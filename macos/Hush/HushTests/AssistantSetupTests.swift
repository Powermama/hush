import Testing
@testable import Hush

struct AssistantSetupTests {
    @Test func missingModelNeverReportsReadyDespiteAllPermissions() {
        let setup = AssistantSetupSnapshot(intelligence: false, transcription: true, voice: true,
                                           microphone: true, accessibility: true, screen: true)
        #expect(!setup.ready)
        #expect(setup.remaining == 1)
        #expect(setup.title == "Set up your assistant")
    }
    @Test func voiceNeedsValidationBeforeSetupIsReady() {
        let setup = AssistantSetupSnapshot(intelligence: true, transcription: true, voice: false,
                                           microphone: true, accessibility: true, screen: true)
        #expect(!setup.ready)
        #expect(setup.remaining == 1)
    }
    @Test func completeSetupAndFirstRunHaveDifferentGuidance() {
        let fresh = AssistantSetupSnapshot(intelligence: false, transcription: false, voice: false,
                                           microphone: false, accessibility: false, screen: false)
        #expect(fresh.remaining == 6)
        let ready = AssistantSetupSnapshot(intelligence: true, transcription: true, voice: true,
                                           microphone: true, accessibility: true, screen: true)
        #expect(ready.ready)
        #expect(ready.title == "Ready when you are")
    }
}
