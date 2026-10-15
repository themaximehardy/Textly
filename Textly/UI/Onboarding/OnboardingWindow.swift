import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController {
    static let shared = OnboardingWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 760),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "Welcome to Textly"
            window.isReleasedWhenClosed = false
            let hosting = NSHostingController(
                rootView: OnboardingView(store: SettingsStore.shared, onDone: { [weak self] in self?.finish() })
            )
            window.contentViewController = hosting
            let size = hosting.view.fittingSize
            if size.width > 0, size.height > 0 { window.setContentSize(size) }
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
    @State private var sample = DefaultPrompts.sampleText(for: SettingsStore.shared.settings.writingProfile)

    private var profile: Binding<WritingProfile> {
        Binding(
            get: { store.settings.writingProfile },
            set: { store.setWritingProfile($0) }
        )
    }

    private var aiReady: Bool {
        switch store.settings.provider {
        case .openRouter: return store.hasAPIKey
        case .local: return !store.settings.localModel.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var shortcut: String {
        store.settings.paletteHotkey?.display ?? "your shortcut"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 16) {
                Image(store.settings.appLogo)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 72, height: 72)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Welcome to Textly")
                        .font(.largeTitle.bold())
                    Text("Four quick steps, then fix, improve, summarise and translate text in any app.")
                        .foregroundStyle(.secondary)
                }
            }

            if store.settings.provider == .openRouter {
                StepView(number: 1, title: "Add your OpenRouter API key", done: store.hasAPIKey) {
                    HStack {
                        SecureField("API key", text: $keyDraft, prompt: Text("sk-or-…"))
                        Button("Save") { store.setAPIKey(keyDraft) }
                            .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    HStack(spacing: 14) {
                        Link("Create a key at openrouter.ai/keys", destination: URL(string: "https://openrouter.ai/keys")!)
                        Button("Use a local model instead (Ollama, LM Studio)") {
                            store.settings.provider = .local
                        }
                        .buttonStyle(.link)
                    }
                    .font(.callout)
                }
            } else {
                StepView(number: 1, title: "Choose your local model", done: aiReady) {
                    LocalModelSettings(store: store, compact: true)
                    Button("Use OpenRouter instead") {
                        store.settings.provider = .openRouter
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                }
            }

            StepView(number: 2, title: "Which languages do you write in?", done: !store.settings.writingProfile.languages.isEmpty) {
                WritingProfileEditor(profile: profile)
                Text("Textly writes its rules from this (Settings › Rules & Glossary) and pins these languages for Translate.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            StepView(number: 3, title: "Allow Accessibility", done: trusted) {
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

            StepView(number: 4, title: "Try it", done: false) {
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
                    .disabled(!aiReady)
            }
        }
        .padding(28)
        .frame(width: 620)
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
