import Foundation

@MainActor
struct AssistantLocalGenerator: AssistantGenerating {
    let provider: LLMProvider

    func generate(_ brief: AssistantBrief) async throws -> AssistantProposal {
        #if canImport(MLXLLM) && canImport(MLXLMCommon) && canImport(MLXHuggingFace) && canImport(HuggingFace)
        guard provider == .qwen35_2b || provider == .qwen35_4b else { throw AssistantFailure.modelSetup }
        return try await LLMRuntime.shared.generateAssistantDraft(brief, provider: provider)
        #else
        throw AssistantFailure.modelSetup
        #endif
    }
}
