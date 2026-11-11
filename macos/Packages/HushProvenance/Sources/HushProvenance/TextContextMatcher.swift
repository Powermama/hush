import Foundation

public struct RecentTextCandidate: Equatable, Sendable {
    public let text: String
    public let bundleIdentifier: String
    public let copiedToClipboard: Bool
    public let proofId: String?
    public let proofCommitment: String?
    public let provenanceEvents: [ProofManifest.ProvenanceEvent]
    public let sourceText: String?

    public init(
        text: String,
        bundleIdentifier: String,
        copiedToClipboard: Bool,
        proofId: String? = nil,
        proofCommitment: String? = nil,
        provenanceEvents: [ProofManifest.ProvenanceEvent] = [],
        sourceText: String? = nil
    ) {
        self.text = text
        self.bundleIdentifier = bundleIdentifier
        self.copiedToClipboard = copiedToClipboard
        self.proofId = proofId
        self.proofCommitment = proofCommitment
        self.provenanceEvents = provenanceEvents
        self.sourceText = sourceText
    }
}

public struct TextContextMatch: Equatable, Sendable {
    public let message: String
    public let expectedText: String
    public let replacementRange: NSRange
    public let proofId: String?
    public let proofCommitment: String?
    public let provenanceEvents: [ProofManifest.ProvenanceEvent]
    public let sourceText: String?

    public init(
        message: String,
        expectedText: String,
        replacementRange: NSRange,
        proofId: String? = nil,
        proofCommitment: String? = nil,
        provenanceEvents: [ProofManifest.ProvenanceEvent] = [],
        sourceText: String? = nil
    ) {
        self.message = message
        self.expectedText = expectedText
        self.replacementRange = replacementRange
        self.proofId = proofId
        self.proofCommitment = proofCommitment
        self.provenanceEvents = provenanceEvents
        self.sourceText = sourceText
    }
}

public enum TextContextMatcher {
    public static let minimumSimilarity = 0.95
    public static let minimumAutomaticMatchLength = 20

    /// Finds the newest exact Hush output in the focused field. A directly
    /// adjacent proof signature is included so editing cannot leave a stale
    /// verification link behind.
    public static func match(
        fieldValue: String,
        bundleIdentifier: String,
        candidates: [RecentTextCandidate],
        selectionLocation: Int? = nil,
        selectedRange: NSRange? = nil
    ) -> TextContextMatch? {
        let field = fieldValue as NSString
        var matches: [(distance: Int, similarity: Double, candidateIndex: Int, match: TextContextMatch)] = []
        for (candidateIndex, candidate) in candidates.enumerated() where
            candidate.bundleIdentifier == bundleIdentifier &&
            !candidate.copiedToClipboard &&
            candidate.text.utf16.count >= minimumAutomaticMatchLength {
            var searchRange = NSRange(location: 0, length: field.length)
            while searchRange.length > 0 {
                let messageRange = field.range(of: candidate.text, range: searchRange)
                guard messageRange.location != NSNotFound else { break }
                let replacementRange = includingProofSignature(after: messageRange, in: field)
                guard isRelevant(replacementRange, to: selectedRange) else {
                    let nextLocation = NSMaxRange(messageRange)
                    guard nextLocation > searchRange.location else { break }
                    searchRange = NSRange(
                        location: nextLocation,
                        length: field.length - nextLocation
                    )
                    continue
                }
                let match = TextContextMatch(
                    message: candidate.text,
                    expectedText: field.substring(with: replacementRange),
                    replacementRange: replacementRange,
                    proofId: candidate.proofId,
                    proofCommitment: candidate.proofCommitment,
                    provenanceEvents: candidate.provenanceEvents,
                    sourceText: candidate.sourceText
                )
                matches.append((
                    distance(from: selectionLocation, to: messageRange),
                    1,
                    candidateIndex,
                    match
                ))

                let nextLocation = NSMaxRange(messageRange)
                guard nextLocation > searchRange.location else { break }
                searchRange = NSRange(
                    location: nextLocation,
                    length: field.length - nextLocation
                )
            }
        }
        if let selectionLocation {
            let fieldBlocks = blocks(in: field)
            for (candidateIndex, candidate) in candidates.prefix(50).enumerated() where
                candidate.bundleIdentifier == bundleIdentifier && !candidate.copiedToClipboard {
                guard let approximate = approximateMatch(
                    candidate: candidate.text,
                    field: field,
                    fieldBlocks: fieldBlocks,
                    selectionLocation: selectionLocation
                ) else { continue }
                let replacementRange = includingProofSignature(after: approximate.range, in: field)
                guard isRelevant(replacementRange, to: selectedRange) else { continue }
                matches.append((
                    distance(from: selectionLocation, to: approximate.range),
                    approximate.similarity,
                    candidateIndex,
                    TextContextMatch(
                        message: field.substring(with: approximate.range),
                        expectedText: field.substring(with: replacementRange),
                        replacementRange: replacementRange,
                        proofId: candidate.proofId,
                        proofCommitment: candidate.proofCommitment,
                        provenanceEvents: candidate.provenanceEvents,
                        sourceText: candidate.sourceText
                    )
                ))
            }
        }
        return matches.min { lhs, rhs in
            if lhs.distance != rhs.distance { return lhs.distance < rhs.distance }
            if lhs.similarity != rhs.similarity { return lhs.similarity > rhs.similarity }
            return lhs.candidateIndex < rhs.candidateIndex
        }?.match
    }

    public static func isValid(
        range: NSRange,
        expectedText: String,
        in currentValue: String
    ) -> Bool {
        guard range.location >= 0,
              range.length >= 0,
              NSMaxRange(range) <= (currentValue as NSString).length else {
            return false
        }
        return (currentValue as NSString).substring(with: range) == expectedText
    }

    private static func approximateMatch(
        candidate: String,
        field: NSString,
        fieldBlocks: [NSRange],
        selectionLocation: Int
    ) -> (range: NSRange, similarity: Double)? {
        let candidateBlocks = blocks(in: candidate as NSString)
        guard !candidateBlocks.isEmpty,
              candidate.utf16.count >= 40,
              candidateBlocks.count <= fieldBlocks.count else { return nil }

        var best: (range: NSRange, similarity: Double)?
        for start in 0...(fieldBlocks.count - candidateBlocks.count) {
            let end = start + candidateBlocks.count - 1
            let range = NSRange(
                location: fieldBlocks[start].location,
                length: NSMaxRange(fieldBlocks[end]) - fieldBlocks[start].location
            )
            guard selectionLocation >= range.location,
                  selectionLocation <= NSMaxRange(range) else { continue }
            let score = similarity(
                normalized(candidate),
                normalized(field.substring(with: range))
            )
            guard score >= minimumSimilarity else { continue }
            if best == nil || score > best!.similarity {
                best = (range, score)
            }
        }
        return best
    }

    private static func blocks(in text: NSString) -> [NSRange] {
        let expression = try! NSRegularExpression(
            pattern: #"(?s)(^|\n{2,})(.*?)(?=\n{2,}|$)"#
        )
        return expression.matches(
            in: text as String,
            range: NSRange(location: 0, length: text.length)
        ).compactMap { result in
            let range = result.range(at: 2)
            return range.length > 0 ? range : nil
        }
    }

    private static func normalized(_ text: String) -> [Character] {
        text.lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .map { $0 }
    }

    private static func similarity(_ lhs: [Character], _ rhs: [Character]) -> Double {
        let denominator = max(lhs.count, rhs.count)
        guard denominator > 0 else { return 1 }
        let maximumDistance = Int(
            floor(Double(denominator) * (1 - minimumSimilarity))
        )
        guard abs(lhs.count - rhs.count) <= maximumDistance else { return 0 }

        let unreachable = maximumDistance + 1
        var previous = Array(repeating: unreachable, count: rhs.count + 1)
        for column in 0...min(rhs.count, maximumDistance) {
            previous[column] = column
        }
        for (row, left) in lhs.enumerated() {
            let index = row + 1
            var current = Array(repeating: unreachable, count: rhs.count + 1)
            if index <= maximumDistance { current[0] = index }
            let lowerBound = max(1, index - maximumDistance)
            let upperBound = min(rhs.count, index + maximumDistance)
            guard lowerBound <= upperBound else { return 0 }
            var rowMinimum = unreachable
            for column in lowerBound...upperBound {
                current[column] = Swift.min(
                    Swift.min(current[column - 1] + 1, previous[column] + 1),
                    previous[column - 1] + (left == rhs[column - 1] ? 0 : 1)
                )
                rowMinimum = min(rowMinimum, current[column])
            }
            if rowMinimum > maximumDistance { return 0 }
            previous = current
        }
        let editDistance = previous[rhs.count]
        guard editDistance <= maximumDistance else { return 0 }
        return 1 - Double(editDistance) / Double(denominator)
    }

    private static func includingProofSignature(after range: NSRange, in field: NSString) -> NSRange {
        var result = range
        let suffixLocation = NSMaxRange(range)
        guard suffixLocation < field.length else { return result }
        let suffix = field.substring(from: suffixLocation) as NSString
        let signatureRange = suffix.range(
            of: #"^(?:\n\n-typed with hush(?::[^\n]*)?)+"#,
            options: .regularExpression
        )
        if signatureRange.location == 0 { result.length += signatureRange.length }
        return result
    }

    private static func distance(from location: Int?, to range: NSRange) -> Int {
        guard let location else { return 0 }
        if location < range.location { return range.location - location }
        if location > NSMaxRange(range) { return location - NSMaxRange(range) }
        return 0
    }

    private static func isRelevant(_ candidateRange: NSRange, to selectedRange: NSRange?) -> Bool {
        guard let selectedRange, selectedRange.length > 0 else { return true }
        return NSIntersectionRange(candidateRange, selectedRange).length > 0
    }
}
