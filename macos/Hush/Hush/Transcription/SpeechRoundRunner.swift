import Foundation
import os

/// Runs `SpeechRounds` while a dictation is recorded (PRD R9, stage 2): every 0.4 s, once
/// speech is heard, Parakeet transcribes the recording so far. At release only the last
/// stretch is transcribed. Any miss falls back to whole-file recognition, so a dictation is
/// never worse than without rounds. Adopted for everyone after its gate passed
/// (SpeechRoundsBenchmark: 97% identical text, p90 wait after release 79 ms against 219 ms).
@MainActor
final class SpeechRoundRunner {
    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "SpeechRounds")
    private static let sampleRate = AudioRecorder.targetSampleRate
    /// The HUD level (peak × 1.5) above which the recording counts as speech, about -36 dBFS.
    private static let speechLevel: Float = 0.025

    /// On unless switched off with `-speech.rounds.enabled NO` (for measuring without it).
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "speech.rounds.enabled") as? Bool ?? true }

    private let transcriber: FluidAudioTranscriber
    private let language: String
    private let recorder: AudioRecorder
    private var rounds = SpeechRounds()
    private var ticker: Task<Void, Never>?
    private var inFlight: Task<Void, Never>?
    private var heardSpeech = false
    private(set) var completedRounds = 0

    /// Nil for speech engines without token timings (Whisper) or when switched off.
    init?(transcriber: Transcriber, language: String, recorder: AudioRecorder) {
        guard Self.isEnabled, let parakeet = transcriber as? FluidAudioTranscriber else { return nil }
        self.transcriber = parakeet
        self.language = language
        self.recorder = recorder
    }

    func start() {
        let interval = rounds.plan.interval
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(interval))
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
    }

    /// Starts a round unless one is still running: a skipped tick costs nothing, a queued
    /// one would delay the release.
    private func tick() {
        guard inFlight == nil else { return }
        if !heardSpeech { heardSpeech = recorder.currentLevel > Self.speechLevel }
        guard heardSpeech else { return }
        let heard = Double(recorder.recordedSampleCount) / Self.sampleRate
        guard let window = rounds.roundWindow(heard: heard) else { return }
        let samples = recorder.recordedSamples(in: Self.range(window))
        let language = language, transcriber = transcriber
        inFlight = Task { [weak self] in
            let words = try? await transcriber.transcribeWords(samples: samples, language: language, offset: window.start)
            guard let self else { return }
            if let words {
                self.rounds.accept(round: words, window: window)
                self.completedRounds += 1
            }
            self.inFlight = nil
        }
    }

    /// The transcript at release, or nil when whole-file recognition should decide.
    func finish(samples: [Float]) async -> String? {
        ticker?.cancel()
        // The speech model is an actor without cancellation: a running round is awaited.
        await inFlight?.value
        guard completedRounds > 0 else { return nil }
        let end = Double(samples.count) / Self.sampleRate
        let window = rounds.releaseWindow(end: end)
        let range = Self.range(window)
        let slice = Array(samples[min(range.lowerBound, samples.count) ..< min(range.upperBound, samples.count)])
        do {
            let words = try await transcriber.transcribeWords(samples: slice, language: language, offset: window.start)
            let text = rounds.transcript(release: words, end: end)
            Self.log.info("Release used \(self.completedRounds) rounds; transcribed \(window.end - window.start, format: .fixed(precision: 1)) of \(end, format: .fixed(precision: 1)) s")
            return text.isEmpty ? nil : text
        } catch {
            Self.log.notice("Release pass failed, using whole-file recognition: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func cancel() {
        ticker?.cancel()
        ticker = nil
    }

    private static func range(_ window: SpeechRounds.Window) -> Range<Int> {
        Int(window.start * sampleRate) ..< Int(window.end * sampleRate)
    }
}
