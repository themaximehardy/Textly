import AppKit

/// What Textly puts on the clipboard to paste: plain text, plus formatting (HTML and RTF) when there is any.
struct PasteContent: Equatable {
    /// Always present. What plain-text apps get, and what ends up in the text field.
    let plain: String
    /// The same content as HTML (lists, bold, headings), for apps that accept formatted text.
    var html: String? = nil

    /// Decides how a model answer (which may contain Markdown) should be pasted into `app`.
    @MainActor
    static func make(for text: String, app: NSRunningApplication?, richText: Bool) -> PasteContent {
        guard RichText.hasFormatting(text) else { return PasteContent(plain: text) }
        // Code and Markdown editors get the Markdown itself.
        if AppCompatibility.prefersMarkdown(app) { return PasteContent(plain: text) }
        let parts = TextCleanup.split(text)
        let plain = parts.lead + RichText.plain(fromMarkdown: parts.core) + parts.trail
        guard richText else { return PasteContent(plain: plain) }
        return PasteContent(plain: plain, html: RichText.html(fromMarkdown: parts.core))
    }

    /// Puts the content on a pasteboard: RTF for Mac apps (Mail, Notes, Pages), HTML for web apps
    /// (Google Docs, Notion, Slack), plain text for everything else.
    @MainActor
    func write(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        if let html {
            let document = "<meta charset=\"utf-8\">" + html
            if let rtf = Self.rtf(fromHTML: html) {
                pasteboard.setData(rtf, forType: .rtf)
            }
            pasteboard.setString(document, forType: .html)
        }
        pasteboard.setString(plain, forType: .string)
    }

    /// RTF in the system font, so it matches Mac apps instead of falling back to Times.
    @MainActor
    private static func rtf(fromHTML html: String) -> Data? {
        let styled = """
        <meta charset="utf-8"><style>
        body { font-family: -apple-system, "Helvetica Neue", Helvetica, sans-serif; font-size: 13px; }
        p, ul, ol, h1, h2, h3, h4 { margin: 0 0 6px 0; }
        h1, h2, h3, h4 { font-size: 14px; }
        </style>
        """ + html
        guard let data = styled.data(using: .utf8),
              let attributed = try? NSAttributedString(
                data: data,
                options: [
                    .documentType: NSAttributedString.DocumentType.html,
                    .characterEncoding: String.Encoding.utf8.rawValue,
                ],
                documentAttributes: nil
              ) else { return nil }
        return try? attributed.data(
            from: NSRange(location: 0, length: attributed.length),
            documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]
        )
    }
}
