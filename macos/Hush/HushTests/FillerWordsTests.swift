import Foundation
import Testing
@testable import Hush

@Suite("Filler words")
struct FillerWordsTests {

    @Test("The bundled lists load, with sources and the gated languages")
    func bundledLists() {
        let lists = FillerWords.bundled
        #expect(lists.universal.contains("uh"))
        #expect(!lists.universal.contains("um"), "'um' is German and Portuguese; it must stay language-gated")
        #expect(lists.languages["de"]?.contains("ähm") == true)
        #expect(Set(lists.languages.keys) == ["en", "de", "fr"])
    }

    @Test("A sound that is a word somewhere goes only in the language where it is a sound")
    func gatedTier() {
        #expect(FillerWords.removing(from: "Um, the plan works.", language: "en") == "The plan works.")
        #expect(FillerWords.removing(from: "Wir treffen uns um 10 Uhr.", language: "de") == "Wir treffen uns um 10 Uhr.")
        #expect(FillerWords.removing(from: "Comprei um carro.", language: "pt") == "Comprei um carro.")
    }

    @Test("Region codes use their language's list")
    func regionCodes() {
        #expect(FillerWords.languageCode(for: "en-US", text: "") == "en")
        #expect(FillerWords.languageCode(for: "pt_BR", text: "") == "pt")
    }

    @Test("Commas that only set the sound off go with it, and a sentence keeps its capital")
    func punctuation() {
        #expect(FillerWords.removing(from: "Um, so we should, uh, move it.", language: "en") == "So we should move it.")
        #expect(FillerWords.removing(from: "That's it, um.", language: "en") == "That's it.")
        #expect(FillerWords.removing(from: "Paris, London and Rome.", language: "en") == "Paris, London and Rome.")
        #expect(FillerWords.removing(from: "Done.\nUh, next one.", language: "en") == "Done.\nNext one.")
    }

    @Test("Drawn-out sounds go; words that only look like them stay")
    func stretched() {
        #expect(FillerWords.removing(from: "Hmmmm, okay.", language: "de") == "Okay.")
        #expect(FillerWords.removing(from: "To err is human.", language: "en") == "To err is human.")
        #expect(FillerWords.removing(from: "It is 5 mm wide.", language: "en") == "It is 5 mm wide.")
        #expect(FillerWords.removing(from: "Uh-oh.", language: "en") == "Uh-oh.")
        #expect(FillerWords.removing(from: "UM won.", language: "en") == "UM won.")
    }

    @Test("A language without its own list removes only universal sounds")
    func languageWithoutList() {
        let lists = FillerWords.Lists(universal: ["uh"], languages: ["en": ["um"]])
        #expect(FillerWords.removing(from: "Uh, um carro novo.", language: "pt", lists: lists) == "Um carro novo.")
    }

    @Test("The basic clean-up removes hesitations for every dictation")
    func basicPostProcessor() async throws {
        let text = try await BasicPostProcessor().process("  Ähm, ich komme  später. ", language: "de")
        #expect(text == "Ich komme später.")
    }
}
