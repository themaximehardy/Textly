import Foundation

/// Language names for the "Translate to…" search. Any free text also works:
/// whatever the user types is passed to the model as the target language.
enum Languages {
    struct Entry: Hashable {
        let name: String
        let native: String
    }

    static let variants: [Entry] = [
        Entry(name: "English (UK)", native: "English (UK)"),
        Entry(name: "English (US)", native: "English (US)"),
        Entry(name: "French (Canada)", native: "Français (Canada)"),
        Entry(name: "Portuguese (Brazil)", native: "Português (Brasil)"),
        Entry(name: "Portuguese (Portugal)", native: "Português (Portugal)"),
        Entry(name: "Spanish (Spain)", native: "Español (España)"),
        Entry(name: "Spanish (Mexico)", native: "Español (México)"),
        Entry(name: "Chinese (Simplified)", native: "简体中文"),
        Entry(name: "Chinese (Traditional)", native: "繁體中文"),
    ]

    static let all: [Entry] = {
        let english = Locale(identifier: "en")
        var seen = Set<String>()
        var list: [Entry] = []
        for code in Locale.LanguageCode.isoLanguageCodes.map(\.identifier) where code.count == 2 {
            guard let name = english.localizedString(forLanguageCode: code), !seen.contains(name) else { continue }
            let nativeLocale = Locale(identifier: code)
            let native = nativeLocale.localizedString(forLanguageCode: code)?.capitalized(with: nativeLocale) ?? name
            seen.insert(name)
            list.append(Entry(name: name, native: native))
        }
        list += variants
        return list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }()

    static let popular: [Entry] = ["Spanish", "German", "Italian", "Portuguese (Brazil)", "Dutch", "Japanese"]
        .compactMap { name in all.first { $0.name == name } }

    static func search(_ query: String, limit: Int = 8) -> [Entry] {
        let q = fold(query)
        guard !q.isEmpty else { return [] }
        let prefixMatches = all.filter { fold($0.name).hasPrefix(q) || fold($0.native).hasPrefix(q) }
        let otherMatches = all.filter { entry in
            !prefixMatches.contains(entry) && (fold(entry.name).contains(q) || fold(entry.native).contains(q))
        }
        return Array((prefixMatches + otherMatches).prefix(limit))
    }

    static func native(for name: String) -> String {
        all.first { $0.name == name }?.native ?? ""
    }

    /// Picks the languages the Mac is set up for, e.g. ["English (UK)", "Français"].
    static func defaultPinned() -> [String] {
        var result: [String] = []
        var codes = Set<String>()
        for identifier in Locale.preferredLanguages {
            let locale = Locale(identifier: identifier)
            guard let code = locale.language.languageCode?.identifier, !codes.contains(code) else { continue }
            codes.insert(code)
            if code == "en" {
                switch locale.region?.identifier {
                case "US": result.append("English (US)")
                case "GB": result.append("English (UK)")
                default: result.append("English")
                }
            } else if let name = locale.localizedString(forLanguageCode: code)?.capitalized(with: locale) {
                result.append(name)
            }
            if result.count == 3 { break }
        }
        if !codes.contains("en") {
            result.insert("English", at: 0)
        }
        return result
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespaces)
    }
}
