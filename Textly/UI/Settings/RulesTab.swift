import SwiftUI
import AppKit

struct RulesTab: View {
    @ObservedObject var store: SettingsStore

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
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
                        store.settings.sharedRules = DefaultPrompts.sharedRules
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
            Text("Fix, improve, summarise and translate text in any app on your Mac.\nOpen source under the MIT licence. Your text goes only to OpenRouter, using your own key.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Link("Source code on GitHub", destination: AppInfo.homepageURL)
                Link("OpenRouter privacy", destination: URL(string: "https://openrouter.ai/privacy")!)
            }
            Button("Show settings file in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([SettingsStore.fileURL])
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
