import AVFoundation
import FluidAudio
import NaturalLanguage
import Combine

@MainActor
protocol CoworkerSpeaking: AnyObject {
    var onStatus: ((String) -> Void)? { get set }
    var onUtterance: ((String?) -> Void)? { get set }
    func prepare() async throws
    func speak(_ text: String) async throws
    func stop()
}

extension CoworkerSpeaking {
    var onUtterance: ((String?) -> Void)? {
        get { nil }
        set { }
    }
}

/// One local Kokoro instance. Audio stays in memory and is never retained as a file.
@MainActor
final class CoworkerVoice: CoworkerSpeaking {
    static let shared = CoworkerVoice()
    enum SetupState: Equatable { case unchecked, preparing, ready, failed(String) }
    let setupState = CurrentValueSubject<SetupState, Never>(.unchecked)
    let setupProgress = CurrentValueSubject<VoicePreparationProgress, Never>(.checking)

    /// Presence is only a hint. The SDK validates and compiles the assets when
    /// setup runs; a directory is never advertised as Ready.
    static var hasCachedAssets: Bool {
        let folder = AIModelStorage.fluidAudioRoot.appendingPathComponent("kokoro-82m-coreml/ANE-v3")
        return !((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty
    }
    var onStatus: ((String) -> Void)?
    var onUtterance: ((String?) -> Void)?
    private var manager = KokoroAneManager(defaultVoice: "af_heart", directory: AIModelStorage.fluidAudioRoot, version: .v3)
    private var removing = false
    private var preparation: Task<Void, Error>?
    private var prepared = false
    private var synthesis: Task<Data, Error>?
    private var player: AVAudioPlayer?
    private var playbackID = UUID()

    func prepare() async throws {
        guard !removing else { throw CancellationError() }
        if prepared { return }
        if let preparation { return try await preparation.value }
        setupState.send(.preparing)
        onStatus?("Preparing Kokoro voice. First use downloads its model.")
        setupProgress.send(.checking)
        let task = Task {
            try await KokoroAneResourceDownloader.ensureG2PAssets(directory: AIModelStorage.fluidAudioRoot) { [weak self] progress in
                Task { @MainActor [weak self] in
                    guard let self, self.setupState.value == .preparing else { return }
                    switch progress.phase {
                    case .listing: self.setupProgress.send(.pronunciation(nil))
                    case .downloading: self.setupProgress.send(.pronunciation(Int(min(1, max(0, progress.fractionCompleted)) * 100)))
                    case .compiling: self.setupProgress.send(.loading)
                    }
                }
            }
            try Task.checkCancellation()
            let observer = Task { [weak self] in
                await VoiceTransferObserver.observe(session: ModelHub.session) { [weak self] progress in
                    guard let self, self.setupState.value == .preparing else { return }
                    self.setupProgress.send(progress)
                }
            }
            defer { observer.cancel() }
            try await manager.initialize(preloadVoices: ["af_heart"])
            observer.cancel()
            await observer.value
            setupProgress.send(.warming)
            try Task.checkCancellation()
            // Compile a representative short-response path while the user is speaking
            // or the writer is working. Discard this audio; it is never played or stored.
            _ = try await manager.synthesize(text: "I'm ready. Tell me what you would like to change.", voice: "af_heart")
        }
        preparation = task
        do {
            try await task.value
            try Task.checkCancellation()
            prepared = true
            preparation = nil
            setupState.send(.ready)
            onStatus?("Kokoro · English · On this Mac")
        } catch {
            preparation = nil
            setupState.send(error is CancellationError ? .unchecked : .failed(error.localizedDescription))
            onStatus?("Voice unavailable. Ask Hush again to retry.")
            throw error
        }
    }

    func speak(_ text: String) async throws {
        stop()
        let id = playbackID
        if text.count > 80, let language = NLLanguageRecognizer.dominantLanguage(for: text), language != .english {
            throw CoworkerError.voiceLanguage
        }
        try await prepare()
        try Task.checkCancellation()
        guard playbackID == id else { throw CancellationError() }
        let chunks = Self.chunks(text)
        guard let first = chunks.first else { return }
        synthesis = Task { try await manager.synthesize(text: first, voice: "af_heart") }
        defer {
            if playbackID == id {
                synthesis?.cancel(); synthesis = nil
                player?.stop(); player = nil
                onUtterance?(nil)
            }
        }
        for index in chunks.indices {
            try Task.checkCancellation()
            guard playbackID == id, let pending = synthesis else { throw CancellationError() }
            let data = try await pending.value
            try Task.checkCancellation()
            guard playbackID == id else { throw CancellationError() }
            // At most one chunk ahead, so synthesis overlaps the current audio without
            // queuing an entire response or allowing cancelled audio to play later.
            if index + 1 < chunks.count {
                let next = chunks[index + 1]
                synthesis = Task { try await manager.synthesize(text: next, voice: "af_heart") }
            } else { synthesis = nil }
            let audio = try AVAudioPlayer(data: data)
            player = audio
            guard audio.prepareToPlay(), audio.play() else { throw CocoaError(.fileReadCorruptFile) }
            onUtterance?(chunks[index])
            while audio.isPlaying {
                try await Task.sleep(for: .milliseconds(20))
                guard playbackID == id else { throw CancellationError() }
            }
        }
    }

    func stop() {
        playbackID = UUID()
        synthesis?.cancel(); synthesis = nil
        player?.stop(); player = nil
        onUtterance?(nil)
    }

    func cancelPreparation() { preparation?.cancel() }

    func removeModel() async throws {
        guard !removing else { throw AIModelLibrary.LibraryError.busy }
        removing = true
        defer { removing = false }
        let pendingAudio = synthesis
        let pendingPreparation = preparation
        stop()
        pendingPreparation?.cancel()
        _ = try? await pendingPreparation?.value
        _ = try? await pendingAudio?.value
        await manager.cleanup()
        prepared = false
        preparation = nil
        manager = KokoroAneManager(defaultVoice: "af_heart", directory: AIModelStorage.fluidAudioRoot, version: .v3)
        do {
            try VoiceModelFiles.remove(in: AIModelStorage.fluidAudioRoot)
            setupState.send(.unchecked)
        } catch {
            setupState.send(.failed(error.localizedDescription))
            throw error
        }
    }

    nonisolated static func chunks(_ text: String) -> [String] {
        var chunks: [String] = [], current = ""
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if !current.isEmpty, current.count + word.count > 180 { chunks.append(current); current = "" }
            if !current.isEmpty { current += " " }
            current += word
            if current.count >= 35, let last = word.last, ".!?".contains(last) { chunks.append(current); current = "" }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }
}
