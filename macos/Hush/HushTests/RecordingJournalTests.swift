import Foundation
import Testing
@testable import Hush

/// R1: a dictation's audio survives a crash until its text is inserted.
@Suite("Recording journal")
@MainActor
struct RecordingJournalTests {
    private func journal() -> RecordingJournal {
        RecordingJournal(directory: FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)"))
    }

    @Test("A finished recording reads back exactly as written")
    func roundTrip() throws {
        let journal = journal()
        journal.begin()
        journal.append([0.1, 0.2])
        journal.append([0.3])
        let id = try #require(journal.finish())
        let entry = try #require(journal.leftovers().first)
        #expect(entry.id == id && !entry.wasInterrupted)
        #expect(journal.samples(of: entry) == [0.1, 0.2, 0.3])
    }

    @Test("A recording cut off by a crash is still readable")
    func interrupted() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("journal-\(UUID().uuidString)")
        let crashed = RecordingJournal(directory: directory)
        crashed.begin()
        crashed.append([0.5, 0.6, 0.7])
        // No finish: the next launch finds a partial file.
        let nextLaunch = RecordingJournal(directory: directory)
        let entry = try #require(nextLaunch.leftovers().first)
        #expect(entry.wasInterrupted)
        #expect(nextLaunch.samples(of: entry) == [0.5, 0.6, 0.7])
    }

    @Test("The recording in progress is never offered for recovery")
    func activeExcluded() {
        let journal = journal()
        journal.begin()
        journal.append([0.1])
        #expect(journal.leftovers().isEmpty)
    }

    @Test("Inserted text removes its audio")
    func discard() throws {
        let journal = journal()
        journal.begin()
        journal.append([0.1])
        let id = try #require(journal.finish())
        journal.discard(id)
        #expect(journal.leftovers().isEmpty)
    }

    @Test("Only the newest recordings are kept")
    func keepLimit() {
        let journal = journal()
        for _ in 0 ..< RecordingJournal.keepLimit + 3 {
            journal.begin()
            journal.append([0.1])
            journal.finish()
        }
        #expect(journal.leftovers().count == RecordingJournal.keepLimit)
    }

    @Test("Tests never write into the user's recordings")
    func testsUseTemporaryFolder() {
        #expect(RecordingJournal.defaultDirectory.path.hasPrefix(FileManager.default.temporaryDirectory.path))
    }
}
