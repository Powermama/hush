// Isolated FluidAudio 0.18.0 benchmark executable. See README for package setup.
import Foundation
import CoreML
import FluidAudio
import Darwin

@main struct TTSBench {
    static func now() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e9 }
    static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 4 else { fatalError("Usage: TTSBench kokoro|supertonic MODEL_ROOT OUTPUT_JSON") }
        let engine = args[1], root = URL(fileURLWithPath: args[2], isDirectory: true)
        let output = URL(fileURLWithPath: args[3])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var report: [String: Any] = [
            "engine": engine, "utc": ISO8601DateFormatter().string(from: Date()),
            "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "memory_bytes": ProcessInfo.processInfo.physicalMemory,
            "fluid_audio_commit": "e15287985625dbf544a343df679436789ffb03fb",
            "limitations": "Single developer Mac, uncontrolled background apps. Warm complete-PCM timing includes frontend, excludes playback. No listening panel or WER evaluation. RSS excludes separately allocated system services.",
        ]
        var records: [[String: Any]] = []
        do {
            let setupStart = now()
            let synthesize: (String, String) async throws -> ([Float], Int)
            if engine == "kokoro" {
                let manager = KokoroAneManager(defaultVoice: "af_heart", directory: root, version: .v3)
                try await manager.initialize()
                report["configuration"] = "English af_heart, ANE v3 released hybrid policy, speed 1.0"
                synthesize = { text, _ in
                    let result = try await manager.synthesizeDetailed(text: text, voice: "af_heart", speed: 1)
                    return (result.samples, result.sampleRate)
                }
            } else if engine == "supertonic" {
                let manager = Supertonic3Manager(directory: root, computeUnits: .cpuAndNeuralEngine, vectorEstimator: .aneBucketed(.int4))
                try await manager.initialize()
                let voice = try await Supertonic3ResourceDownloader.loadVoiceStyle(.f1, directory: root)
                report["configuration"] = "F1, ANE-bucketed int4 VectorEstimator, 8 steps, speed 1.0"
                synthesize = { text, language in
                    let result = try await manager.synthesize(text: text, language: language, style: voice, totalSteps: 8, speed: 1)
                    return (result.samples, Supertonic3Constants.sampleRate)
                }
            } else { throw NSError(domain: "Unknown engine", code: 1) }
            report["initialization_including_download_seconds"] = now() - setupStart
            var phrases = [
                ("confirmation", "en", "Your draft is ready. Please review it before sending."),
                ("target", "en", "The download button is in the top right corner."),
                ("files", "en", "I found twelve PDF files and three images in Downloads. You can review the move list before I organize them."),
                ("details", "en", "Friday at ten a.m. works for me. Please send the agenda to sam@example.com."),
            ]
            if engine == "supertonic" {
                phrases.append(("german", "de", "Dein Entwurf ist fertig. Bitte lies ihn vor dem Senden noch einmal durch."))
            }
            for (id, language, text) in phrases {
                for trial in 0..<5 {
                    let start = now()
                    let (samples, rate) = try await synthesize(text, language)
                    let elapsed = now() - start
                    var usage = rusage()
                    getrusage(RUSAGE_SELF, &usage)
                    let duration = Double(samples.count) / Double(rate)
                    let record: [String: Any] = [
                        "case": id, "language": language, "text": text,
                        "trial": trial, "warmup": trial < 2,
                        "complete_pcm_seconds": elapsed,
                        "audio_seconds": duration, "sample_rate": rate,
                        "realtime_factor_inverse": duration / elapsed,
                        "finite": samples.allSatisfy { $0.isFinite },
                        "peak_amplitude": samples.map { abs($0) }.max() ?? 0,
                        "max_rss_bytes_since_launch": usage.ru_maxrss,
                    ]
                    records.append(record)
                    print("\(engine) \(id) trial \(trial): \(elapsed) s for \(duration) s audio")
                }
            }
        } catch {
            report["error"] = String(describing: error)
        }
        report["records"] = records
        let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: output, options: .atomic)
        if report["error"] != nil { exit(1) }
    }
}
