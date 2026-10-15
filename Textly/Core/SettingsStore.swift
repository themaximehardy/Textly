import Foundation
import Combine

/// Holds the settings (saved as JSON in ~/Library/Application Support/Textly/settings.json)
/// and the API key (saved in the macOS Keychain).
@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var settings: AppSettings {
        didSet { if settings != oldValue { save() } }
    }

    @Published private(set) var apiKey: String

    var hasAPIKey: Bool { !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Textly", isDirectory: true)
    }

    static var fileURL: URL { folderURL.appendingPathComponent("settings.json") }

    private init() {
        apiKey = Keychain.read() ?? ""
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded.migrated()
        } else {
            settings = AppSettings.defaults()
        }
    }

    func setAPIKey(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        Keychain.save(trimmed)
        apiKey = trimmed
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(settings).write(to: Self.fileURL, options: .atomic)
        } catch {
            NSLog("Textly: could not save settings: \(error.localizedDescription)")
        }
    }

    // MARK: Languages

    func noteRecent(_ language: String) {
        guard !settings.pinnedLanguages.contains(language) else { return }
        var recent = settings.recentLanguages.filter { $0.caseInsensitiveCompare(language) != .orderedSame }
        recent.insert(language, at: 0)
        settings.recentLanguages = Array(recent.prefix(3))
    }

    func togglePin(_ language: String) {
        var updated = settings
        if let index = updated.pinnedLanguages.firstIndex(of: language) {
            updated.pinnedLanguages.remove(at: index)
        } else {
            updated.pinnedLanguages.append(language)
            updated.recentLanguages.removeAll { $0 == language }
        }
        settings = updated
    }

    // MARK: Writing profile

    /// True when the shared rules are still generated ones (not edited by hand).
    var sharedRulesAreGenerated: Bool {
        let current = Self.normalise(settings.sharedRules)
        return current == Self.normalise(SharedRulesBuilder.build(settings.writingProfile))
            || current == Self.normalise(DefaultPrompts.sharedRules)
            || current.isEmpty
    }

    /// Saves the profile. Regenerates the shared rules unless they were edited by hand
    /// (then `replaceRules: true` is needed). During setup, the languages are also pinned for Translate.
    func setWritingProfile(_ profile: WritingProfile, replaceRules: Bool = false) {
        var updated = settings
        let wasGenerated = sharedRulesAreGenerated
        let oldLanguages = settings.writingProfile.languages
        updated.writingProfile = profile
        if wasGenerated || replaceRules {
            updated.sharedRules = SharedRulesBuilder.build(profile)
        }
        if !settings.hasCompletedOnboarding || settings.pinnedLanguages == oldLanguages {
            updated.pinnedLanguages = profile.languages
        }
        settings = updated
    }

    private static func normalise(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Actions

    /// Adds the actions from a pack. Returns how many were added.
    @discardableResult
    func importPack(_ pack: ActionPack) -> Int {
        let new = pack.makeActions(existingNames: settings.actions.map(\.name))
        settings.actions.append(contentsOf: new)
        return new.count
    }

    func resetBuiltin(_ id: UUID) {
        guard let index = settings.actions.firstIndex(where: { $0.id == id }),
              let key = settings.actions[index].builtin,
              let builtin = DefaultPrompts.builtin(key) else { return }
        var action = settings.actions[index]
        action.name = builtin.name
        action.icon = builtin.icon
        action.prompt = builtin.prompt
        action.output = builtin.output
        action.temperature = builtin.temperature
        action.useSharedRules = true
        settings.actions[index] = action
    }
}
