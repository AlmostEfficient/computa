import Foundation

/// A user vocabulary line: `Term` or `Term: misheard, other misheard`.
/// The transcription model ignores hints, so terms are enforced on the final text:
/// listed mishearings become the term, and the term itself gets its exact capitalisation.
struct VocabularyEntry: Equatable {
    let term: String
    let misheard: [String]

    static func parse(_ text: String) -> [VocabularyEntry] {
        text.split(whereSeparator: \.isNewline).compactMap { line in
            let parts = line.split(separator: ":", maxSplits: 1)
            let term = parts[0].trimmingCharacters(in: .whitespaces)
            guard !term.isEmpty else { return nil }
            let misheard = parts.count > 1
                ? parts[1].split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                : []
            return VocabularyEntry(term: term, misheard: misheard)
        }
    }

    static func apply(_ entries: [VocabularyEntry], to text: String) -> String {
        entries.reduce(text) { result, entry in
            // Longest phrases first so "ghost tea" wins over "ghost".
            (entry.misheard.sorted { $0.count > $1.count } + [entry.term]).reduce(result) { replace($1, with: entry.term, in: $0) }
        }
    }

    private static func replace(_ phrase: String, with term: String, in text: String) -> String {
        let words = phrase.split(separator: " ").map { NSRegularExpression.escapedPattern(for: String($0)) }
        // Whole words only, any spacing between the phrase's words, any case.
        let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                              withTemplate: NSRegularExpression.escapedTemplate(for: term))
    }
}
