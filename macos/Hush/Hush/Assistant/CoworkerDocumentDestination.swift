import Foundation

/// Semantic document operations are independent of application and AX transport.
/// Adapters must validate their whole snapshot, apply only supported fields, and
/// verify every changed field before reporting success.
struct CoworkerDocumentEdit {
    enum Field: Hashable { case title }
    let body: AssistantProposal
    let fields: [Field: String]
}

@MainActor
protocol CoworkerDocumentDestination: AssistantDestination {
    func update(_ edit: CoworkerDocumentEdit) async throws -> AssistantInsertionResult
}
