import SwiftUI
import AppKit

struct RulesTab: View {
    @ObservedObject var store: SettingsStore

    private var profile: Binding<WritingProfile> {
        Binding(
            get: { store.settings.writingProfile },
            set: { store.setWritingProfile($0) }
        )
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        WritingProfileEditor(profile: profile)
                        if !store.sharedRulesAreGenerated {
                            HStack {
                                Text("You've edited the rules, so they aren't rewritten automatically.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Rewrite for these languages") {
                                    store.setWritingProfile(store.settings.writingProfile, replaceRules: true)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Text("Languages you write in")
                        .font(.headline)
                }
                .padding(.bottom, 4)

                Text("Shared rules")
                    .font(.headline)
                Text("Added to every action that has “Include shared rules” on. This is where your voice and style live.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $store.settings.sharedRules)
                    .font(.system(.body, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                HStack {
                    Spacer()
                    Button("Reset to default") {
                        store.settings.sharedRules = SharedRulesBuilder.build(store.settings.writingProfile)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Glossary")
                    .font(.headline)
                Text("One term per line: brand names, product names, people. Write “wrong → right” to always correct a spelling.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                TextEditor(text: $store.settings.glossary)
                    .font(.system(.body, design: .monospaced))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                Text("Example:\nTextly\nOpenRouter\nmac book → MacBook")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(width: 260)
        }
        .padding(8)
    }
}

struct AboutTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        VStack(spacing: 12) {
            Image(store.settings.appLogo)
                .resizable()
                .interpolation(.high)
                .frame(width: 112, height: 112)
            Text("Textly")
                .font(.title.bold())
            Text("Version \(AppInfo.version)")
                .foregroundStyle(.secondary)
            Text("Fix, improve, summarise and translate text in any app on your Mac.\nOpen source under the MIT licence. Your text goes only to the AI you choose: OpenRouter with your own key, or a model on your Mac.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Source code on GitHub", destination: AppInfo.homepageURL)
                Link("OpenRouter privacy", destination: URL(string: "https://openrouter.ai/privacy")!)
            }
            HStack(spacing: 12) {
                Button("Check for Updates…") {
                    Task { await UpdateChecker.shared.check(userInitiated: true) }
                }
                Button("Show settings file in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.fileURL])
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
