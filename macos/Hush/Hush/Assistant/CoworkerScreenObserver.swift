import AppKit
import ScreenCaptureKit

/// An on-demand image of the bound source window. No full-desktop capture, disk
/// screenshot, audio capture, or background screen monitoring is used.
@MainActor
enum CoworkerScreenObserver {
    private static var requestedPermission = false

    static func isUseful(request: String, observation: CoworkerObservation) -> Bool {
        let words = Set(request.lowercased().components(separatedBy: CharacterSet.letters.inverted))
        let explicitlyVisual: Set<String> = ["screen", "image", "picture", "chart", "graph", "diagram", "premiere", "bildschirm", "bild"]
        let contextual: Set<String> = ["see", "look", "this", "button", "setting", "click", "schau"]
        let visualExplanation: Set<String> = ["explain", "describe", "why", "how", "erkläre", "warum"]
        let hasPageControls = observation.pageURL != nil && observation.elements.contains {
            $0.url != nil || ["AXTextField", "AXComboBox"].contains($0.role)
        }
        return !words.isDisjoint(with: explicitlyVisual) ||
            (words.contains("video") && (!hasPageControls || !words.isDisjoint(with: visualExplanation))) ||
            (observation.visibleText.isEmpty && !words.isDisjoint(with: contextual))
    }

    static func capture(_ context: CoworkerContext) async throws -> Data {
        guard let application = context.application, let frame = context.windowFrame,
              !application.isTerminated,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier else {
            throw CoworkerError.changedContext
        }
        if !PermissionsChecker.isScreenRecordingGranted {
            if !requestedPermission {
                requestedPermission = true
                guard PermissionsChecker.requestScreenRecording() else { throw ScreenError.permission }
            } else {
                throw ScreenError.permission
            }
        }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        try Task.checkCancellation()
        guard let window = content.windows.first(where: {
            $0.owningApplication?.processID == application.processIdentifier && $0.windowLayer == 0 &&
            abs($0.frame.minX - frame.minX) <= 3 && abs($0.frame.minY - frame.minY) <= 3 &&
            abs($0.frame.width - frame.width) <= 3 && abs($0.frame.height - frame.height) <= 3
        }) else { throw CoworkerError.changedContext }
        let scale = min(1, 1_120 / max(frame.width, frame.height))
        let config = SCStreamConfiguration()
        config.width = max(32, Int(frame.width * scale))
        config.height = max(32, Int(frame.height * scale))
        config.showsCursor = false
        config.capturesAudio = false
        config.ignoreShadowsSingleWindow = true
        let image = try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: config)
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == application.processIdentifier,
              let current = CoworkerAX.element(kAXFocusedWindowAttribute, AXUIElementCreateApplication(application.processIdentifier)),
              CoworkerAX.frame(current) == frame,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw CoworkerError.changedContext
        }
        return data
    }
}

private enum ScreenError: LocalizedError {
    case permission
    var errorDescription: String? { "Allow Hush in System Settings > Privacy & Security > Screen Recording so I can see this window." }
}
