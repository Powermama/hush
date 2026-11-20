import Foundation

/// Local models stay in memory only while a switched-on feature can use them, so turning
/// Live Write and the Assistant off gives their memory back to the Mac.
@MainActor
enum ModelResidency {
    /// Whether a loaded Qwen may stay: Live Write or the Assistant is on and uses it.
    static func keeps(_ model: LLMRuntime.QwenModel, liveWrite: LLMProvider?, assistant: LLMProvider?) -> Bool {
        [liveWrite, assistant].contains { provider in
            provider.flatMap { LLMRuntime.QwenModel(provider: $0) } == model
        }
    }

    /// Unloads what no switched-on feature uses. Speech recognition stays: dictation needs it.
    static func releaseUnused() {
        let settings = Settings.shared
        let liveWrite = settings.activeDictationProfile != nil ? settings.llmProvider : nil
        let assistant = settings.assistantEnabled ? CoworkerModelSettings.provider : nil
        if let model = LLMRuntime.shared.warmQwenModel, !keeps(model, liveWrite: liveWrite, assistant: assistant) {
            LLMRuntime.shared.unloadQwen()
        }
        if !settings.assistantEnabled { Task { await CoworkerVoice.shared.release() } }
    }
}
