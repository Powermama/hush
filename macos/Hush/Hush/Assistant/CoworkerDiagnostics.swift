#if DEBUG
import AppKit
import Foundation

/// Development builds only. No persisted enable flag, uploads, or audio recording.
/// Every hook and this entire implementation are excluded from Release compilation.
@MainActor
final class CoworkerDiagnostics {
    static let shared = CoworkerDiagnostics()
    var enabled = ProcessInfo.processInfo.arguments.contains("--assistant-diagnostics") {
        didSet { if !enabled { stopRecordings.forEach { $0() }; stopRecordings.removeAll() } }
    }
    private var stopRecordings: [() -> Void] = []
    static var directory: URL {
        if let path = ProcessInfo.processInfo.environment["HUSH_ASSISTANT_TRACE_ROOT"] {
            return URL(fileURLWithPath: path, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Hush/Development/AssistantTraces", isDirectory: true)
    }

    func begin(id: UUID, application: NSRunningApplication?) -> CoworkerTrace? {
        guard enabled else { return nil }
        let trace = CoworkerTrace(id: id, root: Self.directory)
        stopRecordings.append { [weak trace] in trace?.disable() }
        trace.event("turn.started", [
            "app": application?.bundleIdentifier ?? "none",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "build": Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unknown",
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "memory_bytes": String(ProcessInfo.processInfo.physicalMemory),
            "writer": CoworkerModelSettings.provider.rawValue,
            "transcriber": Settings.shared.modelID,
            "voice": "kokoro-82m-coreml-v3/af_heart",
            "accessibility": String(AXIsProcessTrusted()),
            "screen_recording": String(CGPreflightScreenCaptureAccess())
        ])
        return trace
    }

    /// Records the actual bound editor metadata, without traversing other windows.
    static func binding(_ application: NSRunningApplication?) -> [String: String] {
        guard AXIsProcessTrusted() else { return ["reason": "accessibility_not_granted"] }
        guard let application else { return ["reason": "no_source_application"] }
        let app = AXUIElementCreateApplication(application.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.08)
        guard let field = CoworkerAX.element(kAXFocusedUIElementAttribute, app) else {
            return ["reason": "no_focused_element"]
        }
        let role = CoworkerAX.string(kAXRoleAttribute, field) ?? "missing"
        let subrole = CoworkerAX.string(kAXSubroleAttribute, field) ?? "none"
        if subrole == kAXSecureTextFieldSubrole { return ["reason": "secure_field", "role": role] }
        var settable = DarwinBoolean(false)
        let result = AXUIElementIsAttributeSettable(field, kAXSelectedTextRangeAttribute as CFString, &settable)
        var rawValue: CFTypeRef?
        let valueStatus = AXUIElementCopyAttributeValue(field, kAXValueAttribute as CFString, &rawValue)
        let value = rawValue as? String
        let characters = CoworkerAX.attribute(kAXNumberOfCharactersAttribute, field) as? NSNumber
        let range = CoworkerAX.range(field)
        return ["role": role, "subrole": subrole, "value_present": String(value != nil),
                "value_utf16_count": String(value?.utf16.count ?? -1),
                "value_ax_status": String(valueStatus.rawValue),
                "reported_characters": characters.map { $0.stringValue } ?? "missing",
                "selection": range.map { "\($0.location):\($0.length)" } ?? "missing",
                "selection_settable": String(settable.boolValue), "selection_settable_ax_status": String(result.rawValue),
                "focused_window": String(CoworkerAX.element(kAXFocusedWindowAttribute, app) != nil),
                "frontmost_matches": String(NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier)]
    }
}

/// A single serial writer owns file access. A trace is immutable outside that queue.
/// Per-turn and global retention limits apply to artifacts as well as the timeline.
nonisolated final class CoworkerTrace: @unchecked Sendable {
    enum Artifact: String {
        case context = "context.json", transcript = "transcript.txt", replay = "replay.json"
        case system = "system.txt", prompt = "prompt.json", screenshot = "model-screen.png"
        case rawReply = "model-output.txt", reply = "reply.json"
    }
    private static let queue = DispatchQueue(label: "hush.development.assistant-traces", qos: .utility)
    static let maximumTurns = 5
    static let maximumBytes = 20 * 1_024 * 1_024
    static let maximumTurnBytes = 4 * 1_024 * 1_024
    static let maximumAge: TimeInterval = 24 * 60 * 60
    let id: UUID
    let directory: URL
    private let root: URL
    private let started = Date()
    private var events: [[String: Any]] = []
    private var artifactSizes: [String: Int] = [:]
    private var initialized = false
    private var failed = false
    private var ended = false
    private var accepting = true
    private var step = 0

    init(id: UUID, root: URL) {
        self.id = id; self.root = root
        self.directory = root.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    func event(_ stage: String, _ fields: [String: String] = [:]) {
        Self.queue.async { [self] in
            guard accepting, !failed, events.count < 160 else { return }
            do {
                try prepare()
                events.append(["elapsed_ms": Int(Date().timeIntervalSince(started) * 1_000),
                               "stage": stage, "fields": fields.mapValues { String($0.prefix(2_000)) }])
                try persist()
            } catch { failed = true; NSLog("Hush development trace write failed: %@", error.localizedDescription) }
        }
    }

    func failure(_ stage: String, _ error: Error) {
        let value = error as NSError
        event(stage, ["error_type": String(reflecting: type(of: error)), "error": String(describing: error),
                      "domain": value.domain, "code": String(value.code), "description": error.localizedDescription])
    }

    /// Preserve each observation/model input instead of overwriting earlier evidence.
    /// The first step retains the original replay filenames for existing tooling.
    func beginStep(_ index: Int) {
        Self.queue.async { [self] in step = max(0, index) }
    }

    func artifact(_ kind: Artifact, _ data: Data) {
        Self.queue.async { [self] in
            guard accepting, !failed else { return }
            do {
                try prepare()
                let name = step == 0 ? kind.rawValue : "step-\(step + 1)-\(kind.rawValue)"
                let bytes = artifactSizes.values.reduce(0, +) - (artifactSizes[name] ?? 0) + data.count
                guard data.count <= 2 * 1_024 * 1_024, bytes <= Self.maximumTurnBytes else {
                    events.append(["elapsed_ms": Int(Date().timeIntervalSince(started) * 1_000),
                                   "stage": "artifact.omitted", "fields": ["artifact": name, "reason": "storage_limit"]])
                    try persist(); return
                }
                let file = directory.appendingPathComponent(name)
                try data.write(to: file, options: .atomic)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                artifactSizes[name] = data.count
                try persist()
            } catch { failed = true; NSLog("Hush development artifact write failed: %@", error.localizedDescription) }
        }
    }

    func artifact(_ kind: Artifact, text: String) { artifact(kind, Data(text.utf8)) }
    func encoded<T: Encodable>(_ kind: Artifact, _ value: T) {
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            artifact(kind, try encoder.encode(value))
        } catch { failure("artifact.encoding_failed", error) }
    }

    func finish(_ outcome: String) {
        Self.queue.async { [self] in
            guard accepting, !ended, !failed else { return }
            ended = true
            do {
                try prepare()
                events.append(["elapsed_ms": Int(Date().timeIntervalSince(started) * 1_000),
                               "stage": "turn.finished", "fields": ["outcome": outcome]])
                try persist()
            } catch { failed = true }
        }
    }

    func flush() async { await withCheckedContinuation { continuation in Self.queue.async { continuation.resume() } } }

    func disable() {
        Self.queue.async { [self] in
            accepting = false
            guard initialized, !failed else { return }
            ended = true
            events.append(["elapsed_ms": Int(Date().timeIntervalSince(started) * 1_000),
                           "stage": "diagnostics.disabled", "fields": [:] as [String: String]])
            try? persist()
        }
    }

    private func prepare() throws {
        guard !initialized else { return }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try root.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw CocoaError(.fileWriteNoPermission) }
        try manager.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        initialized = true
    }

    private func persist() throws {
        let report: [String: Any] = ["schema_version": 1, "turn_id": id.uuidString,
            "started": ISO8601DateFormatter().string(from: started), "finished": ended,
            "events": events, "artifacts": artifactSizes,
            "scope": "Development only; local; no audio; model screenshot only when actually supplied."]
        let file = directory.appendingPathComponent("trace.json")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try prune()
    }

    private func prune() throws {
        let manager = FileManager.default
        let entries = try manager.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey, .isSymbolicLinkKey])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
        func size(_ url: URL) -> Int {
            (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey]))?
                .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) } ?? 0
        }
        let ordered = entries.sorted { lhs, rhs in
            let left = (try? lhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            let right = (try? rhs.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            return left < right
        }
        var count = ordered.count, bytes = ordered.reduce(0) { $0 + size($1) }
        for entry in ordered where entry != directory {
            let date = (try? entry.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
            if count > Self.maximumTurns || bytes > Self.maximumBytes || Date().timeIntervalSince(date) > Self.maximumAge {
                let removed = size(entry)
                try manager.removeItem(at: entry); count -= 1; bytes -= removed
            }
        }
    }
}

/// Model-only replay: contains the exact model inputs, never an executable target.
struct CoworkerReplaySnapshot: Codable, Sendable {
    let request: String
    let observation: CoworkerObservation
    let history: [CoworkerTurn]
    let now: Date
    let timeZone: String
    let provider: String
    let validationFeedback: String?
    let hasScreenshot: Bool
    var checkpoints: [CoworkerProgress.Checkpoint]? = nil

    init(_ input: CoworkerRequest, provider: LLMProvider) {
        request = input.text; observation = input.observation; history = input.history
        now = input.now; timeZone = input.timeZone.identifier; self.provider = provider.rawValue
        validationFeedback = input.validationFeedback; hasScreenshot = input.screenshot != nil
        checkpoints = input.checkpoints
    }

    func input(screenshot: Data?) throws -> CoworkerRequest {
        guard hasScreenshot == (screenshot != nil), let zone = TimeZone(identifier: timeZone) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return CoworkerRequest(text: request, observation: observation, history: history, now: now,
                               timeZone: zone, validationFeedback: validationFeedback, screenshot: screenshot, checkpoints: checkpoints ?? [])
    }
}
#endif
