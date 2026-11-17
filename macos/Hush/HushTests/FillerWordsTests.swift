import Foundation
import Testing
@testable import Hush

@Suite("Filler words")
struct FillerWordsTests {

    @Test("The bundled list loads and holds no word of any language")
    func bundledList() {
        let sounds = FillerWords.bundled.sounds
        #expect(sounds.contains("uh"))
        #expect(sounds.contains("ähm"))
        for word in ["um", "er", "eh", "ah", "like", "also", "este"] {
            #expect(!sounds.contains(word), "'\(word)' is a real word in some language; it belongs to the language model")
        }
    }

    @Test("Sounds go in every language; words that only look like them stay")
    func languageIndependent() {
        #expect(FillerWords.removing(from: "Ähm, ich komme später.") == "Ich komme später.")
        #expect(FillerWords.removing(from: "Euh, je pense que oui.") == "Je pense que oui.")
        #expect(FillerWords.removing(from: "Wir treffen uns um 10 Uhr.") == "Wir treffen uns um 10 Uhr.")
        #expect(FillerWords.removing(from: "Comprei um carro.") == "Comprei um carro.")
        #expect(FillerWords.removing(from: "Er hat angerufen.") == "Er hat angerufen.")
    }

    @Test("Commas that only set the sound off go with it, and a sentence keeps its capital")
    func punctuation() {
        #expect(FillerWords.removing(from: "Uh, so we should, uh, move it.") == "So we should move it.")
        #expect(FillerWords.removing(from: "Das war's, äh.") == "Das war's.")
        #expect(FillerWords.removing(from: "Paris, London and Rome.") == "Paris, London and Rome.")
        #expect(FillerWords.removing(from: "Done.\nUh, next one.") == "Done.\nNext one.")
    }

    @Test("Drawn-out sounds go; words that only look like them stay")
    func stretched() {
        #expect(FillerWords.removing(from: "Hmmmm, okay.") == "Okay.")
        #expect(FillerWords.removing(from: "To err is human.") == "To err is human.")
        #expect(FillerWords.removing(from: "It is 5 mm wide.") == "It is 5 mm wide.")
        #expect(FillerWords.removing(from: "Uh-oh.") == "Uh-oh.")
        #expect(FillerWords.removing(from: "UHM won.") == "UHM won.")
    }

    @Test("The basic clean-up removes hesitations for every dictation")
    func basicPostProcessor() async throws {
        let text = try await BasicPostProcessor().process("  Ähm, ich komme  später. ", language: "de")
        #expect(text == "Ich komme später.")
    }
}
