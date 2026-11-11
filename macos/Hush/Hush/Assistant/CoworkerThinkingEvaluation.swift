#if DEBUG
import Foundation
import MLXStructured

/// Opt-in experiment only. Qwen's template has already emitted <think>.
/// Constrain the final object after the closing tag, not the thinking tokens.
/// Never dispatch or record the intermediate text as an action or user response.
nonisolated enum CoworkerThinkingEvaluation {
    static func grammar(schema: String) throws -> Grammar {
        let object = try JSONSerialization.jsonObject(with: Data(schema.utf8))
        let format: [String: Any] = ["type": "structural_tag", "format": [
            "type": "sequence", "elements": [
                ["type": "tag", "begin": "", "content": ["type": "any_text", "excludes": ["</think>"]], "end": "</think>"],
                ["type": "regex", "pattern": "[ \\t\\r\\n]*"],
                ["type": "json_schema", "json_schema": object]
            ]]]
        return .structural(String(decoding: try JSONSerialization.data(withJSONObject: format, options: .sortedKeys), as: UTF8.self))
    }

    @MainActor static func finalResponse(_ output: String) throws -> String {
        guard let end = output.range(of: "</think>") else { throw CoworkerError.invalidResponse }
        let final = String(output[end.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try CoworkerReply.decode(final)
        return final
    }
}
#endif
