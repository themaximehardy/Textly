# App compatibility

Textly reads your selection in one of two ways:

1. **Accessibility**: Textly asks the app for the selected text directly. This is the fastest way and leaves your clipboard alone.
2. **Copy**: if the app doesn't share its selection, Textly presses ⌘C for you, reads the clipboard and puts your clipboard back.

The result is always pasted with ⌘V, and your clipboard is restored afterwards.

Some apps need help:
- **Electron apps** (Slack, VS Code, Notion, Discord, Obsidian, Figma, WhatsApp…) and **Chromium browsers** (Chrome, Edge, Brave, Arc) only share their text once they're asked. Textly asks the first time you use it in that app. The very first try may go through *Copy*; after that, *Accessibility* works.
- **Web editors** (Google Docs, Notion or Gmail in a browser) often say nothing is selected even when text is. In browsers Textly always falls back to *Copy*.
- **Code editors** (VS Code, Cursor, Zed) copy the whole line when nothing is selected. Textly checks first, so it never pastes a duplicate line.

| App | Read | Replace | Status |
|---|---|---|---|
| Notes, TextEdit, Mail, Pages | Accessibility | ⌘V | Works |
| Safari (web pages and forms) | Accessibility, then Copy | ⌘V | Expected to work, testing |
| Chrome, Edge, Brave, Arc | Accessibility (after the first use), then Copy | ⌘V | Expected to work, testing |
| Google Docs (any browser) | Copy | ⌘V | Expected to work, testing |
| Slack | Accessibility (after the first use), then Copy | ⌘V | Expected to work, testing |
| VS Code, Cursor | Accessibility (after the first use), then Copy | ⌘V | Expected to work, testing |
| Notion (app) | Accessibility (after the first use), then Copy | ⌘V | Expected to work, testing |
| Microsoft Word, Outlook | Accessibility, then Copy | ⌘V | Expected to work, testing |
| Terminal, iTerm | Copy | Not possible: terminals don't let you replace text | Use the palette's Copy button |
| Password fields | Never read | | By design |

Something doesn't work? [Open a compatibility issue](https://github.com/themaximehardy/textly/issues/new?template=compatibility.yml). In the meantime, try **right-click › Services › Textly** (for apps built with Apple's own text controls) or select the text, use **Copy** in the palette and paste it yourself.
