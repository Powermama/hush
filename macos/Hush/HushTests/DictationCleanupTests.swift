import Foundation
import Testing
@testable import Hush

@Suite("Deterministic cleanup around the model")
struct DictationCleanupTests {
    @Test("Subject lines, Markdown and placeholders go; bullets become plain lines")
    func finishesAnEmail() {
        let model = """
        **Betreff: Einladung zum Brunch**

        Liebe Corinda,

        *   Beta launched
        • 40 pilots
        ## Risks

        Viele Grüße,

        [Your Name]
        """
        #expect(DictationCleanup.finishing(model, dictation: "schreib Corinda eine Einladung") == """
        Liebe Corinda,

        - Beta launched
        - 40 pilots
        Risks

        Viele Grüße,
        """)
    }

    @Test("A subject line stays when the speaker asked for one")
    func keepsAskedForSubject() {
        let model = "Subject: Board update\n\nHi Steffi,"
        #expect(DictationCleanup.finishing(model, dictation: "an email to Steffi with the subject board update") == model)
    }

    @Test("An echoed prompt or example is cut to its answer")
    func cutsEchoes() {
        let echo = "<persona>Write.</persona>\n<dictation>list milk and bread</dictation>\nAnswer: \n- Milk\n- Bread"
        #expect(DictationCleanup.finishing(echo, dictation: "list milk and bread") == "- Milk\n- Bread")
    }

    @Test("Numbered lists and ordinary text are left alone")
    func leavesTextAlone() {
        let text = "1. Export the data\n2. Check the totals\n\nThe 3 * 4 grid stays."
        #expect(DictationCleanup.finishing(text, dictation: "steps") == text)
    }
}

@Suite("Guards around the model")
struct DictationGuardTests {
    @Test("A preamble line introducing the answer is cut")
    func cutsPreamble() {
        #expect(DictationCleanup.finishing("Hier ist der Entwurf für die Einladung:\n\nLiebe Corinda,", dictation: "Einladung") == "Liebe Corinda,")
        #expect(DictationCleanup.finishing("Here is the email:\nHi Tom,", dictation: "email Tom") == "Hi Tom,")
        #expect(DictationCleanup.finishing("Here is what I think we should do.", dictation: "x") == "Here is what I think we should do.")
    }

    @Test("Empty, runaway or collapsed answers fall back to the dictation")
    func unusable() {
        let said = "also ich hab gestern mit dem Team gesprochen und wir verschieben das Release auf Freitag"
        #expect(DictationCleanup.isUnusable("", dictation: said, mode: .correct))
        #expect(DictationCleanup.isUnusable(String(repeating: "Release ", count: 80), dictation: said, mode: .correct))
        #expect(DictationCleanup.isUnusable("Freitag.", dictation: said, mode: .correct))
        #expect(!DictationCleanup.isUnusable("Gestern habe ich mit dem Team gesprochen; wir verschieben das Release auf Freitag.", dictation: said, mode: .correct))
        // A written email may be several times longer than the request that described it.
        let email = String(repeating: "word ", count: 120)
        #expect(!DictationCleanup.isUnusable(email, dictation: "an email to Steffi about the beta and the hiring risk", mode: .compose))
        #expect(DictationCleanup.isUnusable(String(repeating: "word ", count: 600), dictation: "an email to Steffi", mode: .compose))
    }

    @Test("Every dictation loses its hesitation sounds, also without a persona")
    func basicProcessor() async throws {
        #expect(try await BasicPostProcessor().process(" uh so we ship  it ", language: "en") == "so we ship it")
    }
}
