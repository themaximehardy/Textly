import SwiftUI

/// "Which languages do you write in?" Used in the setup window and in Settings › Rules & Glossary.
struct WritingProfileEditor: View {
    @Binding var profile: WritingProfile
    @State private var newLanguage = ""

    private static let quickPicks = ["English", "French", "Spanish", "German", "Italian", "Portuguese", "Dutch"]

    private var suggestions: [String] {
        let query = newLanguage.trimmingCharacters(in: .whitespaces)
        let names = query.isEmpty
            ? Self.quickPicks
            : Languages.search(query, limit: 5).map(\.name)
        return names.filter { name in
            !profile.languages.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
        }
        .prefix(4)
        .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                ForEach(profile.languages, id: \.self) { language in
                    LanguageChip(name: language, removeHelp: "Remove \(language)") {
                        profile.languages.removeAll { $0 == language }
                    }
                }
                if profile.languages.isEmpty {
                    Text("Add at least one language")
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                TextField("Add a language", text: $newLanguage, prompt: Text("Add a language…"))
                    .labelsHidden()
                    .frame(width: 170)
                    .onSubmit { add(newLanguage) }
                ForEach(suggestions, id: \.self) { name in
                    Button(name) { add(name) }
                        .controlSize(.small)
                }
            }
            if profile.includesEnglish {
                Picker("English spelling", selection: $profile.englishVariant) {
                    ForEach(EnglishVariant.allCases) { variant in
                        Text(variant.label).tag(variant)
                    }
                }
                .fixedSize()
            }
            if profile.languages.count > 1 {
                Toggle("I mix languages in the same message (e.g. Franglais)", isOn: $profile.mixesLanguages)
            }
            Toggle("Never use long dashes (— and –)", isOn: $profile.avoidDashes)
        }
    }

    private func add(_ raw: String) {
        let name = raw.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if !profile.languages.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            profile.languages.append(name)
        }
        newLanguage = ""
    }
}
