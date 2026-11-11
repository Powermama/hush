import Combine
import Foundation

@MainActor
final class AssistantSession: ObservableObject {
    enum Phase: Equatable { case ready, generating, review, applying, complete, paused, stopped }
    struct JournalEntry: Equatable {
        enum Outcome { case verified, unverified }
        let operationID: UUID
        let contextID: UUID
        let outcome: Outcome
    }

    @Published private(set) var phase: Phase = .ready
    @Published private(set) var status = "Describe the email you want to write."
    @Published private(set) var proposal: AssistantProposal?
    @Published var request = ""
    private(set) var journal: [JournalEntry] = []
    let destination: any AssistantDestination
    private let generator: any AssistantGenerating
    private var task: Task<Void, Never>?
    private var deadline: Task<Void, Never>?
    private var operationID = UUID()
    private var insertionStarted = false
    var onTargetVisibilityChange: ((Bool) -> Void)?

    init(destination: any AssistantDestination, generator: any AssistantGenerating) {
        self.destination = destination
        self.generator = generator
    }

    var isBusy: Bool { phase == .generating || phase == .applying }
    var canSubmit: Bool { !isBusy && !insertionStarted }
    var canInsert: Bool { phase == .review && proposal?.decision == .draft && !insertionStarted }

    func receiveTranscript(_ text: String, contextID: UUID) {
        guard destination.context.id == contextID, canSubmit else { return }
        if !request.isEmpty { request += " " }
        request += text
    }

    func submit(_ request: String) {
        guard !isBusy, !insertionStarted else { return }
        let brief = AssistantBrief(request: request, context: destination.context)
        do {
            try brief.validate()
            try destination.validate()
        } catch { pause(error); return }
        operationID = UUID()
        let operation = operationID
        proposal = nil
        phase = .generating
        status = "Writing on this Mac…"
        onTargetVisibilityChange?(true)
        deadline?.cancel()
        deadline = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(60)) } catch { return }
            guard let self, self.operationID == operation, self.phase == .generating else { return }
            self.task?.cancel()
            self.operationID = UUID()
            self.pause(AssistantFailure.timedOut)
        }
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let generated = try await generator.generate(brief)
                try Task.checkCancellation()
                guard operationID == operation else { return }
                try generated.validate(for: brief)
                try destination.validate()
                proposal = generated
                if generated.decision == .clarify {
                    phase = .ready
                    status = generated.message
                } else {
                    phase = .review
                    status = "Review your draft, then insert it into the bound email body."
                }
            } catch {
                guard operationID == operation, !Task.isCancelled else { return }
                pause(error)
            }
            if operationID == operation { deadline?.cancel(); task = nil }
        }
    }

    func insert() {
        guard canInsert, let proposal else { return }
        do { try destination.validate() } catch { pause(error); return }
        let operation = operationID
        insertionStarted = true
        phase = .applying
        status = "Inserting into the email body…"
        task = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await destination.insert(proposal)
                journal.append(JournalEntry(operationID: operation, contextID: destination.context.id,
                                            outcome: result == .verified ? .verified : .unverified))
                if journal.count > 30 { journal.removeFirst(journal.count - 30) }
                phase = result == .verified ? .complete : .paused
                status = result == .verified
                    ? "Inserted and checked in Mail. Ready for you to review and send."
                    : "Paste was requested, but Hush could not confirm it. Check Mail before trying again."
            } catch {
                pause(error)
            }
            onTargetVisibilityChange?(false)
            task = nil
        }
    }

    func stop() {
        deadline?.cancel()
        task?.cancel()
        onTargetVisibilityChange?(false)
        if insertionStarted {
            // The adapter still reads back a dispatched mutation. Cancellation cannot
            // retract a paste already delivered to another process.
            if phase == .applying { status = "Stopping. Checking whether the paste already reached Mail…" }
        } else {
            operationID = UUID()
            phase = .stopped
            status = "Stopped. Your email has not been changed."
        }
    }

    private func pause(_ error: Error) {
        phase = .paused
        status = error.localizedDescription
        onTargetVisibilityChange?(false)
    }
}
