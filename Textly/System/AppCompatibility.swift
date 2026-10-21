import AppKit
import ApplicationServices

/// Workarounds for apps that don't let other apps read the selected text directly.
///
/// - Electron apps (Slack, VS Code, Notion, Discord, Obsidian…) and Chromium browsers only build
///   their accessibility tree when asked. Textly asks once per app launch with "AXManualAccessibility".
///   The first use may still go through the clipboard while the app catches up.
/// - Web pages (Google Docs, Notion in a browser…) often report an empty selection even when text
///   is selected, so Textly always falls back to copying in browsers.
/// See COMPATIBILITY.md for the apps that have been tested.
@MainActor
enum AppCompatibility {
    private static var prepared = Set<pid_t>()

    static let browserBundleIDs: Set<String> = [
        "com.apple.Safari", "com.apple.SafariTechnologyPreview",
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
        "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "app.zen-browser.zen",
    ]

    static let chromiumBundleIDs: Set<String> = [
        "com.google.Chrome", "com.google.Chrome.beta", "com.google.Chrome.canary",
        "org.chromium.Chromium", "com.microsoft.edgemac", "com.brave.Browser",
        "company.thebrowser.Browser", "com.vivaldi.Vivaldi", "com.operasoftware.Opera",
    ]

    /// Code editors, terminals and Markdown editors: results are pasted as Markdown text, not formatting.
    static let markdownBundleIDs: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf",
        "dev.zed.Zed", "com.apple.dt.Xcode", "com.sublimetext.4", "com.sublimetext.3", "com.panic.Nova", "com.barebones.bbedit",
        "com.apple.Terminal", "com.googlecode.iterm2", "dev.warp.Warp-Stable", "com.mitchellh.ghostty",
        "md.obsidian", "abnerworks.Typora", "net.shinyfrog.bear", "com.uranusjr.macdown",
    ]

    static func prefersMarkdown(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return markdownBundleIDs.contains(id) || id.hasPrefix("com.jetbrains.")
    }

    static func isBrowser(_ app: NSRunningApplication?) -> Bool {
        guard let id = app?.bundleIdentifier else { return false }
        return browserBundleIDs.contains(id)
    }

    static func isElectron(_ app: NSRunningApplication?) -> Bool {
        guard let url = app?.bundleURL else { return false }
        let framework = url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework")
        return FileManager.default.fileExists(atPath: framework.path)
    }

    /// Asks Electron apps and Chromium browsers to expose their text to accessibility. Cheap, once per process.
    static func prepare(_ app: NSRunningApplication?) {
        guard let app, !prepared.contains(app.processIdentifier) else { return }
        prepared.insert(app.processIdentifier)
        let isChromium = app.bundleIdentifier.map { chromiumBundleIDs.contains($0) } ?? false
        guard isChromium || isElectron(app) else { return }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.3)
        AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }

    /// Whether to believe an app that says nothing is selected. If we don't, Textly tries copying instead.
    /// Editors like VS Code copy the whole line when nothing is selected, so for them we must believe it.
    static func trustsEmptySelection(_ app: NSRunningApplication?) -> Bool {
        !isBrowser(app)
    }
}
