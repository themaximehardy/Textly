import Foundation

/// Writes the shared rules (Settings › Rules & Glossary) from the languages and style chosen during setup.
/// For French and English, mixed, British English, it produces exactly `DefaultPrompts.sharedRules`.
enum SharedRulesBuilder {
    static func build(_ profile: WritingProfile) -> String {
        var names: [String] = []
        for raw in profile.languages {
            let name = baseName(raw)
            guard !name.isEmpty, !names.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) else { continue }
            names.append(name)
        }
        let hasFrench = names.contains { matches($0, "French", "Français") }
        let hasEnglish = names.contains { matches($0, "English") }
        let mixes = profile.mixesLanguages && names.count > 1

        let intro: String
        switch names.count {
        case 0: intro = "You are an expert writing assistant."
        case 1: intro = "You are an expert \(names[0]) writing assistant."
        case 2: intro = "You are an expert bilingual \(names[0]) and \(names[1]) writing assistant."
        default: intro = "You are an expert multilingual writing assistant for \(list(names, "and"))."
        }

        var rules: [String] = []
        if names.count > 1 {
            if mixes {
                let mixture = names.count == 2 ? "both" : "them"
                rules.append("Automatically detect \(names.joined(separator: ", ")) or a mixture of \(mixture).")
            } else {
                rules.append("Automatically detect \(list(names, "or")).")
            }
        } else {
            rules.append("Keep the text in the language it is written in.")
        }
        if mixes {
            if hasFrench && hasEnglish {
                rules.append("Preserve natural Franglais and code-switching. Expressions such as \"je vais check\", \"faire un call\", \"le feedback\", \"le go-live\" and technical English vocabulary are perfectly acceptable.")
            } else {
                rules.append("Preserve natural code-switching between \(list(names, "and")). Words from one language used inside another, and technical English vocabulary, are perfectly acceptable.")
            }
        }
        rules.append("Preserve the original meaning, intent, information and point of view.")

        let formality = names.compactMap(formalityPair)
        let including = formality.isEmpty ? "" : ", including \(list(formality, "and"))"
        rules.append("Keep the writer's personality, humour, tone and level of formality\(including).")
        rules.append("Preserve natural, informal messaging. Do not turn casual writing into corporate language.")
        rules.append("Keep emojis, slang, contractions and common abbreviations when appropriate.")

        if hasEnglish {
            switch profile.englishVariant {
            case .british: rules.append("Use British English rather than American English.")
            case .american: rules.append("Use American English rather than British English.")
            }
        }
        if profile.avoidDashes {
            rules.append("Never use em dashes (—) or en dashes (–) as punctuation. Use a comma, colon, full stop or parentheses instead.")
        }
        if hasEnglish && profile.englishVariant == .british {
            rules.append(hasFrench
                ? "Never add a comma immediately before \"and\" or \"et\"."
                : "Never add a comma immediately before \"and\".")
        }
        if hasFrench {
            rules.append("Keep the writer's convention for spaces before French punctuation (; : ! ?).")
        }
        rules.append("Preserve names, numbers, URLs, technical terms, product names, formatting, line breaks and paragraph breaks.")
        rules.append("Do not invent information, introduce new ideas or add unnecessary words.")
        rules.append("When the mode instructions below conflict with these rules, follow the mode instructions.")

        let header = intro + " You work on text the user has selected on their Mac."
        return header + "\n\nGlobal rules\n" + rules.map { "- " + $0 }.joined(separator: "\n")
    }

    /// "English (UK)" → "English", "  french " → "French".
    static func baseName(_ raw: String) -> String {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let paren = name.range(of: " (") {
            name = String(name[..<paren.lowerBound])
        }
        guard let first = name.first else { return "" }
        return first.uppercased() + name.dropFirst()
    }

    /// "A", "A and B", "A, B and C".
    static func list(_ items: [String], _ conjunction: String) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        default: return items.dropLast().joined(separator: ", ") + " \(conjunction) " + items[items.count - 1]
        }
    }

    private static func matches(_ name: String, _ candidates: String...) -> Bool {
        candidates.contains { name.compare($0, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    private static func formalityPair(_ name: String) -> String? {
        if matches(name, "French", "Français") { return "tu/vous" }
        if matches(name, "Spanish", "Español") { return "tú/usted" }
        if matches(name, "German", "Deutsch") { return "du/Sie" }
        if matches(name, "Italian", "Italiano") { return "tu/Lei" }
        if matches(name, "Portuguese", "Português") { return "tu/você" }
        if matches(name, "Dutch", "Nederlands") { return "jij/u" }
        return nil
    }
}
