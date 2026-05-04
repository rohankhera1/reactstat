import Foundation
import NaturalLanguage

// MARK: - Profile

struct PersonalityProfile: Identifiable {
    let id = UUID()
    let name: String
    let messageCount: Int

    // Trait scores 0.0–1.0 (used for visual bars)
    let warmth: Double          // sentiment positivity
    let expressiveness: Double  // emoji density + exclamations
    let verbosity: Double       // avg words/message
    let curiosity: Double       // question frequency
    let enthusiasm: Double      // exclamation frequency
    let lexicalRichness: Double // unique word ratio

    // Free-form AI-generated (or fallback template) descriptor
    let descriptor: String
}

// MARK: - Traits (internal intermediate)

struct PersonalityTraits {
    let warmth: Double
    let expressiveness: Double
    let verbosity: Double
    let curiosity: Double
    let enthusiasm: Double
    let lexical: Double
}

// MARK: - Analyzer (trait computation only — no classification)

enum PersonalityAnalyzer {

    static let minMessages = 5

    // Returns cleaned messages for a person.
    static func cleaned(_ messages: [String]) -> [String] {
        messages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "\u{FFFC}" }
    }

    // Extracts person names from messages using NER, sorted by frequency.
    // Samples up to 10k messages for performance; counts occurrences across all messages.
    static func extractTopNames(from messages: [String], topN: Int = 30) -> [(name: String, count: Int)] {
        let tagger = NLTagger(tagSchemes: [.nameType])
        var candidates: Set<String> = []

        let nerSample = messages.count > 10_000
            ? Array(messages.shuffled().prefix(10_000))
            : messages

        for message in nerSample {
            guard message.count > 4 else { continue }
            tagger.string = message
            tagger.enumerateTags(
                in: message.startIndex..<message.endIndex,
                unit: .word, scheme: .nameType,
                options: [.omitWhitespace, .omitPunctuation]
            ) { tag, range in
                if tag == .personalName {
                    let name = String(message[range])
                        .trimmingCharacters(in: .punctuationCharacters)
                    if name.count >= 3 { candidates.insert(name) }
                }
                return true
            }
        }

        // Count actual occurrences across ALL messages for accurate ranking.
        return candidates.map { name -> (name: String, count: Int) in
            let count = messages.filter { $0.localizedCaseInsensitiveContains(name) }.count
            return (name: name, count: count)
        }
        .filter { $0.count >= 3 }
        .sorted { $0.count > $1.count }
        .prefix(topN)
        .map { $0 }
    }

    // Compute trait scores for a message collection.
    static func traits(for messages: [String]) -> PersonalityTraits? {
        let clean = cleaned(messages)
        guard clean.count >= minMessages else { return nil }
        return PersonalityTraits(
            warmth:         computeSentiment(clean),
            expressiveness: computeExpressiveness(clean),
            verbosity:      computeVerbosity(clean),
            curiosity:      computeCuriosity(clean),
            enthusiasm:     computeEnthusiasm(clean),
            lexical:        computeLexicalRichness(clean)
        )
    }

    // MARK: - Individual trait functions

    static func computeSentiment(_ messages: [String]) -> Double {
        let tagger = NLTagger(tagSchemes: [.sentimentScore])
        var total = 0.0
        var count = 0

        for msg in messages.prefix(250) {
            guard msg.count > 3 else { continue }
            tagger.string = msg
            let (tag, _) = tagger.tag(at: msg.startIndex, unit: .paragraph, scheme: .sentimentScore)
            if let val = tag?.rawValue, let score = Double(val) {
                total += score
                count += 1
            }
        }
        guard count > 0 else { return 0.5 }
        return min(1.0, max(0.0, (total / Double(count) + 1.0) / 2.0))
    }

    static func computeExpressiveness(_ messages: [String]) -> Double {
        var emojiCount = 0
        var totalChars = 0
        var exclamMsgs = 0

        for msg in messages {
            totalChars += msg.count
            emojiCount += msg.unicodeScalars.filter { $0.properties.isEmojiPresentation }.count
            if msg.contains("!") { exclamMsgs += 1 }
        }

        let emojiScore  = totalChars > 0 ? min(1.0, Double(emojiCount) / Double(totalChars) / 0.03) : 0
        let exclamScore = min(1.0, Double(exclamMsgs) / Double(messages.count) / 0.30)
        return emojiScore * 0.6 + exclamScore * 0.4
    }

    static func computeVerbosity(_ messages: [String]) -> Double {
        let total = messages.reduce(0) {
            $0 + $1.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.count
        }
        let avg = Double(total) / Double(max(1, messages.count))
        return min(1.0, max(0.0, (avg - 2.0) / 28.0))
    }

    static func computeCuriosity(_ messages: [String]) -> Double {
        let q = messages.filter { $0.contains("?") }.count
        return min(1.0, Double(q) / Double(max(1, messages.count)))
    }

    static func computeEnthusiasm(_ messages: [String]) -> Double {
        let e = messages.filter { $0.contains("!") }.count
        return min(1.0, Double(e) / Double(max(1, messages.count)))
    }

    static func computeLexicalRichness(_ messages: [String]) -> Double {
        let tagger = NLTagger(tagSchemes: [.tokenType])
        let combined = messages.prefix(100).joined(separator: " ")
        tagger.string = combined

        var words: [String] = []
        tagger.enumerateTags(in: combined.startIndex..<combined.endIndex,
                             unit: .word, scheme: .tokenType) { tag, range in
            if tag == .word { words.append(combined[range].lowercased()) }
            return true
        }

        guard words.count > 10 else { return 0.5 }
        let ratio = Double(Set(words).count) / Double(words.count)
        return min(1.0, max(0.0, (ratio - 0.3) / 0.5))
    }

    // MARK: - Fallback descriptor (no API key)

    static func fallbackDescriptor(traits t: PersonalityTraits, messageCount: Int) -> String {
        var parts: [String] = []

        let lengthDesc = t.verbosity > 0.5 ? "long, detailed messages"
                       : t.verbosity < 0.12 ? "very short messages"
                       : "relatively short messages"
        let toneDesc = t.warmth > 0.62 ? "an upbeat tone"
                     : t.warmth < 0.40 ? "a reserved tone"
                     : "a balanced tone"
        parts.append("Tends to write \(lengthDesc) with \(toneDesc).")

        var extras: [String] = []
        if t.curiosity > 0.25 { extras.append("asks questions frequently") }
        if t.enthusiasm > 0.35 { extras.append("uses a lot of exclamation marks") }
        if t.expressiveness > 0.40 { extras.append("expressive with emoji") }
        if t.lexical > 0.65 { extras.append("varied vocabulary") }
        if !extras.isEmpty {
            parts.append("Notable for: \(extras.joined(separator: ", ")).")
        }

        parts.append("Based on \(messageCount) messages.")
        return parts.joined(separator: " ")
    }
}
