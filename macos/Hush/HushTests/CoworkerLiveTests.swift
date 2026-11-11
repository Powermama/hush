import AVFoundation
import AppKit
import FluidAudio
import Foundation
import Testing
@testable import Hush

/// Opt-in integration evidence using installed Qwen/Parakeet and Hush's permanent
/// Kokoro cache. Synthetic fixtures do not establish real-user speech accuracy.
@Suite("Coworker local stack", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["HUSH_COWORKER_LIVE"] == "1"))
@MainActor
struct CoworkerLiveTests {
    @Test("Installed Qwen plans a browser sequence from successive synthetic observations")
    func browserSequence() async throws {
        let goal = "Open a new tab in Safari, go to https://www.youtube.com/, search for David Guetta and open the first music video."
        let cases: [(CoworkerReply.Action, String?, [CoworkerObservation.Element], String)] = [
            (.newTab, "https://example.com/", [], "Example page"),
            (.navigate, nil, [], "New empty tab. Address bar focused."),
            (.fill, "https://www.youtube.com/", [.init(id: 21, role: "AXTextField", label: "Search", url: nil, value: "")], "YouTube search"),
            (.submitSearch, "https://www.youtube.com/", [.init(id: 33, role: "AXTextField", label: "Search", url: nil, value: "David Guetta")], "Search field contains David Guetta"),
            (.press, "https://www.youtube.com/results?search_query=David+Guetta", [
                .init(id: 47, role: "AXLink", label: "David Guetta - Titanium (Official Music Video)", url: "https://www.youtube.com/watch?v=fixture1")
            ], "First music video result: David Guetta - Titanium (Official Music Video)")
        ]
        var checkpoints: [CoworkerProgress.Checkpoint] = []
        for (expected, pageURL, elements, text) in cases {
            let observation = CoworkerObservation(application: "Safari", window: "Browser", selectedText: "", visibleText: text,
                elements: elements, editable: false, limitation: "Synthetic AX fixture, no live page", pageURL: pageURL)
            let request = CoworkerRequest(text: goal, observation: observation, history: [], now: Date(), timeZone: .current, checkpoints: checkpoints)
            let start = ContinuousClock.now
            let reply = try await LLMRuntime.shared.generateCoworkerReply(request, provider: .qwen35_4b)
            print("[coworker-sequence] step=\(checkpoints.count + 1) elapsed=\(start.duration(to: .now)) action=\(reply.action) more=\(reply.more)")
            // Both a grounded native press and navigating the exact observed link are valid.
            #expect(reply.action == expected || (expected == .press && reply.action == .navigate))
            #expect(reply.more == (expected != .press))
            if [.fill, .submitSearch, .press].contains(reply.action) { #expect(reply.target == elements.first?.id) }
            if reply.action == .fill { #expect(reply.content == "David Guetta") }
            checkpoints.append(.init(action: expected, result: "Verified: \(text). Completed \(expected.rawValue)."))
        }
        let observation = CoworkerObservation(application: "Safari", window: "YouTube", selectedText: "", visibleText: "Search page",
            elements: [], editable: false, limitation: "No ranking evidence")
        let ambiguous = try await LLMRuntime.shared.generateCoworkerReply(.init(text: "Find David Guetta's most viral video.",
            observation: observation, history: [], now: Date(), timeZone: .current), provider: .qwen35_4b)
        #expect(ambiguous.action == .answer)
        #expect(ambiguous.message.contains("?"))
        #expect(!ambiguous.more)
    }

    @Test("Mail follow-ups return one body and a separate subject with the installed small model")
    func mailDocumentFollowup() async throws {
        var observation = CoworkerObservation(application: "Mail", window: "New Message", selectedText: "",
            visibleText: "New Message", elements: [], editable: true, limitation: nil)
        observation.mailDraft = .init(subject: "", body: "")
        let firstRequest = "Write an email to my mother inviting her to dinner tomorrow at five pm in Bremen."
        let first = try await LLMRuntime.shared.generateCoworkerReply(.init(text: firstRequest, observation: observation,
            history: [], now: Date(), timeZone: .current), provider: .qwen35_4b)
        #expect([.write, .revise].contains(first.action))
        #expect(!first.subject.isEmpty)
        #expect(!first.content.contains("Subject:"))
        #expect(!first.content.contains("To:"))
        #expect(!first.content.contains("["))
        #expect(first.content.contains("Bremen"))
        observation.mailDraft = .init(subject: first.subject, body: first.content)
        let history = [CoworkerTurn(request: firstRequest, response: first.message, artifact: first.content,
                                   outcome: "Your draft is updated. I've checked the text.")]
        let second = try await LLMRuntime.shared.generateCoworkerReply(.init(
            text: "My name is Alex. Sign it with my name and put the subject in the subject field, not in the body.",
            observation: observation, history: history, now: Date(), timeZone: .current), provider: .qwen35_4b)
        #expect([.write, .revise].contains(second.action))
        #expect(second.content.contains("Alex"))
        #expect(second.content.contains("Bremen"))
        #expect(!second.subject.isEmpty)
        #expect(!second.content.contains("Subject:"))
        #expect(!second.content.contains("To:"))
        #expect(!second.content.contains("["))
        print("[coworker-live] Mail document contract passed; subject/body separated on both turns.")
    }

    @Test("The installed Qwen checkpoint sees image pixels through native MLXVLM")
    func nativeVision() async throws {
        for greenOnRight in [true, false] {
            let space = CGColorSpaceCreateDeviceRGB()
            let bitmap = try #require(CGContext(data: nil, width: 448, height: 224, bitsPerComponent: 8, bytesPerRow: 448 * 4,
                                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            bitmap.setFillColor(NSColor.white.cgColor); bitmap.fill(CGRect(x: 0, y: 0, width: 448, height: 224))
            bitmap.setFillColor((greenOnRight ? NSColor.red : NSColor.green).cgColor)
            bitmap.fill(CGRect(x: 20, y: 32, width: 160, height: 160))
            bitmap.setFillColor((greenOnRight ? NSColor.green : NSColor.red).cgColor)
            bitmap.fill(CGRect(x: 268, y: 32, width: 160, height: 160))
            let image = try #require(bitmap.makeImage())
            let png = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            let observation = CoworkerObservation(application: "Synthetic image", window: "Image pixels only", selectedText: "",
                visibleText: "", elements: [], editable: false, limitation: nil)
            let request = CoworkerRequest(text: "Look at the attached image. Is the green rectangle on the left or the right? Answer in one word.",
                observation: observation, history: [], now: Date(), timeZone: .current, screenshot: png)
            let reply = try await LLMRuntime.shared.generateCoworkerReply(request, provider: .qwen35_4b)
            print("[coworker-live] native vision greenOnRight=\(greenOnRight): \(reply)")
            #expect(reply.action == .answer)
            #expect(reply.message.lowercased().contains(greenOnRight ? "right" : "left"))
        }
    }

    @Test("Installed models support a local work conversation and synthesize its reply")
    func localConversation() async throws {
        let observation = CoworkerObservation(application: "Mail", window: "Conversation with Tom",
            selectedText: "", visibleText: "Tom: Could we meet tomorrow at 10 in the morning for 30 minutes?",
            elements: [], editable: true, limitation: nil)
        let now = try #require(ISO8601DateFormatter().date(from: "2026-11-01T09:00:00-03:00"))
        let zone = try #require(TimeZone(identifier: "America/Asuncion"))
        let started = Date()
        let draft = try await LLMRuntime.shared.generateCoworkerReply(.init(text: "Write a short reply to Tom confirming the meeting. Begin with Hi Tom,",
            observation: observation, history: [], now: now, timeZone: zone), provider: .qwen35_4b)
        print("[coworker-live] draft \(Date().timeIntervalSince(started))s \(draft)")
        #expect(draft.action == .write)
        #expect(draft.content.contains("Tom"))
        #expect(draft.content.contains("10"))
        let history = [CoworkerTurn(request: "Write a short reply to Tom confirming the meeting. Begin with Hi Tom,",
            response: draft.message, artifact: draft.content, outcome: "Your draft is updated. I've checked the text.")]
        let revised = try await LLMRuntime.shared.generateCoworkerReply(.init(text: "Make it warmer and shorter. Keep the greeting.",
            observation: observation, history: history, now: now, timeZone: zone), provider: .qwen35_4b)
        print("[coworker-live] follow-up \(revised)")
        #expect(revised.action == .revise)
        #expect(revised.content.contains("Tom"))
        #expect(revised.content.contains("10"))
        #expect(revised.content != draft.content)
        #expect(revised.content.count < draft.content.count)

        let speech = FluidAudioTranscriber()
        try await speech.prepare(modelID: ParakeetModel.ultra.id) { _ in }
        let clip = FluidAudioTranscriberIntegrationTests.clips[2]
        let transcript = try #require(try await speech.transcribe(samples: FluidAudioTranscriberIntegrationTests.samples(for: clip),
                                                                 language: "en", fallbackCount: 0))
        await speech.unload()
        print("[coworker-live] Parakeet \(transcript)")
        #expect(transcript.lowercased().contains("clara"))
        let meetingContext = CoworkerObservation(application: "Mail", window: "Clara", selectedText: "",
            visibleText: "Design review with Clara. Duration: 30 minutes. Local timezone America/Asuncion.",
            elements: [], editable: false, limitation: nil)
        let meeting = try await LLMRuntime.shared.generateCoworkerReply(.init(text: transcript, observation: meetingContext,
            history: [], now: now, timeZone: zone), provider: .qwen35_4b)
        print("[coworker-live] meeting \(meeting)")
        #expect(meeting.action == .meeting)
        #expect(meeting.minutes == 30)
        #expect(meeting.start.hasPrefix("2026-11-05T15:30"))
        let kokoro = KokoroAneManager(defaultVoice: "af_heart", directory: AIModelStorage.fluidAudioRoot, version: .v3)
        let voiceStart = Date()
        try await kokoro.initialize(preloadVoices: ["af_heart"])
        print("[coworker-live] Kokoro prepare \(Date().timeIntervalSince(voiceStart))s")
        let synthesisStart = Date()
        let wav = try await kokoro.synthesize(text: "Your reply is ready. You can ask me to make it shorter.", voice: "af_heart")
        #expect(wav.count > 4_000)
        let player = try AVAudioPlayer(data: wav)
        #expect(player.duration > 1)
        #expect(player.prepareToPlay())
        print("[coworker-live] Kokoro synthesis \(Date().timeIntervalSince(synthesisStart))s duration \(player.duration)s bytes \(wav.count)")
        await kokoro.cleanup()
    }
}
