import SwiftUI

enum DiffSegment: Equatable {
    case same(String)
    case added(String)
    case removed(String)
}

/// Word-level diff used by the preview to highlight what changed.
enum TextDiff {
    static func diff(_ original: String, _ updated: String) -> [DiffSegment]? {
        let a = tokenize(original)
        let b = tokenize(updated)
        let n = a.count
        let m = b.count
        guard n * m <= 1_000_000 else { return nil }

        var table = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        if n > 0 && m > 0 {
            for i in stride(from: n - 1, through: 0, by: -1) {
                for j in stride(from: m - 1, through: 0, by: -1) {
                    table[i][j] = a[i] == b[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
                }
            }
        }

        var segments: [DiffSegment] = []
        func push(_ segment: DiffSegment) {
            if let last = segments.last {
                switch (last, segment) {
                case let (.same(x), .same(y)): segments[segments.count - 1] = .same(x + y); return
                case let (.added(x), .added(y)): segments[segments.count - 1] = .added(x + y); return
                case let (.removed(x), .removed(y)): segments[segments.count - 1] = .removed(x + y); return
                default: break
                }
            }
            segments.append(segment)
        }

        var i = 0
        var j = 0
        while i < n && j < m {
            if a[i] == b[j] {
                push(.same(a[i])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                push(.removed(a[i])); i += 1
            } else {
                push(.added(b[j])); j += 1
            }
        }
        while i < n { push(.removed(a[i])); i += 1 }
        while j < m { push(.added(b[j])); j += 1 }
        return segments
    }

    /// Only highlight changes when the two texts are still mostly the same.
    static func isWorthShowing(_ segments: [DiffSegment]) -> Bool {
        var same = 0
        var total = 0
        for segment in segments {
            switch segment {
            case .same(let s):
                same += s.count
                total += s.count
            case .added(let s), .removed(let s):
                total += s.count
            }
        }
        return total > 0 && Double(same) / Double(total) >= 0.5
    }

    static func changeCount(_ segments: [DiffSegment]) -> Int {
        var count = 0
        var inChange = false
        for segment in segments {
            switch segment {
            case .same(let s):
                if !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { inChange = false }
            case .added, .removed:
                if !inChange { count += 1; inChange = true }
            }
        }
        return count
    }

    static func plainText(_ segments: [DiffSegment]) -> String {
        segments.map { segment -> String in
            switch segment {
            case .same(let s), .added(let s), .removed(let s): return s
            }
        }.joined()
    }

    static func attributed(_ segments: [DiffSegment]) -> AttributedString {
        var result = AttributedString()
        var previousWasRemoved = false
        for segment in segments {
            if case .added = segment, previousWasRemoved {
                // "feedbak feedback" reads better than "feedbakfeedback".
                result += AttributedString(" ")
            }
            if case .removed = segment { previousWasRemoved = true } else { previousWasRemoved = false }
            switch segment {
            case .same(let s):
                result += AttributedString(s)
            case .removed(let s):
                var piece = AttributedString(s)
                piece[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self] = Text.LineStyle(pattern: .solid)
                piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = .secondary
                result += piece
            case .added(let s):
                var piece = AttributedString(s)
                piece[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] = Color.accentColor.opacity(0.18)
                piece[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = .accentColor
                result += piece
            }
        }
        return result
    }

    private static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsSpace: Bool?
        for character in text {
            let isSpace = character.isWhitespace
            if let previous = currentIsSpace, previous != isSpace {
                tokens.append(current)
                current = ""
            }
            current.append(character)
            currentIsSpace = isSpace
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
