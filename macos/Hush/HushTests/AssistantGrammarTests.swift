import Foundation
import MLX
import MLXLMCommon
import MLXStructured
import Testing
@testable import Hush

@Suite("Assistant native grammar", .serialized)
@MainActor
struct AssistantGrammarTests {
    @Test("Profile grammar preparation with the installed tokenizer, without loading model weights",
          .enabled(if: ProcessInfo.processInfo.environment["HUSH_GRAMMAR_PROFILE"] == "1"))
    func installedTokenizerPreparation() async throws {
        let directory = try #require(LLMRuntime.cachedQwenSnapshotURL(for: .qwen35_4b))
        let configuration = ModelConfiguration(directory: directory)
        let report = URL(fileURLWithPath: "/private/tmp/hush-grammar-preparation.jsonl")
        try Data().write(to: report)
        let file = try FileHandle(forWritingTo: report)
        defer { try? file.close() }
        func record(_ fields: [String: String]) throws {
            try file.write(contentsOf: JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]))
            try file.write(contentsOf: Data([10]))
        }
        // Freeze the old bounded-string contract so later fixes retain a useful baseline.
        let bounded = CoworkerSequenceBaseline.schema
        let compact = bounded.replacingOccurrences(of: ",\"maxLength\":300", with: "")
        #expect(compact != bounded)
        // Reverse the order in a fresh process to separate tokenizer setup from schema cost.
        for (name, schema) in [("unbounded-cold", compact), ("bounded-first", bounded),
                               ("bounded-cached", bounded), ("unbounded-cached", compact)] {
            try record(["case": name, "stage": "started"])
            let start = ContinuousClock.now
            _ = try await GrammarMaskedLogitProcessor.from(configuration: configuration, grammar: .schema(schema))
            try record(["case": name, "stage": "completed", "duration": String(describing: start.duration(to: .now))])
        }
    }

    @Test("XGrammar preserves text whitespace and permits EOS only after a complete proposal", arguments: [false, true])
    func nativeTokenMask(fixedFormatting: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("hush-grammar-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let vocab = ["<eos>"] + (32...126).compactMap(UnicodeScalar.init).map(String.init) + ["ü", "ß", "👋"]
        let indices = Dictionary(uniqueKeysWithValues: vocab.enumerated().map { ($0.element, $0.offset) })
        func write(_ object: [String: Any], _ name: String) throws {
            try JSONSerialization.data(withJSONObject: object).write(to: directory.appendingPathComponent(name))
        }
        try write(["vocab_size": vocab.count, "eos_token_id": 0], "config.json")
        try write(["eos_token": "<eos>"], "tokenizer_config.json")
        try write(["model": ["vocab": indices], "added_tokens": [], "decoder": ["type": "Sequence", "decoders": []]], "tokenizer.json")
        let configuration = ModelConfiguration(directory: directory, extraEOSTokens: ["<eos>"])
        let processor = try await GrammarMaskedLogitProcessor.from(configuration: configuration,
            grammar: .schema(CoworkerReply.schema, format: .init(whitespace: fixedFormatting ? .none : .any)))
        processor.prompt(MLXArray([0]))
        let initial = processor.process(logits: MLXArray.zeros([vocab.count])).asArray(Float.self)
        #expect(!initial[0].isFinite)
        #expect(!initial[try #require(indices["["])].isFinite)
        let output = fixedFormatting
            ? #"{"action": "write", "target": 0, "content": "Grüße 👋\nGuten Tag", "subject": "", "start": "", "minutes": 0, "message": "Ready", "more": false}"#
            : #"{"action":"write","target":0,"content":"Grüße 👋\nGuten Tag","subject":"","start":"","minutes":0,"message":"Ready","more":false}"#
        var prefix = ""
        for character in output {
            let token = try #require(indices[String(character)])
            let mask = processor.process(logits: MLXArray.zeros([vocab.count])).asArray(Float.self)
            #expect(mask[token].isFinite, "Grammar rejected \(character)")
            if fixedFormatting && prefix.hasSuffix(": ") {
                #expect(!mask[try #require(indices[" "])].isFinite, "Must not allow repeated formatting spaces")
            }
            processor.didSample(token: MLXArray(token))
            prefix.append(character)
        }
        let finished = processor.process(logits: MLXArray.zeros([vocab.count])).asArray(Float.self)
        #expect(finished[0].isFinite)
        #expect(!finished[try #require(indices["{"])].isFinite)
        processor.didSample(token: MLXArray(0))
    }
}
