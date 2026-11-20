import Testing
@testable import Hush

/// ⌃ Fn starts the assistant when its models are ready, and opens setup otherwise.
@Suite("Assistant readiness")
struct AssistantReadinessTests {
    @Test("A connected ChatGPT plan is ready: ⌃ Fn listens instead of opening settings")
    func chatGPTReady() {
        #expect(AssistantSetupSnapshot.modelsInstalled(provider: .chatGPT, intelligenceReady: true, speechAvailable: true,
                                                       voiceEnabled: true, voiceAvailable: true))
    }

    @Test("ChatGPT not connected, or no model chosen, still opens setup")
    func chatGPTNotConnected() {
        #expect(!AssistantSetupSnapshot.modelsInstalled(provider: .chatGPT, intelligenceReady: false, speechAvailable: true,
                                                        voiceEnabled: true, voiceAvailable: true))
    }

    @Test("Speech recognition and, when spoken replies are on, the voice are needed with every engine")
    func speechAndVoice() {
        for provider in [LLMProvider.chatGPT, .qwen35_4b] {
            #expect(!AssistantSetupSnapshot.modelsInstalled(provider: provider, intelligenceReady: true, speechAvailable: false,
                                                            voiceEnabled: false, voiceAvailable: true))
            #expect(!AssistantSetupSnapshot.modelsInstalled(provider: provider, intelligenceReady: true, speechAvailable: true,
                                                            voiceEnabled: true, voiceAvailable: false))
            #expect(AssistantSetupSnapshot.modelsInstalled(provider: provider, intelligenceReady: true, speechAvailable: true,
                                                           voiceEnabled: false, voiceAvailable: false))
        }
    }
}

/// Reported 2026-11-20: with the Assistant switched off, ⌃ Fn still started it and it answered.
@Suite("Assistant switch")
struct AssistantSwitchTests {
    @Test("Switched off, ⌃ Fn never starts the assistant, even when every model is ready")
    func offNeverStarts() {
        #expect(AssistantEntry.decide(enabled: false, ready: true) == .off)
        #expect(AssistantEntry.decide(enabled: false, ready: false) == .off)
    }

    @Test("Switched on, ⌃ Fn starts when ready and opens setup otherwise")
    func onStartsOrSetsUp() {
        #expect(AssistantEntry.decide(enabled: true, ready: true) == .start)
        #expect(AssistantEntry.decide(enabled: true, ready: false) == .setup)
    }
}
