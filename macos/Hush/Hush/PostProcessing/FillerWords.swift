import Foundation

/// The safety floor of hesitation removal: sounds that are a word in no language ("uh",
/// "ähm", "hmm") are removed in code from every dictation, with or without AI, in any
/// language. Everything that depends on the language ("um" is German for "at") is left to
/// the speech model and the language model, which see the whole sentence. The sounds live
/// in FillerWords.json with their sources.
enum FillerWords {

    struct Lists: Decodable, Equatable {
        let sounds: [String]
    }

    static let bundled: Lists = load()

    static func load(from bundle: Bundle = .main) -> Lists {
        guard let url = bundle.url(forResource: "FillerWords", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let lists = try? JSONDecoder().decode(Lists.self, from: data) else {
            assertionFailure("FillerWords.json is missing from the app bundle or invalid")
            return Lists(sounds: [])
        }
        return lists
    }

    static func removing(from text: String, lists: Lists = bundled) -> String {
        let exact = Set(lists.sounds.map { $0.lowercased() })
        // Drawn-out sounds ("ummm", "hmmmm") match a listed drawn-out sound.
        let stretched = Set(exact.filter { $0 != squeezed($0) }.map(squeezed))

        func isFiller(_ word: Substring) -> Bool {
            let lower = word.lowercased()
            // An acronym such as "UHM" in a product name is a name, not a sound.
            if word.count >= 2, word == word.uppercased(), word != word.lowercased() { return false }
            if exact.contains(lower) { return true }
            // Three letters at least, so the unit "mm" stays.
            return lower.count >= 3 && lower != squeezed(lower) && stretched.contains(squeezed(lower))
        }

        let source = text as NSString
        let words = wordPattern.matches(in: text, range: NSRange(location: 0, length: source.length))
        var output = ""
        var cursor = 0
        var capitalOwed = false

        func append(_ segment: String) {
            guard capitalOwed, let index = segment.firstIndex(where: \.isLetter) else {
                output += segment
                return
            }
            capitalOwed = false
            output += segment[..<index] + segment[index].uppercased() + segment[segment.index(after: index)...]
        }

        for match in words {
            let range = match.range
            guard isFiller(Substring(source.substring(with: range))) else { continue }
            append(source.substring(with: NSRange(location: cursor, length: range.location - cursor)))

            var end = range.location + range.length
            let rest = source.substring(from: end)
            // The comma, ellipsis and space that only set the sound off go with it.
            let trailing = rest.prefixMatch(of: trailingPattern)
            let hadComma = trailing.map { $0.contains(",") } ?? false
            end += (trailing ?? "").utf16.count
            // "sollten, äh, morgen": the comma before the sound was only there for it too.
            if hadComma, output.hasSuffix(", ") { output.removeLast(2); output += " " }

            let opensSentence = output.trimmingCharacters(in: .whitespacesAndNewlines).last.map { ".!?…".contains($0) } ?? true
            if opensSentence, source.substring(with: range).first?.isUppercase == true { capitalOwed = true }
            cursor = end
        }
        append(source.substring(from: cursor))

        // "Das war's, äh." leaves "Das war's, ." behind.
        output = output.replacingOccurrences(of: #",\s*([.!?…])"#, with: "$1", options: .regularExpression)
        output = output.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        output = output.replacingOccurrences(of: #" ([,.])"#, with: "$1", options: .regularExpression)
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "ummm" -> "um": runs of one letter collapsed.
    static func squeezed(_ word: String) -> String {
        var result = ""
        for character in word where character != result.last { result.append(character) }
        return result
    }

    /// Words with inner apostrophes or hyphens stay whole, so "uh-oh" is one word.
    private static let wordPattern = try! NSRegularExpression(pattern: #"[\p{L}\p{M}]+(?:['’\-][\p{L}\p{M}]+)*"#)
    private static let trailingPattern = #/^(?:\s*(?:,|\.\.\.|…))?\s*/#
}

private extension String {
    func prefixMatch(of regex: Regex<Substring>) -> String? {
        guard let match = try? regex.prefixMatch(in: self), !match.output.isEmpty else { return nil }
        return String(match.output)
    }
}
