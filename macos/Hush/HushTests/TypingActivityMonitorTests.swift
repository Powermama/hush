import AppKit
import Combine
import Foundation
import Testing
@testable import Hush

@Suite("Typing monitor responsiveness", .serialized)
@MainActor
struct TypingActivityMonitorTests {
    private final class Permission {
        var allowed = true
        var checks = 0
        func check() -> Bool { checks += 1; return allowed }
    }

    @Test("Stopping tracking does not repeatedly save the same aggregate", arguments: [true, false])
    func permissionLossSettles(disableMeasurement: Bool) async throws {
        let suite = "hush.tests.typing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        settings.everydayTypingMeasurementEnabled = true
        settings.recordEverydayTyping(day: Date(), characterCount: 120, activeDuration: 60)
        let permission = Permission()
        let monitor = TypingActivityMonitor(settings: settings, hasAccessibility: { permission.check() })
        monitor.startObservingSettings()
        defer { monitor.stopAndFlush() }
        var notifications = 0
        let observation = settings.didChange.sink { notifications += 1 }
        permission.allowed = false
        // The same refresh occurs after returning from System Settings.
        if disableMeasurement {
            settings.everydayTypingMeasurementEnabled = false
        } else {
            NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        }
        try await Task.sleep(for: .milliseconds(250))
        let first = notifications
        try await Task.sleep(for: .milliseconds(250))
        let second = notifications
        // Stop observation before checking that shutdown stays stopped.
        monitor.stopAndFlush()
        observation.cancel()
        let checksAfterStop = permission.checks
        settings.didChange.send()
        NotificationCenter.default.post(name: NSApplication.didBecomeActiveNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(permission.checks == checksAfterStop, "A stopped monitor must not restart")
        #expect(first <= 2, "Stopping emitted \(first) settings changes in 250 ms")
        #expect(second == first, "The idle monitor kept publishing: \(first) -> \(second)")
    }

    @Test("Unchanged aggregate does not notify but new typing does")
    func onlyChangedAggregatesPublish() throws {
        let suite = "hush.tests.typing.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = Settings(defaults: defaults)
        var notifications = 0
        let observation = settings.didChange.sink { notifications += 1 }
        defer { observation.cancel() }
        let day = Date()
        settings.recordEverydayTyping(day: day, characterCount: 120, activeDuration: 60)
        settings.recordEverydayTyping(day: day, characterCount: 120, activeDuration: 60)
        #expect(notifications == 1)
        settings.recordEverydayTyping(day: day, characterCount: 121, activeDuration: 61)
        #expect(notifications == 2)
        #expect(settings.everydayTypingSamples.first?.characterCount == 121)
    }
}
