import Foundation

/// One suggested change: replace `removed` with `added` (either can be empty).
struct SuggestedChange: Identifiable, Equatable {
    let id: Int
    let removed: String
    let added: String
    /// A few words of the unchanged text around it, to show where it is.
    let before: String
    let after: String
}

/// The result of an action split into separate changes the user can accept or reject one by one.
/// Built from the word diff between the original and the model's answer.
struct ChangeReview: Equatable {
    enum Piece: Equatable {
        case same(String)
        case change(Int)
    }

    private(set) var pieces: [Piece] = []
    private(set) var changes: [SuggestedChange] = []

    init(segments: [DiffSegment]) {
        var pieces: [Piece] = []
        var raw: [(removed: String, added: String)] = []
        var removed = ""
        var added = ""
        var inChange = false
        // Spaces between two edits are folded into one change ("a b" → "c d" is one change, not two).
        var heldSpace: String?

        func appendSame(_ text: String) {
            guard !text.isEmpty else { return }
            if case .same(let previous)? = pieces.last {
                pieces[pieces.count - 1] = .same(previous + text)
            } else {
                pieces.append(.same(text))
            }
        }

        func flush() {
            if inChange {
                pieces.append(.change(raw.count))
                raw.append((removed, added))
                removed = ""
                added = ""
                inChange = false
            }
            if let space = heldSpace {
                appendSame(space)
                heldSpace = nil
            }
        }

        for segment in segments {
            switch segment {
            case .same(let text):
                if inChange, heldSpace == nil, text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    heldSpace = text
                    continue
                }
                flush()
                appendSame(text)
            case .removed(let text):
                if let space = heldSpace {
                    removed += space
                    added += space
                    heldSpace = nil
                }
                inChange = true
                removed += text
            case .added(let text):
                if let space = heldSpace {
                    removed += space
                    added += space
                    heldSpace = nil
                }
                inChange = true
                added += text
            }
        }
        flush()

        self.pieces = pieces
        self.changes = raw.enumerated().map { index, change in
            let position = pieces.firstIndex(of: .change(index)) ?? 0
            var before = ""
            var after = ""
            if position > 0, case .same(let text) = pieces[position - 1] { before = Self.tail(text) }
            if position + 1 < pieces.count, case .same(let text) = pieces[position + 1] { after = Self.head(text) }
            return SuggestedChange(id: index, removed: change.removed, added: change.added, before: before, after: after)
        }
    }

    init?(original: String, updated: String) {
        guard let segments = TextDiff.diff(original, updated) else { return nil }
        self.init(segments: segments)
    }

    var allIDs: Set<Int> { Set(changes.map(\.id)) }

    /// The text with only the accepted changes applied.
    func text(accepting accepted: Set<Int>) -> String {
        pieces.map { piece -> String in
            switch piece {
            case .same(let text):
                return text
            case .change(let id):
                let change = changes[id]
                return accepted.contains(id) ? change.added : change.removed
            }
        }
        .joined()
    }

    /// The last few words of the text before a change ("…je vais check ").
    static func tail(_ text: String, limit: Int = 28) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > limit else { return flat }
        var cut = String(flat.suffix(limit))
        if let space = cut.firstIndex(of: " ") {
            cut = String(cut[space...])
        }
        return "…" + cut
    }

    /// The first few words of the text after a change (" demain et je…").
    static func head(_ text: String, limit: Int = 28) -> String {
        let flat = text.replacingOccurrences(of: "\n", with: " ")
        guard flat.count > limit else { return flat }
        var cut = String(flat.prefix(limit))
        if let space = cut.lastIndex(of: " ") {
            cut = String(cut[..<space])
        }
        return cut + " …"
    }
}
