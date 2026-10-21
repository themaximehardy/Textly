import Foundation

/// Turns the small Markdown subset the models write (lists, bold, italic, headings, links, code)
/// into HTML for apps that accept formatted text, and into clean plain text for the others.
enum RichText {
    private enum Block {
        case paragraph([String])
        case heading(level: Int, text: String)
        case item(ordered: Bool, depth: Int, text: String)
    }

    // MARK: Detection

    /// True when the text has structure worth pasting as formatting.
    static func hasFormatting(_ markdown: String) -> Bool {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if listMarker(trimmed) != nil || headingLevel(trimmed) != nil { return true }
        }
        return markdown.range(of: #"\*\*[^*\n]+\*\*"#, options: .regularExpression) != nil
    }

    // MARK: HTML

    static func html(fromMarkdown markdown: String) -> String {
        var html = ""
        var openLists: [Bool] = [] // true = ordered, one entry per nesting level

        func closeLists(to depth: Int) {
            while openLists.count > depth {
                html += openLists.removeLast() ? "</li></ol>" : "</li></ul>"
            }
        }

        for block in blocks(markdown) {
            switch block {
            case .item(let ordered, let depth, let text):
                if openLists.count > depth + 1 {
                    closeLists(to: depth + 1)
                }
                if openLists.count == depth + 1 {
                    if openLists[depth] != ordered {
                        closeLists(to: depth)
                    } else {
                        html += "</li>"
                    }
                }
                while openLists.count < depth + 1 {
                    html += ordered ? "<ol>" : "<ul>"
                    openLists.append(ordered)
                }
                html += "<li>" + inlineHTML(text)
            case .heading(let level, let text):
                closeLists(to: 0)
                let tag = "h\(min(max(level, 1), 4))"
                html += "<\(tag)>\(inlineHTML(text))</\(tag)>"
            case .paragraph(let lines):
                closeLists(to: 0)
                html += "<p>" + lines.map(inlineHTML).joined(separator: "<br>") + "</p>"
            }
        }
        closeLists(to: 0)
        return html
    }

    // MARK: Plain text

    /// "• item", "1. item", no ** or #, links as "text (url)".
    static func plain(fromMarkdown markdown: String) -> String {
        var lines: [String] = []
        var previousWasItem = false
        for block in blocks(markdown) {
            switch block {
            case .item(let ordered, let depth, let text):
                if let last = lines.last, !last.isEmpty, !previousWasItem { lines.append("") }
                let indent = String(repeating: "    ", count: depth)
                let marker = ordered ? (orderedNumber(text) ?? "1.") : "•"
                lines.append(indent + marker + " " + inlinePlain(stripOrderedNumber(text)))
                previousWasItem = true
            case .heading(_, let text):
                if !lines.isEmpty { lines.append("") }
                lines.append(inlinePlain(text))
                previousWasItem = false
            case .paragraph(let paragraph):
                if !lines.isEmpty && (previousWasItem || lines.last != "") { lines.append("") }
                lines.append(contentsOf: paragraph.map(inlinePlain))
                previousWasItem = false
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: Parsing

    private static func blocks(_ markdown: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []

        func flush() {
            if !paragraph.isEmpty { result.append(.paragraph(paragraph)) }
            paragraph = []
        }

        for raw in markdown.components(separatedBy: .newlines) {
            let leading = raw.prefix { $0 == " " || $0 == "\t" }
            let spaces = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty {
                flush()
            } else if let level = headingLevel(line) {
                flush()
                result.append(.heading(level: level, text: String(line.dropFirst(level + 1))))
            } else if let marker = listMarker(line) {
                flush()
                let depth = min(spaces / 2, 3)
                let text = marker.ordered ? line : String(line.dropFirst(marker.length))
                result.append(.item(ordered: marker.ordered, depth: depth, text: text))
            } else {
                paragraph.append(line.hasPrefix("> ") ? String(line.dropFirst(2)) : line)
            }
        }
        flush()
        return result
    }

    /// "- ", "* ", "+ ", "• " or "1. " / "1) ".
    private static func listMarker(_ line: String) -> (ordered: Bool, length: Int)? {
        let bullets: Set<Character> = ["-", "*", "+", "•", "◦", "▪"]
        if let first = line.first, bullets.contains(first), line.count > 1 {
            let second = line[line.index(after: line.startIndex)]
            if second == " " || second == "\t" { return (false, 2) }
        }
        if let range = line.range(of: #"^\d{1,3}[.)] "#, options: .regularExpression) {
            return (true, line.distance(from: line.startIndex, to: range.upperBound))
        }
        return nil
    }

    private static func headingLevel(_ line: String) -> Int? {
        guard let range = line.range(of: #"^#{1,6} "#, options: .regularExpression) else { return nil }
        return line.distance(from: line.startIndex, to: range.upperBound) - 1
    }

    private static func orderedNumber(_ text: String) -> String? {
        guard let range = text.range(of: #"^\d{1,3}[.)]"#, options: .regularExpression) else { return nil }
        return String(text[range]).replacingOccurrences(of: ")", with: ".")
    }

    private static func stripOrderedNumber(_ text: String) -> String {
        text.replacingOccurrences(of: #"^\d{1,3}[.)] "#, with: "", options: .regularExpression)
    }

    // MARK: Inline

    private static func inlineHTML(_ text: String) -> String {
        var s = stripOrderedNumber(text)
        s = s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        s = s.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "<code>$1</code>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#, with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"__([^_\n]+)__"#, with: "<strong>$1</strong>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, with: "<em>$1</em>", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#, with: "<a href=\"$2\">$1</a>", options: .regularExpression)
        return s
    }

    private static func inlinePlain(_ text: String) -> String {
        var s = text
        s = s.replacingOccurrences(of: #"`([^`\n]+)`"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\*\*([^*\n]+)\*\*"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"__([^_\n]+)__"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"(?<![\w*])\*([^*\n]+)\*(?![\w*])"#, with: "$1", options: .regularExpression)
        s = s.replacingOccurrences(of: #"\[([^\]\n]+)\]\((https?://[^)\s]+)\)"#, with: "$1 ($2)", options: .regularExpression)
        return s
    }
}
