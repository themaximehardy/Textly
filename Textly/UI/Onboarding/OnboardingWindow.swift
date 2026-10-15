import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 580, height: 640),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Textly"
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(
                rootView: OnboardingView(store: SettingsStore.shared, onDone: { [weak self] in self?.finish() })
            )
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        SettingsStore.shared.settings.hasCompletedOnboarding = true
        window?.close()
    }
}

struct OnboardingView: View {
    @ObservedObject var store: SettingsStore
    let onDone: @MainActor () -> Void

    @State private var keyDraft = ""
    @State private var trusted = Permissions.isTrusted
    @State private var sample = "Salut ! Je vais check sa demain et je te fait un retour avant le go-live, promis."

    private var shortcut: String {
        store.settings.paletteHotkey?.display ?? "your shortcut"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 16) {
                Image(store.settings.appLogo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Textly")
                        .font(.largeTitle.bold())
                    Text("Three quick steps, then fix, improve, summarise and translate text in any app.")
                        .foregroundStyle(.secondary)
                }
            }

            StepView(number: 1, title: "Add your OpenRouter API key", done: store.hasAPIKey) {
                HStack {
                    SecureField("API key", text: $keyDraft, prompt: Text("sk-or-…"))
                    Button("Save") { store.setAPIKey(keyDraft) }
                        .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Link("Create a key at openrouter.ai/keys", destination: URL(string: "https://openrouter.ai/keys")!)
                    .font(.callout)
            }

            StepView(number: 2, title: "Allow Accessibility", done: trusted) {
                Text("Textly reads the text you select and pastes the result back. macOS asks for this permission once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Accessibility settings") {
                    Permissions.requestAccessibility()
                    Permissions.openAccessibilitySettings()
                }
                Text("Switch Textly on in the list. If it's already on and this step stays unticked, remove it with − and add it again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StepView(number: 3, title: "Try it", done: false) {
                Text("Select the sentence below, press \(shortcut), then press F to fix it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                TextEditor(text: $sample)
                    .font(.body)
                    .frame(height: 64)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
            }

            HStack {
                Text("Textly lives in the menu bar. You can change its icon in Settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { onDone() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!store.hasAPIKey)
            }
        }
        .padding(28)
        .frame(width: 580)
        .onAppear { keyDraft = store.apiKey }
        .onReceive(Timer.publish(every: 1, on: .main, in: .common).autoconnect()) { _ in
            trusted = Permissions.isTrusted
        }
    }
}

private struct StepView<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(done ? Color.green : Color.accentColor.opacity(0.15))
                    .frame(width: 28, height: 28)
                if done {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Color.white)
                } else {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline)
                content
            }
            Spacer(minLength: 0)
        }
    }
}
