import AppKit

/// Entry point. Textly is a menu bar app (no Dock icon): LSUIElement is set in the build settings.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The unit tests run inside the app: no menu bar icon, shortcuts or windows then.
        guard !AppInfo.isRunningTests else { return }
        MainMenu.install()
        AppController.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        SettingsWindowController.shared.show()
        return false
    }
}
