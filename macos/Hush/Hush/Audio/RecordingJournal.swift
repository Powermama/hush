import Foundation
import os

/// Keeps each dictation's audio on disk until its text is safely inserted (PRD R1), so a
/// crash, a sleep or a force quit never loses what the user said.
///
/// While recording, every block of audio is appended to `<id>.f32.partial` as raw 16 kHz
/// mono Float32, which stays readable at any moment because there is no header to finish.
/// When the recording ends it is renamed to `<id>.f32`; once its text is inserted it is
/// deleted. Whatever is left at the next launch is an interrupted dictation to recover.
/// Handy writes recordings aside and renames them too, but only after capture ends.
@MainActor
final class RecordingJournal {
    private static let log = Logger(subsystem: "com.decentralfreedom.hush", category: "RecordingJournal")
    static let partialExtension = "partial"
    static let audioExtension = "f32"
    /// Older recordings beyond this many are removed, so the folder can never grow without bound.
    static let keepLimit = 10

    struct Entry: Equatable {
        let id: UUID
        let url: URL
        let date: Date
        /// The recording was still running when hush stopped.
        let wasInterrupted: Bool
    }

    let directory: URL
    private var handle: FileHandle?
    private(set) var activeID: UUID?

    init(directory: URL = RecordingJournal.defaultDirectory) {
        self.directory = directory
    }

    /// Tests and previews never touch the user's recordings.
    nonisolated static var defaultDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if environment["HUSH_TEST_HOST"] == "1" || environment["XCTestConfigurationFilePath"] != nil {
            return FileManager.default.temporaryDirectory.appendingPathComponent("hush-recordings-\(ProcessInfo.processInfo.processIdentifier)")
        }
        return AIModelStorage.root.deletingLastPathComponent().appendingPathComponent("Recordings", isDirectory: true)
    }

    /// Opens a new recording file. A failure only means this dictation has no copy on disk.
    func begin() {
        finish()
        let id = UUID()
        let url = partialURL(id)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
            handle = try FileHandle(forWritingTo: url)
            activeID = id
        } catch {
            Self.log.error("Could not start the recording file: \(error.localizedDescription, privacy: .public)")
        }
    }

    func append(_ samples: some Collection<Float>) {
        guard let handle, !samples.isEmpty else { return }
        let data = Array(samples).withUnsafeBufferPointer { Data(buffer: $0) }
        do { try handle.write(contentsOf: data) } catch {
            Self.log.error("Could not write the recording: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Closes the file and marks the recording complete. Returns its id.
    @discardableResult
    func finish() -> UUID? {
        guard let id = activeID else { return nil }
        try? handle?.close()
        handle = nil
        activeID = nil
        try? FileManager.default.moveItem(at: partialURL(id), to: completeURL(id))
        return id
    }

    /// The text is safe: the audio is no longer needed.
    func discard(_ id: UUID) {
        for url in [completeURL(id), partialURL(id)] { try? FileManager.default.removeItem(at: url) }
    }

    /// Recordings left by an earlier run, oldest first, at most `keepLimit`.
    func leftovers() -> [Entry] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles)) ?? []
        var entries: [Entry] = urls.compactMap { url in
            let interrupted = url.pathExtension == Self.partialExtension
            let name = interrupted ? url.deletingPathExtension() : url
            guard name.pathExtension == Self.audioExtension,
                  let id = UUID(uuidString: name.deletingPathExtension().lastPathComponent),
                  id != activeID else { return nil }
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return Entry(id: id, url: url, date: date, wasInterrupted: interrupted)
        }
        entries.sort { $0.date < $1.date }
        while entries.count > Self.keepLimit { discard(entries.removeFirst().id) }
        return entries
    }

    func samples(of entry: Entry) -> [Float] {
        guard let data = try? Data(contentsOf: entry.url) else { return [] }
        let count = data.count / MemoryLayout<Float>.size
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self).prefix(count)) }
    }

    private func partialURL(_ id: UUID) -> URL {
        completeURL(id).appendingPathExtension(Self.partialExtension)
    }

    private func completeURL(_ id: UUID) -> URL {
        directory.appendingPathComponent(id.uuidString).appendingPathExtension(Self.audioExtension)
    }
}
