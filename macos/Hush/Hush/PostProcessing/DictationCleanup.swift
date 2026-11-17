import Foundation

/// Deterministic steps after the language model, as the rules layers of open
/// dictation tools do: what a small model gets wrong now and then, code gets
/// right every time: protocol echoes, subject lines nobody asked for, Markdown
/// and template placeholders go, and list markers become plain "- " lines that
/// paste well into Mail, Slack or a document. Hesitations are the model's job.
enum DictationCleanup {

    // MARK: After the model

    /// Whether a model's answer is unusable, so the user's own words are pasted instead
    /// (as phonon guards its refiner): empty, runaway or collapsed. A correction stays
    /// close to the length of what was said; a written text may be much longer than
    /// the request that described it, but not endless.
    static func isUnusable(_ output: String, dictation: String, mode: Profile.Mode) -> Bool {
        func words(_ text: String) -> Int { text.split(whereSeparator: \.isWhitespace).count }
        let said = max(words(dictation), 1)
        let answered = words(output)
        if answered == 0 { return true }
        switch mode {
        case .correct: return answered > said * 2 + 20 || (said >= 8 && answered * 10 < said * 4)
        case .compose: return answered > said * 8 + 120
        }
    }

    static func finishing(_ output: String, dictation: String) -> String {
        var text = output

        // A model that echoes its prompt or an example: keep only the answer after it.
        if text.range(of: "<dictation>") != nil || text.range(of: "<persona>") != nil {
            if let answer = text.range(of: "Answer:", options: .backwards) {
                text = String(text[answer.upperBound...])
            } else if let end = text.range(of: "</dictation>", options: .backwards) {
                text = String(text[end.upperBound...])
            }
        }
        text = text.replacingOccurrences(of: "</?(persona|creativity|language|dictation)>", with: "", options: .regularExpression)

        var lines = text.components(separatedBy: "\n")

        // A preamble line introducing the answer, such as "Hier ist der Entwurf:" or "Here is the email:".
        if let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].range(of: #"^\W*(here is|here's|hier ist|hier sind|gerne|sure|certainly|natürlich)\b[^\n]{0,80}:\W*$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            lines.remove(at: first)
        }

        // A subject line only when the speaker asked for one; pasted into a message body it does not belong.
        let askedForSubject = dictation.range(of: "subject|betreff", options: [.regularExpression, .caseInsensitive]) != nil
        if !askedForSubject, let first = lines.firstIndex(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }),
           lines[first].range(of: #"^\W*(subject|betreff)\s*:"#, options: [.regularExpression, .caseInsensitive]) != nil {
            lines.remove(at: first)
        }

        lines = lines.compactMap { line in
            var line = line
            // Template placeholders on a line of their own, such as "[Your Name]".
            if line.range(of: #"^\s*\[[^\]]{1,40}\]\s*$"#, options: .regularExpression) != nil { return nil }
            // Headings and list markers as plain text.
            line = line.replacingOccurrences(of: #"^\s{0,3}#{1,6}\s+"#, with: "", options: .regularExpression)
            line = line.replacingOccurrences(of: #"^(\s*)[*•·–]\s+"#, with: "$1- ", options: .regularExpression)
            return line
        }
        text = lines.joined(separator: "\n")
        // Bold and italic markers around words.
        text = text.replacingOccurrences(of: #"\*\*(.+?)\*\*|__(.+?)__"#, with: "$1$2", options: .regularExpression)
        text = text.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
