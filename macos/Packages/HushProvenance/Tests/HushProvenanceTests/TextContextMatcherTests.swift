import Foundation
import Testing
@testable import HushProvenance

@Suite("Contextual Hush editor")
struct TextContextMatcherTests {
    @Test("detects an exact recent Hush message and its visible proof")
    func detectsMessageAndProof() throws {
        let message = "Perfect, let us lock in Thursday at ten."
        let signature = "\n\n-typed with hush: https://behu.sh/A7k2Qx#k=private"
        let field = "Earlier text\n\(message)\(signature)\nLater text"

        let match = try #require(TextContextMatcher.match(
            fieldValue: field,
            bundleIdentifier: "com.apple.mail",
            candidates: [
                RecentTextCandidate(
                    text: message,
                    bundleIdentifier: "com.apple.mail",
                    copiedToClipboard: false
                ),
            ]
        ))

        #expect(match.message == message)
        #expect(match.expectedText == message + signature)
        #expect((field as NSString).substring(with: match.replacementRange) == message + signature)
    }

    @Test("detects the linked signature label without a visible URL")
    func detectsLinkedSignature() throws {
        let message = "A short verified message."
        let field = "\(message)\n\n-typed with hush"
        let match = try #require(TextContextMatcher.match(
            fieldValue: field,
            bundleIdentifier: "com.apple.notes",
            candidates: [
                RecentTextCandidate(
                    text: message,
                    bundleIdentifier: "com.apple.notes",
                    copiedToClipboard: false
                ),
            ]
        ))
        #expect(match.expectedText == field)
    }

    @Test("ignores text from another app or clipboard-only output")
    func rejectsUnrelatedContext() {
        let candidates = [
            RecentTextCandidate(
                text: "Do not import this",
                bundleIdentifier: "com.apple.mail",
                copiedToClipboard: false
            ),
            RecentTextCandidate(
                text: "Clipboard draft",
                bundleIdentifier: "com.apple.notes",
                copiedToClipboard: true
            ),
        ]
        #expect(TextContextMatcher.match(
            fieldValue: "Do not import this Clipboard draft",
            bundleIdentifier: "com.apple.notes",
            candidates: candidates
        ) == nil)
    }

    @Test("replacement validation fails closed after source text changes")
    func rejectsStaleReplacement() throws {
        let message = "Original Hush message text"
        let match = try #require(TextContextMatcher.match(
            fieldValue: message,
            bundleIdentifier: "com.apple.TextEdit",
            candidates: [
                RecentTextCandidate(
                    text: message,
                    bundleIdentifier: "com.apple.TextEdit",
                    copiedToClipboard: false
                ),
            ]
        ))
        #expect(TextContextMatcher.isValid(
            range: match.replacementRange,
            expectedText: match.expectedText,
            in: message
        ))
        #expect(!TextContextMatcher.isValid(
            range: match.replacementRange,
            expectedText: match.expectedText,
            in: "Someone changed it"
        ))
    }

    @Test("does not infer short text that may occur incidentally")
    func rejectsShortAutomaticMatch() {
        #expect(TextContextMatcher.match(
            fieldValue: "The release is amazing and ready to ship.",
            bundleIdentifier: "com.apple.TextEdit",
            candidates: [
                RecentTextCandidate(
                    text: "amazing",
                    bundleIdentifier: "com.apple.TextEdit",
                    copiedToClipboard: false
                ),
            ],
            selectionLocation: 18
        ) == nil)
    }

    @Test("expands a partial selection to the complete Hush message and proof")
    func expandsPartialSelectionToCompleteMessage() throws {
        let message = "Please review the complete launch checklist before Thursday morning."
        let firstProof = "\n\n-typed with hush: https://behu.sh/A7k2Qx#k=first"
        let staleProof = "\n\n-typed with hush: https://behu.sh/B8m3Ry#k=stale"
        let field = "Intro\n\n\(message)\(firstProof)\(staleProof)\n\nFooter"
        let messageLocation = (field as NSString).range(of: message).location
        let selectedRange = NSRange(location: messageLocation + 7, length: 12)
        let history = [ProofManifest.ProvenanceEvent(
            occurredAt: "2026-08-02T20:00:00.000Z",
            kind: .messageStarted
        )]

        let match = try #require(TextContextMatcher.match(
            fieldValue: field,
            bundleIdentifier: "com.microsoft.Word",
            candidates: [
                RecentTextCandidate(
                    text: message,
                    bundleIdentifier: "com.microsoft.Word",
                    copiedToClipboard: false,
                    proofId: "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34",
                    proofCommitment: String(repeating: "A", count: 43),
                    provenanceEvents: history,
                    sourceText: "Original unrefined wording"
                ),
            ],
            selectionLocation: selectedRange.location,
            selectedRange: selectedRange
        ))

        #expect(match.message == message)
        #expect(match.expectedText == message + firstProof + staleProof)
        #expect(match.proofId == "018f47a6-84d2-7a10-9c2d-2f2c29ba7b34")
        #expect(match.proofCommitment == String(repeating: "A", count: 43))
        #expect(match.provenanceEvents == history)
        #expect(match.sourceText == "Original unrefined wording")
    }

    @Test("does not use another nearby Hush message for an unrelated selection")
    func rejectsUnrelatedSelectionNearKnownMessage() {
        let known = "This complete paragraph was previously created and retained by Hush."
        let pasted = "This paragraph came from an unrelated pasted source and is selected."
        let field = "\(known)\n\n\(pasted)"
        let selectedRange = (field as NSString).range(of: pasted)

        #expect(TextContextMatcher.match(
            fieldValue: field,
            bundleIdentifier: "com.microsoft.Word",
            candidates: [
                RecentTextCandidate(
                    text: known,
                    bundleIdentifier: "com.microsoft.Word",
                    copiedToClipboard: false
                ),
            ],
            selectionLocation: selectedRange.location,
            selectedRange: selectedRange
        ) == nil)
    }

    @Test("chooses the historical message nearest the caret")
    func choosesNearestMessage() {
        let older = RecentTextCandidate(
            text: "The older Hush message",
            bundleIdentifier: "com.apple.TextEdit",
            copiedToClipboard: false
        )
        let newer = RecentTextCandidate(
            text: "The newer Hush message",
            bundleIdentifier: "com.apple.TextEdit",
            copiedToClipboard: false
        )
        let document = "The older Hush message\n\nUnrelated notes\n\nThe newer Hush message"

        let match = TextContextMatcher.match(
            fieldValue: document,
            bundleIdentifier: "com.apple.TextEdit",
            candidates: [newer, older],
            selectionLocation: 5
        )

        #expect(match?.message == older.text)
        #expect(match?.replacementRange.location == 0)
    }

    @Test("reopens a lightly edited Hush message without a time limit")
    func detectsStrictApproximateMatch() throws {
        let original = "Please review the complete onboarding journey before Thursday and send the final notes to the product team."
        let current = "Please review the complete onboarding journey before Thursday and send the final notes to our product team."
        let field = "Unrelated introduction\n\n\(current)\n\n-typed with hush: https://behu.sh/A7k2Qx#k=private"

        let match = try #require(TextContextMatcher.match(
            fieldValue: field,
            bundleIdentifier: "com.apple.TextEdit",
            candidates: [
                RecentTextCandidate(
                    text: original,
                    bundleIdentifier: "com.apple.TextEdit",
                    copiedToClipboard: false
                ),
            ],
            selectionLocation: 45
        ))

        #expect(match.message == current)
        #expect(match.expectedText.hasSuffix("#k=private"))
    }

    @Test("does not guess below the strict similarity threshold")
    func rejectsLooseApproximateMatch() {
        let original = "Please review the complete onboarding journey before Thursday and send the final notes to the product team."
        let unrelated = "A substantially different paragraph is under the cursor and it must never be replaced by an approximate match."

        #expect(TextContextMatcher.match(
            fieldValue: unrelated,
            bundleIdentifier: "com.apple.TextEdit",
            candidates: [
                RecentTextCandidate(
                    text: original,
                    bundleIdentifier: "com.apple.TextEdit",
                    copiedToClipboard: false
                ),
            ],
            selectionLocation: 20
        ) == nil)
    }
}
