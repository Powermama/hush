import AppKit
import Testing
@testable import Hush

@MainActor
@Suite("Onboarding components", .serialized)
struct OnboardingComponentTests {
    @Test("The flow opens with the reference value proposition and one action")
    func welcomePage() {
        let flow = makeFlow()

        #expect(flow.page == .welcome)
        #expect(flow.headlinePhrases == [
            "does the typing.",
            "ships it with personas.",
            "proves its origin.",
        ])
        #expect(flow.primaryTitle == "Continue")
        #expect(flow.primaryEnabled)
        #expect(flow.footerMessage == "You’ll be ready in under a minute.")
    }

    @Test("Voice permissions stay contextual and both are required for the practice")
    func contextualVoiceSetup() {
        let flow = makeFlow()
        flow.goForward()

        #expect(flow.page == .voice)
        #expect(flow.permissionSheetPresented == false)
        #expect(flow.primaryEnabled == false)

        flow.tapMicrophone()
        #expect(flow.permissionSheetPresented)
        #expect(flow.permissionsReady == false)

        flow.requestMicrophone()
        #expect(flow.microphoneReady)
        #expect(flow.permissionsReady == false)

        flow.requestAccessibility()
        #expect(flow.accessibilityReady)
        #expect(flow.permissionsReady)
    }

    @Test("Personas and proof stay optional without adding extra pages")
    func optionalCapabilities() {
        let flow = makeFlow()
        flow.page = .personas
        flow.togglePersonas(false)
        flow.toggleProof(false)

        #expect(flow.primaryTitle == "Skip")
        #expect(flow.primaryEnabled)

        flow.goForward()
        #expect(flow.page == .proof)
        #expect(flow.proofState == .off)
        #expect(flow.primaryTitle == "Set up hush")
        #expect(flow.primaryEnabled)
    }

    @Test("Finishing gathers the local setup before opening Hush")
    func completionHandoff() {
        let flow = makeFlow()
        flow.page = .proof

        flow.goForward()

        #expect(flow.isCompletingSetup)
        #expect(flow.primaryEnabled == false)
        flow.stop()
    }

    @Test("The onboarding window matches the 1280 by 860 reference canvas")
    func windowGeometry() {
        let controller = OnboardingWindowController(
            coordinator: DictationCoordinator(),
            onFinish: {}
        )

        #expect(controller.window?.contentView?.frame.size == NSSize(width: 1280, height: 860))
        #expect(controller.window?.minSize == NSSize(width: 980, height: 700))
        #expect(controller.window?.maxSize == NSSize(width: 1440, height: 960))
        #expect(controller.window?.title == "Welcome to hush")
    }

    private func makeFlow() -> OnboardingFlowModel {
        OnboardingFlowModel(coordinator: nil, onFinish: {}, isUITest: true)
    }
}
