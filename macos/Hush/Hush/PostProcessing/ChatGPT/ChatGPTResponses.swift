import Foundation

/// What can go wrong with the ChatGPT connection, mapped from OpenAI's documented error
/// codes (siwc/token-sharing-open-source/errors-and-recovery) to what hush does next.
enum ChatGPTError: Error, Equatable {
    /// The plan's limit for this app is reached: pause plan requests, offer Manage usage.
    case usageLimitReached
    /// The account cannot use its plan here: explain, never loop through sign-in.
    case notEligible(String?)
    /// OpenAI cannot serve plan requests right now: retry later with backoff.
    case temporarilyUnavailable
    /// The request asked for something plan usage does not support (`param` says what).
    case unsupported(String?)
    /// Credentials are no longer accepted: sign in again.
    case signInRequired
    /// Sign-in finished without the plan-usage permission.
    case planUsageNotGranted
    case cancelled
    case incomplete(String?)
    case badResponse(String)
    case keychain(OSStatus)
    case network(String)

    static func from(status: Int, code: String?, param: String?) -> ChatGPTError {
        switch code {
        case "subscription_sharing_usage_limit_exceeded": return .usageLimitReached
        case "subscription_sharing_user_not_eligible": return .notEligible(param)
        case "subscription_sharing_usage_unavailable", "subscription_sharing_user_unavailable": return .temporarilyUnavailable
        case "subscription_sharing_unsupported_capability": return .unsupported(param)
        case "subscription_sharing_invalid_user": return .signInRequired
        case "subscription_sharing_route_not_supported", "chatpass_v2_scope_not_authorized", "chatpass_v2_invalid_authorization_context":
            return .badResponse(code ?? "")
        default: break
        }
        switch status {
        case 401: return .signInRequired
        case 403: return .notEligible(nil)
        case 429: return .usageLimitReached
        case 503: return .temporarilyUnavailable
        default: return .badResponse("HTTP \(status)\(code.map { " \($0)" } ?? "")")
        }
    }
}

/// The Responses API on the user's ChatGPT plan: `store: false`, `stream: true`, hush's
/// rules as `instructions`, no temperature or output limit (both rejected in this flow).
/// Success only on `response.completed`.
enum ChatGPTResponses {
    static let endpoint = URL(string: "https://api.openai.com/v1/responses")!
    static let modelsEndpoint = URL(string: "https://api.openai.com/v1/models")!

    struct Message: Encodable, Equatable {
        let role: String
        let content: String
    }

    struct Request: Encodable {
        let model: String
        let instructions: String
        let input: [Message]
        let store = false
        let stream = true
    }

    static func request(model: String, instructions: String, input: [Message], accessToken: String) throws -> URLRequest {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(Request(model: model, instructions: instructions, input: input))
        return request
    }

    /// Accumulates a server-sent event stream into the final text.
    struct StreamReader {
        private(set) var text = ""
        private(set) var completed = false
        private var eventName: String?
        private var dataLines: [String] = []

        /// Feeds one line of the stream; throws when the stream reports a failure.
        mutating func consume(line: String) throws {
            if line.isEmpty { try dispatch(); return }
            if line.hasPrefix(":") { return }
            if line.hasPrefix("event:") { eventName = line.dropFirst(6).trimmingCharacters(in: .whitespaces); return }
            if line.hasPrefix("data:") { dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)) }
        }

        mutating func finish() throws {
            try dispatch()
            guard completed else { throw ChatGPTError.incomplete("The stream ended before response.completed") }
        }

        private mutating func dispatch() throws {
            defer { eventName = nil; dataLines = [] }
            guard !dataLines.isEmpty else { return }
            let payload = dataLines.joined(separator: "\n")
            if payload == "[DONE]" { return }
            guard let object = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return }
            let type = object["type"] as? String ?? eventName ?? ""
            switch type {
            case "response.output_text.delta":
                text += object["delta"] as? String ?? ""
            case "response.output_text.done":
                if let full = object["text"] as? String, !full.isEmpty { text = full }
            case "response.completed":
                completed = true
            case "response.incomplete":
                let response = object["response"] as? [String: Any]
                let details = response?["incomplete_details"] as? [String: Any]
                throw ChatGPTError.incomplete(details?["reason"] as? String)
            case "response.failed", "error":
                let response = object["response"] as? [String: Any]
                let error = (response?["error"] ?? object["error"] ?? object) as? [String: Any]
                throw ChatGPTError.from(status: 0, code: error?["code"] as? String, param: error?["param"] as? String)
            default:
                break
            }
        }
    }

    /// Decodes an error body returned before a stream opens, in either documented form.
    static func admissionError(status: Int, body: Data) -> ChatGPTError {
        let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
        let error = object?["error"] as? [String: Any]
        return ChatGPTError.from(status: status, code: error?["code"] as? String, param: error?["param"] as? String)
    }

    struct Model: Equatable, Sendable {
        let slug: String
        let displayName: String
    }

    /// The models the signed-in account may use: the `models` array, entries listed visible.
    static func models(from body: Data) -> [Model] {
        guard let object = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] else { return [] }
        let entries = (object["models"] ?? object["data"]) as? [[String: Any]] ?? []
        return entries.compactMap { entry in
            if let visibility = entry["visibility"] as? String, visibility != "list" { return nil }
            guard let slug = (entry["slug"] ?? entry["id"]) as? String else { return nil }
            return Model(slug: slug, displayName: entry["display_name"] as? String ?? slug)
        }
    }
}
