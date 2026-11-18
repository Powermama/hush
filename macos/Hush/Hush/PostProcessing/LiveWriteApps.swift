import Foundation

/// An app where Live Write stays off and the user's words go in as spoken.
nonisolated struct LiveWriteAppException: Codable, Equatable, Hashable, Sendable {
    let bundleIdentifier: String
    let displayName: String
}

/// Where Live Write steps aside (PRD R4, R10). In terminals and code editors text is a
/// command or code, in AI chats it is a prompt, and in password managers it is a secret:
/// rewriting would change what the user means. The standard list follows the app types the
/// studied dictation apps keep (Wispr Flow's per-type lists with per-app overrides, phonon's
/// denylist); the user can add apps, remove them, or reset to the standard.
nonisolated enum LiveWriteApps {
    static let standard: [LiveWriteAppException] = [
        // Terminals
        .init(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal"),
        .init(bundleIdentifier: "com.googlecode.iterm2", displayName: "iTerm2"),
        .init(bundleIdentifier: "com.mitchellh.ghostty", displayName: "Ghostty"),
        .init(bundleIdentifier: "dev.warp.Warp-Stable", displayName: "Warp"),
        .init(bundleIdentifier: "net.kovidgoyal.kitty", displayName: "kitty"),
        .init(bundleIdentifier: "com.github.wez.wezterm", displayName: "WezTerm"),
        .init(bundleIdentifier: "org.alacritty", displayName: "Alacritty"),
        // Code editors
        .init(bundleIdentifier: "com.apple.dt.Xcode", displayName: "Xcode"),
        .init(bundleIdentifier: "com.microsoft.VSCode", displayName: "Visual Studio Code"),
        .init(bundleIdentifier: "com.todesktop.230313mzl4w4u92", displayName: "Cursor"),
        .init(bundleIdentifier: "dev.zed.Zed", displayName: "Zed"),
        .init(bundleIdentifier: "com.sublimetext.4", displayName: "Sublime Text"),
        .init(bundleIdentifier: "com.jetbrains.intellij", displayName: "IntelliJ IDEA"),
        // AI chats: what the user says is a prompt.
        .init(bundleIdentifier: "com.openai.chat", displayName: "ChatGPT"),
        .init(bundleIdentifier: "com.anthropic.claudefordesktop", displayName: "Claude"),
        .init(bundleIdentifier: "ai.perplexity.mac", displayName: "Perplexity"),
        // Password managers
        .init(bundleIdentifier: "com.1password.1password", displayName: "1Password"),
        .init(bundleIdentifier: "com.bitwarden.desktop", displayName: "Bitwarden"),
    ]

    /// AI chats in the browser take prompts just as their apps do. Verified Messages' website
    /// rule normalises hosts and matches subdomains, so both features read sites the same way.
    static let standardWebsites: [VerifiedMessageWebsiteException] = [
        "chatgpt.com", "claude.ai", "perplexity.ai", "gemini.google.com",
    ].compactMap(VerifiedMessageWebsiteException.init(host:))

    /// Whether Live Write should step aside for the app, or the website in it, that the
    /// dictation goes to.
    static func isExcluded(_ bundleIdentifier: String?, websiteHost: String? = nil,
                           apps: [LiveWriteAppException], websites: [VerifiedMessageWebsiteException] = []) -> Bool {
        if let bundleIdentifier,
           apps.contains(where: { $0.bundleIdentifier.caseInsensitiveCompare(bundleIdentifier) == .orderedSame }) {
            return true
        }
        guard let websiteHost else { return false }
        return websites.contains { $0.matches(websiteHost) }
    }

    /// Only apps on this Mac are listed; standard entries for others stay in place and apply
    /// once such an app is installed.
    static func installed(_ exceptions: [LiveWriteAppException], isInstalled: (String) -> Bool) -> [LiveWriteAppException] {
        exceptions.filter { isInstalled($0.bundleIdentifier) }
    }

    /// Unique by bundle identifier, sorted by name, as the user sees the list.
    static func normalized(_ exceptions: [LiveWriteAppException]) -> [LiveWriteAppException] {
        var seen = Set<String>()
        return exceptions
            .filter { seen.insert($0.bundleIdentifier.lowercased()).inserted }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
