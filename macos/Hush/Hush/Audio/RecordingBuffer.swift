import Foundation

/// The samples of one recording, capped at a duration. Reaching the cap keeps everything
/// recorded until then; only later audio is dropped (PRD R1: no dictation is ever lost).
/// Counted in samples, not wall-clock time, so the cap is exact and testable.
struct RecordingBuffer {
    private let capacity: Int
    private(set) var samples: [Float] = []
    private(set) var reachedLimit = false

    init(maxDuration: TimeInterval, sampleRate: Double) {
        capacity = max(1, Int(maxDuration * sampleRate))
    }

    /// Appends frames up to the cap. Returns true only for the append that reaches it.
    @discardableResult
    mutating func append<Frames: Collection>(_ frames: Frames) -> Bool where Frames.Element == Float {
        guard !reachedLimit else { return false }
        let room = capacity - samples.count
        samples.append(contentsOf: frames.prefix(room))
        guard samples.count >= capacity else { return false }
        reachedLimit = true
        return true
    }

    /// Hands over the recording and starts the next one empty.
    mutating func take() -> [Float] {
        defer { samples = []; reachedLimit = false }
        return samples
    }
}
