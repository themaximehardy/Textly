import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Textly Settings"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(store: SettingsStore.shared))
            window.setContentSize(NSSize(width: 800, height: 600))
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        TabView {
            GeneralTab(store: store)
                .tabItem { Label("General", systemImage: "gearshape") }
            ActionsTab(store: store)
                .tabItem { Label("Actions", systemImage: "list.bullet.rectangle") }
            RulesTab(store: store)
                .tabItem { Label("Rules & Glossary", systemImage: "text.book.closed") }
            UsageTab(store: store)
                .tabItem { Label("Usage", systemImage: "chart.bar") }
            AboutTab(store: store)
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(12)
        .frame(minWidth: 760, minHeight: 560)
    }
}
