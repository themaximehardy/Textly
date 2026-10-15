import AppKit
import ApplicationServices

/// Accessibility permission lets Textly read the selected text and paste the result back.
enum Permissions {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt that adds Textly to the Accessibility list.
    static func requestAccessibility() {
        let key = "AXTrustedCheckOptionPrompt" // value of kAXTrustedCheckOptionPrompt
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}
