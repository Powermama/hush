import Testing
@testable import Hush

/// Reported 2026-11-20: with Live Write and the Assistant off, the writing model should leave memory.
@Suite("Model residency")
@MainActor
struct ModelResidencyTests {
    @Test("With Live Write and the Assistant off, no Qwen stays in memory")
    func bothOffFreesQwen() {
        #expect(!ModelResidency.keeps(.qwen35_4b, liveWrite: nil, assistant: nil))
        #expect(!ModelResidency.keeps(.qwen35_2b, liveWrite: nil, assistant: nil))
    }

    @Test("A Qwen stays while a switched-on feature uses it")
    func usedQwenStays() {
        #expect(ModelResidency.keeps(.qwen35_4b, liveWrite: .qwen35_4b, assistant: nil))
        #expect(ModelResidency.keeps(.qwen35_4b, liveWrite: nil, assistant: .qwen35_4b))
        #expect(ModelResidency.keeps(.qwen35_2b, liveWrite: .qwen35_4b, assistant: .qwen35_2b))
    }

    @Test("Features on ChatGPT or Apple Intelligence keep no Qwen, nor does a different variant")
    func otherEnginesFreeQwen() {
        #expect(!ModelResidency.keeps(.qwen35_4b, liveWrite: .chatGPT, assistant: .chatGPT))
        #expect(!ModelResidency.keeps(.qwen35_4b, liveWrite: .appleIntelligence, assistant: nil))
        #expect(!ModelResidency.keeps(.qwen35_4b, liveWrite: .qwen35_2b, assistant: nil))
    }
}
