import Foundation
import OSLog

/// Profile-aware post-processor. Behavior is driven by
/// `Settings.shared.llmProvider`:
///
/// - `.off` → light cleanup only (`BasicPostProcessor`: trim + collapse
///   spaces). This is the default — Hush behaves exactly as before the
///   profiles feature landed. Zero network, zero LLM RAM.
///
/// - Apple Intelligence or a local Qwen provider runs cleanup plus the active profile's
///   prompt run through `LLMRuntime`. If the provider isn't ready (model
///   not downloaded, Apple Intelligence not available, etc.), the runtime
///   throws; the coordinator catches that and pastes the raw transcript
///   plus a HUD notice (`DictationCoordinator.runTranscription`).
///
/// The protocol contract (`TextPostProcessor.process(_:language:)`) is
/// unchanged, so wiring this in is a one-line swap on
/// `DictationCoordinator.postProcessor`.
struct LLMPostProcessor: TextPostProcessor {

    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "LLMPostProcessor")

    /// The profile to apply *when an LLM provider is active*. Captured at
    /// processor construction time so the coordinator can swap processors
    /// when the user picks a different profile.
    let profile: Profile
    let provider: LLMProvider

    func process(_ text: String, language: String) async throws -> String {
        let cleaned = try await BasicPostProcessor().process(text, language: language)

        // Provider check is the source of truth for "should we LLM at all?".
        // If the user hasn't picked a provider, behave like the pre-profiles
        // build: just the BasicPostProcessor pass.
        guard provider != .off else {
            return cleaned
        }

        // Route through `LLMRuntime` — handles both Apple Intelligence and
        // Qwen-via-MLX. Errors bubble up; coordinator catches `Error` and
        // falls back to the raw transcript with a HUD notice.
        do {
            let result = try await LLMRuntime.shared.generate(
                transcript: cleaned,
                profile: profile,
                provider: provider
            )
            // Re-run the basic cleanup pass so any whitespace the model
            // added gets normalized. Cheap + idempotent.
            return try await BasicPostProcessor().process(result, language: language)
        } catch let runtimeError as LLMRuntime.Error {
            Self.log.notice("LLM runtime error for profile \"\(profile.name, privacy: .public)\": \(String(describing: runtimeError), privacy: .public)")
            // Re-wrap as our own typed error so the coordinator surfaces a
            // user-facing message via the HUD.
            switch runtimeError {
            case .providerOff:                throw Error.providerOff
            case .notCompiled:                throw Error.runtimeNotInstalled
            case .appleUnsupportedOS:         throw Error.appleNeedsMacOS26
            case .appleUnavailable(let why):  throw Error.appleUnavailable(why)
            case .qwenNotDownloaded:          throw Error.qwenNotDownloaded
            case .qwenBusy:                   throw Error.runtimeBusy
            case .qwenLoadFailed(let msg):    throw Error.loadFailed(msg)
            case .incompleteResponse:         throw Error.incompleteResponse
            }
        }
    }

    enum Error: Swift.Error, LocalizedError {
        case providerOff
        case runtimeNotInstalled
        case runtimeBusy
        case loadFailed(String)
        case appleNeedsMacOS26
        case appleUnavailable(String)
        case qwenNotDownloaded
        case incompleteResponse

        var errorDescription: String? {
            switch self {
            case .providerOff:
                return "AI post-processing is off — pasted raw transcript."
            case .runtimeNotInstalled:
                return "AI runtime isn't installed — pasted raw transcript."
            case .runtimeBusy:
                return "AI model is still loading — pasted raw transcript."
            case .loadFailed(let msg):
                return "AI model couldn't load (\(msg)) — pasted raw."
            case .appleNeedsMacOS26:
                return "Apple Intelligence needs macOS 26 — pasted raw."
            case .appleUnavailable(let reason):
                return "\(reason) Pasted raw transcript."
            case .qwenNotDownloaded:
                return "Download the Qwen model in Settings — pasted raw transcript."
            case .incompleteResponse:
                return "AI response was incomplete - pasted raw transcript."
            }
        }
    }
}

extension LLMPostProcessor {
    /// Factory used by `DictationCoordinator` so it doesn't have to know
    /// about `Profile` shape when picking a post-processor. Returns the
    /// concrete `LLMPostProcessor` bound to the active profile; the
    /// processor's `process()` method itself checks `Settings.llmProvider`
    /// to decide whether to run an LLM.
    static func make(for profile: Profile) -> TextPostProcessor {
        make(for: profile, provider: Settings.shared.llmProvider)
    }

    static func make(for profile: Profile, provider: LLMProvider) -> TextPostProcessor {
        LLMPostProcessor(profile: profile, provider: provider)
    }
}
