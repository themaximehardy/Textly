import SwiftUI
import AppKit

enum PaletteScreen: Equatable {
    case menu
    case languages
    case working(String)
    case result
    /// Each suggested change listed, to accept or reject one by one.
    case review
    case error(String)
}

struct PaletteItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case action(UUID)
        case translate(UUID, String)
        case translateAny(UUID)
    }

    let id: String
    let kind: Kind
    let title: String
    let icon: String
    /// Text the shortcut letter is picked from (first free letter wins).
    let keySource: String
    let isCustom: Bool
    var key: Character? = nil

    /// Gives every row a single-key shortcut: Fix → F, Improve → I, Summarise → S,
    /// English → E, Français → R (F is taken), Translate to… → T, then 1–9 if letters run out.
    static func assignKeys(_ items: [PaletteItem]) -> [PaletteItem] {
        var used = Set<Character>()
        var result = items
        for index in result.indices {
            let candidates = result[index].keySource.lowercased().filter { $0.isASCII && $0.isLetter }
            if let letter = candidates.first(where: { !used.contains($0) }) {
                result[index].key = letter
                used.insert(letter)
            }
        }
        var digit = 1
        for index in result.indices where result[index].key == nil && digit <= 9 {
            result[index].key = Character(String(digit))
            digit += 1
        }
        return result
    }
}

struct LanguageRow: Identifiable, Equatable {
    let id: String
    let name: String
    let native: String
    let section: String
    let isPinned: Bool
}

/// Everything the palette shows. The AppController owns the logic; this is the view state.
@MainActor
final class PaletteModel: ObservableObject {
    @Published var screen: PaletteScreen = .menu
    @Published var style: PaletteStyle = .list
    @Published var items: [PaletteItem] = []
    @Published var highlighted = 0
    @Published var languageQuery = "" {
        didSet { if languageQuery != oldValue { refreshLanguages(resetHighlight: true) } }
    }
    @Published var languageRows: [LanguageRow] = []
    @Published var languageHighlighted = 0
    @Published var pinned: [String] = [] {
        didSet { refreshLanguages(resetHighlight: false) }
    }
    @Published var recent: [String] = []
    @Published var sourceText = ""
    @Published var brandIcon = MenuBarIcons.defaultIcon
    @Published var resultTitle = ""
    @Published var resultFull = ""
    @Published var resultCore = ""
    @Published var diff: [DiffSegment]? = nil
    @Published var changeCount = 0
    /// The answer so far, while it is being written.
    @Published var streamingText = ""
    /// Review mode: the changes and which ones are kept.
    @Published var review: ChangeReview?
    @Published var accepted: Set<Int> = []
    @Published var reviewHighlighted = 0
    private var resultLead = ""
    private var resultTrail = ""
    private var resultOriginal = ""

    /// The second value is true when the user held ⇧ (review the changes this time).
    var onRun: (@MainActor (PaletteItem.Kind, Bool) -> Void)?
    var onRunLanguage: (@MainActor (String) -> Void)?
    var onReplace: (@MainActor () -> Void)?
    var onCopy: (@MainActor () -> Void)?
    var onRetry: (@MainActor () -> Void)?
    var onClose: (@MainActor () -> Void)?
    var onTogglePin: (@MainActor (String) -> Void)?
    var onOpenSettings: (@MainActor () -> Void)?

    func configure(style: PaletteStyle, items: [PaletteItem], pinned: [String], recent: [String], source: String, brandIcon: String) {
        self.style = style
        self.brandIcon = brandIcon
        self.items = items
        self.highlighted = 0
        self.recent = recent
        self.pinned = pinned
        self.sourceText = source
        self.languageQuery = ""
        self.resultTitle = ""
        self.resultFull = ""
        self.resultCore = ""
        self.diff = nil
        self.changeCount = 0
        self.streamingText = ""
        self.review = nil
        self.accepted = []
        self.screen = .menu
        refreshLanguages(resetHighlight: true)
    }

    // MARK: Menu

    func move(_ delta: Int) {
        guard !items.isEmpty else { return }
        highlighted = (highlighted + delta + items.count) % items.count
    }

    func runHighlighted() {
        guard items.indices.contains(highlighted) else { return }
        run(items[highlighted])
    }

    /// Holding ⇧ (with the letter, ↵ or a click) reviews each change instead of replacing straight away.
    func run(_ item: PaletteItem) {
        if let index = items.firstIndex(of: item) { highlighted = index }
        onRun?(item.kind, NSEvent.modifierFlags.contains(.shift))
    }

    // MARK: Languages

    func showLanguages() {
        languageQuery = ""
        refreshLanguages(resetHighlight: true)
        screen = .languages
    }

    func backToMenu() {
        screen = .menu
    }

    func moveLanguage(_ delta: Int) {
        guard !languageRows.isEmpty else { return }
        languageHighlighted = (languageHighlighted + delta + languageRows.count) % languageRows.count
    }

    func chooseHighlightedLanguage() {
        guard languageRows.indices.contains(languageHighlighted) else { return }
        choose(languageRows[languageHighlighted])
    }

    func choose(_ row: LanguageRow) {
        onRunLanguage?(row.name)
    }

    func togglePinHighlighted() {
        guard languageRows.indices.contains(languageHighlighted) else { return }
        onTogglePin?(languageRows[languageHighlighted].name)
    }

    func refreshLanguages(resetHighlight: Bool) {
        var rows: [LanguageRow] = []
        let query = languageQuery.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            rows += pinned.map { LanguageRow(id: "pinned:\($0)", name: $0, native: Languages.native(for: $0), section: "Pinned", isPinned: true) }
            rows += recent.filter { !pinned.contains($0) }.map {
                LanguageRow(id: "recent:\($0)", name: $0, native: Languages.native(for: $0), section: "Recent", isPinned: false)
            }
            rows += Languages.popular
                .filter { entry in !pinned.contains(entry.name) && !recent.contains(entry.name) }
                .prefix(5)
                .map { LanguageRow(id: "popular:\($0.name)", name: $0.name, native: $0.native, section: "Popular", isPinned: false) }
        } else {
            let matches = Languages.search(query)
            rows += matches.map {
                LanguageRow(id: "match:\($0.name)", name: $0.name, native: $0.native, section: "Matches", isPinned: pinned.contains($0.name))
            }
            if !matches.contains(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) {
                rows.append(LanguageRow(id: "custom:\(query)", name: query, native: "", section: "Use exactly what you typed", isPinned: pinned.contains(query)))
            }
        }
        languageRows = rows
        if resetHighlight {
            languageHighlighted = 0
        } else {
            languageHighlighted = min(languageHighlighted, max(rows.count - 1, 0))
        }
    }

    // MARK: Results

    func startWorking(title: String) {
        streamingText = ""
        screen = .working(title)
    }

    func showPartial(_ text: String) {
        guard case .working = screen, text != streamingText else { return }
        streamingText = text
    }

    func showResult(title: String, output: RunOutput, showDiff: Bool, review wantsReview: Bool) {
        resultTitle = title
        resultFull = output.full
        resultCore = output.core
        resultLead = output.lead
        resultTrail = output.trail
        resultOriginal = output.original
        review = nil
        accepted = []
        if showDiff, let segments = TextDiff.diff(output.original, output.core), TextDiff.isWorthShowing(segments) {
            diff = segments
            changeCount = TextDiff.changeCount(segments)
            if wantsReview {
                let changes = ChangeReview(segments: segments)
                if !changes.changes.isEmpty {
                    review = changes
                    accepted = changes.allIDs
                    reviewHighlighted = 0
                    screen = .review
                    return
                }
            }
        } else {
            diff = nil
            changeCount = 0
        }
        screen = .result
    }

    // MARK: Review

    /// What ↵ / Replace inserts: the whole result, or only the accepted changes when reviewing.
    var textToInsert: String {
        guard screen == .review, let review else { return resultFull }
        return resultLead + review.text(accepting: accepted) + resultTrail
    }

    /// What Copy copies (without the surrounding spaces).
    var textToCopy: String {
        guard screen == .review, let review else { return resultCore }
        return review.text(accepting: accepted)
    }

    func toggleChange(_ id: Int) {
        if accepted.contains(id) {
            accepted.remove(id)
        } else {
            accepted.insert(id)
        }
        if let index = review?.changes.firstIndex(where: { $0.id == id }) { reviewHighlighted = index }
    }

    func toggleHighlightedChange() {
        guard let changes = review?.changes, changes.indices.contains(reviewHighlighted) else { return }
        toggleChange(changes[reviewHighlighted].id)
    }

    func moveReview(_ delta: Int) {
        guard let count = review?.changes.count, count > 0 else { return }
        reviewHighlighted = (reviewHighlighted + delta + count) % count
    }

    func setAllChanges(_ on: Bool) {
        accepted = on ? (review?.allIDs ?? []) : []
    }

    func showError(_ message: String) {
        screen = .error(message)
    }
}
