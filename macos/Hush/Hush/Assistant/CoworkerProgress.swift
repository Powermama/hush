import Foundation

/// Observable work stages, never generated reasoning or an estimated completion time.
enum CoworkerStage: String, Sendable {
    case preparingModel = "Preparing local AI"
    case readingContext = "Reading this window"
    case preparingActions = "Preparing action controls"
    case choosingAction = "Choosing the next action"
    case validatingReply = "Checking the plan"
    case checkingResult = "Checking the result"
}

/// Shared by every inference adapter. This is task state, not a skill or workflow store.
struct CoworkerProgress: Sendable {
    struct Checkpoint: Codable, Sendable, Equatable {
        let action: CoworkerReply.Action
        let result: String
        var verified: Bool = true
    }

    let goal: String
    let conversation: [CoworkerTurn]
    private(set) var checkpoints: [Checkpoint] = []
    private let started = ContinuousClock.now
    private var proposals = Set<Data>()
    let limit: Int

    init(goal: String, conversation: [CoworkerTurn], limit: Int = 8) {
        self.goal = goal
        self.conversation = conversation
        self.limit = limit
    }

    mutating func admit(_ reply: CoworkerReply, observation: CoworkerObservation) throws {
        try checkBudget()
        // This invariant belongs to the shared runner, not to model prompting.
        // A future adapter must not resume or replay after an uncertain mutation.
        guard checkpoints.allSatisfy(\.verified) else { throw CoworkerProgressError.unverifiedResult }
        struct Proposal: Encodable {
            let action: CoworkerReply.Action
            let content: String
            let target: Int
            let subject: String
            let observation: CoworkerObservation
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Proposal(action: reply.action, content: reply.content, target: reply.target,
            subject: reply.subject, observation: observation))
        guard proposals.insert(data).inserted else { throw CoworkerProgressError.noProgress }
    }

    mutating func record(_ action: CoworkerReply.Action, result: String, verified: Bool = true) {
        checkpoints.append(.init(action: action, result: String(result.prefix(600)), verified: verified))
    }

    func checkBudget() throws {
        guard checkpoints.count < limit, started.duration(to: .now) < .seconds(180) else {
            throw CoworkerProgressError.limit
        }
    }
}

enum CoworkerProgressError: LocalizedError {
    case noProgress, limit, unverifiedResult
    var errorDescription: String? {
        switch self {
        case .noProgress: "That step hasn't changed the result. I'll stop here rather than repeat it."
        case .limit: "I've reached the limit for this run. Tell me how you'd like to continue."
        case .unverifiedResult: "The previous action couldn't be verified, so I've stopped this run."
        }
    }
}

/// A native result. The model proposes actions; only the executor creates this value.
struct CoworkerActionResult: Sendable, Equatable {
    enum Verification: String, Sendable { case verified, unverified }
    let message: String
    let verification: Verification
    var applicationPID: Int32? = nil
    #if DEBUG
    var diagnostics: [String: String] = [:]
    #endif
    var canContinue: Bool { verification == .verified }
}

extension CoworkerGenerating {
    /// All model adapters cross the same shape and content checks before native execution.
    func validatedResponse(to request: CoworkerRequest) async throws -> CoworkerReply {
        var input = request
        for attempt in 0...1 {
            let generated = try await respond(to: input)
            try Task.checkCancellation()
            input.onStage?(.validatingReply)
            let data = try JSONEncoder().encode(generated)
            let decoded = try CoworkerReply.decode(String(decoding: data, as: UTF8.self))
            if let available = input.observation.availableActions, !available.contains(decoded.action) {
                throw CoworkerError.invalidResponse
            }
            let reply = input.observation.mailDraft == nil ? decoded : CoworkerMailDraftPolicy.normalize(decoded)
            var feedback = CoworkerMailDraftPolicy.feedback(for: reply, observation: input.observation)
            if [.write, .revise].contains(reply.action), let maximum = input.maximumDraftCharacters,
               reply.content.count > maximum {
                feedback = "Return the full revised draft within \(maximum) characters, preserving the supplied facts."
            }
            if let feedback {
                guard attempt == 0 else { throw CoworkerError.invalidResponse }
                input.validationFeedback = feedback
            } else { return reply }
        }
        throw CoworkerError.invalidResponse
    }
}
