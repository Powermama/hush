import Foundation

/// Ranks personas for the text currently open in the selection editor.
/// The ranking is intentionally local and deterministic so the first chat
/// screen feels relevant without spending tokens or delaying the UI.
nonisolated enum PersonaSuggestionRanker {
    static func ranked(
        profiles: [Profile],
        activeProfileID: UUID?,
        applicationName: String,
        bundleIdentifier: String?,
        websiteHost: String?,
        text: String
    ) -> [Profile] {
        let destination = [applicationName, bundleIdentifier, websiteHost]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let content = text.lowercased()
        let contentTokens = meaningfulTokens(in: content)

        return profiles.enumerated()
            .map { index, profile in
                var score = profile.id == activeProfileID ? 1 : 0
                let name = profile.name.lowercased()
                let prompt = profile.systemPrompt.lowercased()

                if destination.contains("slack") {
                    score += name.contains("slack") ? 14 : 0
                    score += name.contains("casual") ? 5 : 0
                } else if containsAny(destination, ["telegram", "whatsapp", "messages", "imessage", "signal", "discord", "messenger"]) {
                    score += name.contains("casual") ? 11 : 0
                    score += name.contains("slack") ? 4 : 0
                }

                if containsAny(destination, ["mail", "outlook", "gmail", "superhuman"]) {
                    score += name.contains("business") ? 12 : 0
                    score += name.contains("polish") ? 5 : 0
                }

                if containsAny(destination, ["xcode", "terminal", "iterm", "warp", "visual studio", "vscode", "github", "code"]) {
                    score += name.contains("code") ? 14 : 0
                }

                if containsAny(content, ["func ", "class ", "struct ", "let ", "var ", "//", "```", "error:"]) {
                    score += name.contains("code") ? 9 : 0
                }
                if containsAny(content, ["hi ", "hey ", "thanks", "thank you", "lol", "haha"]) {
                    score += name.contains("casual") ? 4 : 0
                }
                if content.split(whereSeparator: \Character.isWhitespace).count > 60 {
                    score += name.contains("polish") ? 4 : 0
                    score += name.contains("business") ? 2 : 0
                }

                let profileTokens = meaningfulTokens(in: "\(name) \(prompt)")
                score += min(6, profileTokens.intersection(contentTokens).count * 2)
                return (profile: profile, score: score, originalIndex: index)
            }
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                return $0.originalIndex < $1.originalIndex
            }
            .map(\.profile)
    }

    static func openingDetail(
        applicationName: String,
        bundleIdentifier: String?,
        text: String,
        bestProfileName: String?,
        selectedProfileName: String?
    ) -> String {
        let destination = [applicationName, bundleIdentifier]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
        let wordCount = text.split(whereSeparator: \Character.isWhitespace).count
        let opportunity: String

        if containsAny(destination, ["telegram", "whatsapp", "messages", "imessage", "signal", "discord", "messenger", "slack"]) {
            opportunity = wordCount > 35
                ? "I can tighten it or make it more conversational."
                : "I can make it clearer or more conversational."
        } else if containsAny(destination, ["mail", "outlook", "gmail", "superhuman"]) {
            opportunity = "I can make it more concise or more professional."
        } else if containsAny(destination, ["xcode", "terminal", "iterm", "warp", "visual studio", "vscode", "github", "code"]) {
            opportunity = "I can clarify it or turn it into a concise code comment."
        } else if wordCount > 60 {
            opportunity = "I can shorten it or improve its structure."
        } else {
            opportunity = "I can polish the wording or adjust the tone."
        }

        if let selectedProfileName {
            return "\(opportunity) \(selectedProfileName) will guide the first edit."
        }
        if let bestProfileName {
            return "\(opportunity) \(bestProfileName) may fit best."
        }
        return opportunity
    }

    private static func containsAny(_ value: String, _ candidates: [String]) -> Bool {
        candidates.contains(where: value.contains)
    }

    private static func meaningfulTokens(in value: String) -> Set<String> {
        let ignored: Set<String> = [
            "this", "that", "with", "from", "your", "into", "text", "message",
            "rewrite", "keep", "make", "only", "where", "when", "have", "will"
        ]
        return Set(value.components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.lowercased() }
            .filter { $0.count >= 4 && !ignored.contains($0) })
    }
}
