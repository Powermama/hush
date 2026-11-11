import AppKit
import Carbon.HIToolbox
import Combine
import CoreGraphics

/// Builds a privacy-preserving estimate of everyday typing speed.
///
/// The event tap is opt-in and listen-only. It classifies text-producing key
/// events, but never reads or stores characters, key identities, app names, or
/// text-field contents. Persistence is limited to daily aggregate key counts
/// and active typing seconds.
@MainActor
final class TypingActivityMonitor {
    static let shared = TypingActivityMonitor()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var subscriptions = Set<AnyCancellable>()
    private var activationObserver: NSObjectProtocol?

    private var day = Calendar.current.startOfDay(for: Date())
    private var characterCount = 0
    private var activeDuration: TimeInterval = 0
    private var lastKeyAt: Date?
    private var lastFlushAt = Date.distantPast
    private var lastFlushedCharacterCount = 0

    private let maximumActiveGap: TimeInterval = 5
    private let settings: Settings
    private let hasAccessibility: @MainActor () -> Bool

    private convenience init() {
        self.init(settings: .shared, hasAccessibility: { PermissionsChecker.isAccessibilityGranted })
    }

    init(settings: Settings, hasAccessibility: @escaping @MainActor () -> Bool) {
        self.settings = settings
        self.hasAccessibility = hasAccessibility
    }

    func startObservingSettings() {
        guard subscriptions.isEmpty else { return }
        settings.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.updateMonitoringState() }
            .store(in: &subscriptions)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateMonitoringState() }
        }
        updateMonitoringState()
    }

    func stopAndFlush() {
        subscriptions.removeAll()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        stopEventTap()
    }

    private func updateMonitoringState() {
        guard !subscriptions.isEmpty else { return }
        let shouldRun = settings.everydayTypingMeasurementEnabled
            && hasAccessibility()
        if shouldRun {
            startEventTapIfNeeded()
        } else {
            stopEventTap()
        }
    }

    private func startEventTapIfNeeded() {
        guard eventTap == nil else { return }
        loadToday()
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<TypingActivityMonitor>.fromOpaque(userInfo).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    Task { @MainActor in monitor.enableEventTap() }
                    return Unmanaged.passUnretained(event)
                }
                guard type == .keyDown else { return Unmanaged.passUnretained(event) }
                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                let flags = event.flags
                Task { @MainActor in monitor.handleKeyDown(keyCode: keyCode, flags: flags) }
                return Unmanaged.passUnretained(event)
            },
            userInfo: userInfo
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func enableEventTap() {
        guard let eventTap else { return }
        CGEvent.tapEnable(tap: eventTap, enable: true)
    }

    private func stopEventTap() {
        flush()
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        runLoopSource = nil
        eventTap = nil
        lastKeyAt = nil
    }

    private func handleKeyDown(keyCode: Int64, flags: CGEventFlags) {
        guard settings.everydayTypingMeasurementEnabled,
              Self.textKeyCodes.contains(keyCode),
              !flags.contains(.maskCommand),
              !flags.contains(.maskControl),
              NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier else {
            return
        }

        let now = Date()
        let today = Calendar.current.startOfDay(for: now)
        if today != day {
            flush()
            day = today
            characterCount = 0
            activeDuration = 0
            lastFlushedCharacterCount = 0
            lastKeyAt = nil
        }

        if let lastKeyAt {
            let interval = now.timeIntervalSince(lastKeyAt)
            if interval <= maximumActiveGap {
                activeDuration += max(0, interval)
            }
        }
        characterCount += 1
        lastKeyAt = now

        if characterCount - lastFlushedCharacterCount >= 25
            || now.timeIntervalSince(lastFlushAt) >= 20 {
            flush()
        }
    }

    private func loadToday() {
        day = Calendar.current.startOfDay(for: Date())
        let existing = settings.everydayTypingSamples.first {
            Calendar.current.isDate($0.day, inSameDayAs: day)
        }
        characterCount = existing?.characterCount ?? 0
        activeDuration = existing?.activeDuration ?? 0
        lastFlushedCharacterCount = characterCount
    }

    private func flush() {
        // Saving publishes a settings change, which refreshes monitoring. A clean
        // aggregate must not publish again when permission is lost or tracking stops.
        guard characterCount > lastFlushedCharacterCount else { return }
        lastFlushAt = Date()
        lastFlushedCharacterCount = characterCount
        settings.recordEverydayTyping(
            day: day,
            characterCount: characterCount,
            activeDuration: activeDuration
        )
    }

    private static let textKeyCodes: Set<Int64> = Set([
        kVK_ANSI_A, kVK_ANSI_B, kVK_ANSI_C, kVK_ANSI_D, kVK_ANSI_E, kVK_ANSI_F,
        kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_I, kVK_ANSI_J, kVK_ANSI_K, kVK_ANSI_L,
        kVK_ANSI_M, kVK_ANSI_N, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_Q, kVK_ANSI_R,
        kVK_ANSI_S, kVK_ANSI_T, kVK_ANSI_U, kVK_ANSI_V, kVK_ANSI_W, kVK_ANSI_X,
        kVK_ANSI_Y, kVK_ANSI_Z,
        kVK_ANSI_0, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4,
        kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
        kVK_ANSI_Equal, kVK_ANSI_Minus, kVK_ANSI_RightBracket, kVK_ANSI_LeftBracket,
        kVK_ANSI_Quote, kVK_ANSI_Semicolon, kVK_ANSI_Backslash, kVK_ANSI_Comma,
        kVK_ANSI_Slash, kVK_ANSI_Period, kVK_ANSI_Grave,
        kVK_Space, kVK_Return,
        kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3,
        kVK_ANSI_Keypad4, kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7,
        kVK_ANSI_Keypad8, kVK_ANSI_Keypad9, kVK_ANSI_KeypadDecimal,
        kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadMinus,
        kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEquals, kVK_ANSI_KeypadEnter,
    ].map(Int64.init))
}
