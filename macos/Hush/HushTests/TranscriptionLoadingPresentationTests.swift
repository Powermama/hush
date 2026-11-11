import Testing
@testable import Hush

@Suite("Transcription loading presentation")
struct TranscriptionLoadingPresentationTests {
    @Test("Remote models communicate download progress")
    func remoteProgress() {
        let value = TranscriptionModelLoadingPresentation.make(
            modelName: "Large v3",
            progress: 0.426,
            isLocal: false
        )
        #expect(value.label == "Downloading 43%")
        #expect(value.toolTip == "Downloading Large v3 to this Mac")
    }

    @Test("Cached models communicate preparation progress")
    func localProgress() {
        let value = TranscriptionModelLoadingPresentation.make(
            modelName: "Base",
            progress: 0.95,
            isLocal: true
        )
        #expect(value.label == "Preparing 95%")
        #expect(value.toolTip == "Loading Base from this Mac")
    }
}
