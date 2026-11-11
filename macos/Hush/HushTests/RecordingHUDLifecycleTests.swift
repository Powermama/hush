import AppKit
import Testing
@testable import Hush

@Suite("Recording HUD lifecycle", .serialized)
@MainActor
struct RecordingHUDLifecycleTests {
    @Test("Space changes restore a visible HUD but never revive a dismissed session")
    func spaceChangesRespectVisibilityIntent() async throws {
        let controller = RecordingHUDController()
        controller.show(state: .recording)
        defer { controller.hide(animated: false) }
        let window = try #require(NSApp.windows.first { $0 is HUDPanel && $0.isVisible })
        try await Task.sleep(for: .milliseconds(400))
        #expect(window.collectionBehavior.contains(.canJoinAllApplications))
        #expect(window.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!window.canBecomeKey)
        #expect(window.ignoresMouseEvents)
        window.orderOut(nil)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(window.isVisible)
        controller.hide(animated: false)
        NSWorkspace.shared.notificationCenter.post(name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        NotificationCenter.default.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        #expect(!window.isVisible)
    }

    @Test("A pending auto-hide cannot dismiss the next recording")
    func nextRecordingCancelsOldDismissal() async throws {
        let controller = RecordingHUDController()
        controller.show(state: .inserted(words: 2, app: nil, verified: false))
        controller.hideAfter(seconds: 0.1)
        controller.hide(animated: false)
        controller.show(state: .recording)
        defer { controller.hide(animated: false) }
        try await Task.sleep(for: .milliseconds(400))
        #expect(NSApp.windows.contains { $0 is HUDPanel && $0.isVisible })
    }
}
