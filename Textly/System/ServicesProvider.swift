import AppKit

/// Right-click › Services › Textly… (and the app menu › Services).
/// The entries are declared in Config/Info.plist (NSServices). macOS hands over the selected text,
/// and the result is pasted back like any other Textly action.
@MainActor
final class ServicesProvider: NSObject {
    static let shared = ServicesProvider()

    func install() {
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()
    }

    /// "Textly: Open Palette"
    @objc func openPalette(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let selection = selection(from: pboard, error: error) else { return }
        Task { await AppController.shared.openPalette(preset: selection) }
    }

    /// "Textly: Fix", "Textly: Improve", "Textly: Summarise". userData is the built-in action's key.
    @objc func runAction(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let selection = selection(from: pboard, error: error) else { return }
        let key = userData ?? "fix"
        guard let action = SettingsStore.shared.settings.actions.first(where: { $0.builtin == key }) else {
            error.pointee = "Textly couldn't find this action." as NSString
            return
        }
        Task { await AppController.shared.runDirect(action, language: nil, preset: selection) }
    }

    /// "Textly: Translate…" opens the language list.
    @objc func translate(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let selection = selection(from: pboard, error: error) else { return }
        Task { await AppController.shared.openPalette(startInLanguages: true, preset: selection) }
    }

    private func selection(from pboard: NSPasteboard, error: AutoreleasingUnsafeMutablePointer<NSString?>) -> CapturedSelection? {
        guard let text = pboard.string(forType: .string),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error.pointee = "Select some text first." as NSString
            return nil
        }
        return SelectionService.selection(withText: text)
    }
}
