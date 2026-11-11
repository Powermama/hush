import Foundation

struct PersonaIconChoice: Sendable, Equatable {
    let symbol: String
    let title: String
}

/// Keeps persona icons useful without turning profile creation into setup work.
/// A user override wins; otherwise Hush infers a stable SF Symbol locally from
/// the profile name and instructions.
enum PersonaIconResolver {
    static let choices: [PersonaIconChoice] = [
        .init(symbol: "sparkles", title: "Polish"),
        .init(symbol: "briefcase.fill", title: "Business"),
        .init(symbol: "face.smiling.fill", title: "Friendly"),
        .init(symbol: "bubble.left.and.bubble.right.fill", title: "Chat"),
        .init(symbol: "chevron.left.forwardslash.chevron.right", title: "Code"),
        .init(symbol: "doc.text.magnifyingglass", title: "Research"),
        .init(symbol: "checkmark.shield.fill", title: "Legal"),
        .init(symbol: "shippingbox.fill", title: "Product"),
        .init(symbol: "envelope.fill", title: "Email"),
        .init(symbol: "megaphone.fill", title: "Marketing"),
        .init(symbol: "chart.line.uptrend.xyaxis", title: "Growth"),
        .init(symbol: "graduationcap.fill", title: "Academic"),
        .init(symbol: "character.book.closed.fill", title: "Translation"),
        .init(symbol: "person.2.fill", title: "Meetings"),
        .init(symbol: "paintpalette.fill", title: "Creative"),
        .init(symbol: "pencil", title: "Writing"),
    ]

    static func symbol(for profile: Profile) -> String {
        if let override = profile.iconName,
           choices.contains(where: { $0.symbol == override }) {
            return override
        }

        switch profile.id {
        case Profile.SeedID.polish: return "sparkles"
        case Profile.SeedID.business: return "briefcase.fill"
        case Profile.SeedID.casual: return "face.smiling.fill"
        case Profile.SeedID.slack: return "bubble.left.and.bubble.right.fill"
        case Profile.SeedID.codeComment: return "chevron.left.forwardslash.chevron.right"
        default: break
        }

        let text = "\(profile.name) \(profile.systemPrompt)".lowercased()
        let rules: [([String], String)] = [
            (["translate", "translation", "language"], "character.book.closed.fill"),
            (["legal", "law", "contract", "compliance"], "checkmark.shield.fill"),
            (["research", "finding", "analysis", "source"], "doc.text.magnifyingglass"),
            (["code", "developer", "technical", "programming"], "chevron.left.forwardslash.chevron.right"),
            (["product", "feature", "roadmap"], "shippingbox.fill"),
            (["email", "mail", "newsletter"], "envelope.fill"),
            (["marketing", "campaign", "social", "promotion"], "megaphone.fill"),
            (["sales", "growth", "revenue", "conversion"], "chart.line.uptrend.xyaxis"),
            (["academic", "student", "teacher", "lesson"], "graduationcap.fill"),
            (["meeting", "team", "standup", "interview"], "person.2.fill"),
            (["creative", "story", "imaginative"], "paintpalette.fill"),
            (["slack", "chat", "message", "conversation"], "bubble.left.and.bubble.right.fill"),
            (["business", "professional", "executive", "formal"], "briefcase.fill"),
            (["casual", "friendly", "warm"], "face.smiling.fill"),
            (["grammar", "punctuation", "polish", "correct"], "sparkles"),
            (["write", "rewrite", "copy", "editor"], "pencil"),
        ]
        if let match = rules.first(where: { keywords, _ in
            keywords.contains(where: text.contains)
        }) {
            return match.1
        }

        let seed = profile.id.uuidString.utf8.reduce(UInt(0)) {
            ($0 &* 31) &+ UInt($1)
        }
        return choices[Int(seed % UInt(choices.count))].symbol
    }
}
