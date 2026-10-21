import AppKit
import Carbon.HIToolbox

enum AppInfo {
    /// GitHub "owner/name". Used for the homepage link and the update check.
    static let repository = "themaximehardy/textly"
    /// Also sent to OpenRouter as the app's referrer, so Textly appears in OpenRouter's app rankings.
    static let homepage = "https://github.com/\(repository)"
    static var homepageURL: URL { URL(string: homepage) ?? URL(string: "https://github.com")! }
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
    /// True when the unit tests are running (the app then skips its menu bar and shortcuts).
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
    }
}

extension Notification.Name {
    /// Posted by the shortcut recorder (object: Bool) so global shortcuts pause while recording.
    static let textlyRecordingChanged = Notification.Name("TextlyRecordingChanged")
}

// MARK: - Output and palette style

enum OutputMode: String, Codable, CaseIterable, Identifiable {
    /// Swap the selection straight away.
    case replace
    /// Show the whole result (changes highlighted) and replace on ↵.
    case show
    /// List each suggested change to accept or reject, then apply the ones kept.
    case review

    var id: String { rawValue }
    var label: String {
        switch self {
        case .replace: return "Replace the selected text straight away"
        case .show: return "Show the result first"
        case .review: return "Let me review each change"
        }
    }
}

enum PaletteStyle: String, Codable, CaseIterable, Identifiable {
    case list
    case preview

    var id: String { rawValue }
    var label: String {
        switch self {
        case .list: return "Command list"
        case .preview: return "Preview before replacing"
        }
    }
    var detail: String {
        switch self {
        case .list:
            return "A compact list next to your selection. Actions set to “Replace” swap the text straight away."
        case .preview:
            return "A wider panel that always shows the result, with changes highlighted, before anything is replaced."
        }
    }
}

// MARK: - AI provider and writing profile

enum AIProvider: String, Codable, CaseIterable, Identifiable {
    /// openrouter.ai with your own key: hundreds of models, pay per use.
    case openRouter
    /// An OpenAI-compatible server on your Mac or network (Ollama, LM Studio…). Free and private.
    case local

    var id: String { rawValue }
    var label: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .local: return "Local model"
        }
    }
}

enum EnglishVariant: String, Codable, CaseIterable, Identifiable {
    case british
    case american

    var id: String { rawValue }
    var label: String {
        switch self {
        case .british: return "British (colour, organise)"
        case .american: return "American (color, organize)"
        }
    }
}

/// How the user writes. Chosen during setup; the shared rules are generated from it.
struct WritingProfile: Codable, Equatable {
    var languages: [String]
    var englishVariant: EnglishVariant
    /// Mixes languages in the same message (e.g. Franglais).
    var mixesLanguages: Bool
    /// Never use em dashes or en dashes as punctuation.
    var avoidDashes: Bool

    /// The profile Textly's original rules were written for (French and English, mixed, British English).
    static let classic = WritingProfile(languages: ["French", "English"], englishVariant: .british, mixesLanguages: true, avoidDashes: true)

    /// A first guess from the languages set in macOS (System Settings › General › Language & Region).
    static func suggested(preferred: [String] = Locale.preferredLanguages) -> WritingProfile {
        let english = Locale(identifier: "en_US")
        var names: [String] = []
        var codes = Set<String>()
        var variant: EnglishVariant = .british
        for identifier in preferred {
            let locale = Locale(identifier: identifier)
            guard let code = locale.language.languageCode?.identifier, !codes.contains(code) else { continue }
            codes.insert(code)
            if code == "en", locale.region?.identifier == "US" { variant = .american }
            if let name = english.localizedString(forLanguageCode: code) {
                names.append(name)
            }
            if names.count == 3 { break }
        }
        if names.isEmpty { names = ["English"] }
        return WritingProfile(languages: names, englishVariant: variant, mixesLanguages: names.count > 1, avoidDashes: true)
    }

    var includesEnglish: Bool { languages.contains { SharedRulesBuilder.baseName($0).caseInsensitiveCompare("English") == .orderedSame } }
}

extension WritingProfile {
    enum CodingKeys: String, CodingKey { case languages, englishVariant, mixesLanguages, avoidDashes }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        languages = try c.decodeIfPresent([String].self, forKey: .languages) ?? WritingProfile.classic.languages
        englishVariant = try c.decodeIfPresent(EnglishVariant.self, forKey: .englishVariant) ?? .british
        mixesLanguages = try c.decodeIfPresent(Bool.self, forKey: .mixesLanguages) ?? true
        avoidDashes = try c.decodeIfPresent(Bool.self, forKey: .avoidDashes) ?? true
    }
}

// MARK: - Shortcuts

struct Hotkey: Codable, Equatable, Hashable {
    /// Carbon virtual key code (layout independent).
    var keyCode: UInt32
    /// NSEvent.ModifierFlags raw value (command, option, control, shift only).
    var modifiers: UInt
    /// Human readable key, e.g. "T" or "Space".
    var keyLabel: String

    var modifierFlags: NSEvent.ModifierFlags { NSEvent.ModifierFlags(rawValue: modifiers) }

    var carbonModifiers: UInt32 {
        var result: UInt32 = 0
        let flags = modifierFlags
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }

    var display: String {
        var text = ""
        let flags = modifierFlags
        if flags.contains(.control) { text += "⌃" }
        if flags.contains(.option) { text += "⌥" }
        if flags.contains(.shift) { text += "⇧" }
        if flags.contains(.command) { text += "⌘" }
        return text + keyLabel
    }

    /// ⌃⌥T opens the palette. (⌃⌥Space is taken by macOS for switching keyboard input sources.)
    static let defaultPalette = Hotkey(
        keyCode: UInt32(kVK_ANSI_T),
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "T"
    )

    /// ⌃⌥Z puts back the text Textly last replaced.
    static let defaultRevert = Hotkey(
        keyCode: UInt32(kVK_ANSI_Z),
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "Z"
    )

    /// ⌃⌥F fixes the selection directly, without opening the palette.
    static let defaultFix = Hotkey(
        keyCode: UInt32(kVK_ANSI_F),
        modifiers: NSEvent.ModifierFlags([.control, .option]).rawValue,
        keyLabel: "F"
    )
}

// MARK: - Actions

struct TextAction: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    /// "fix", "improve", "summarise" or "translate" for the built-in actions, nil for your own.
    var builtin: String? = nil
    var name: String
    var icon: String
    var prompt: String
    var output: OutputMode
    /// Empty means "use the default model".
    var model: String = ""
    var temperature: Double = 0.3
    var useSharedRules: Bool = true
    var shortcut: Hotkey? = nil

    var isTranslate: Bool { builtin == "translate" }
}

extension TextAction {
    enum CodingKeys: String, CodingKey {
        case id, builtin, name, icon, prompt, output, model, temperature, useSharedRules, shortcut
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        builtin = try c.decodeIfPresent(String.self, forKey: .builtin)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Action"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? "wand.and.stars"
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        output = try c.decodeIfPresent(OutputMode.self, forKey: .output) ?? .replace
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? ""
        temperature = try c.decodeIfPresent(Double.self, forKey: .temperature) ?? 0.3
        useSharedRules = try c.decodeIfPresent(Bool.self, forKey: .useSharedRules) ?? true
        shortcut = try c.decodeIfPresent(Hotkey.self, forKey: .shortcut)
    }
}

// MARK: - Settings

struct AppSettings: Codable, Equatable {
    var defaultModel: String
    var sharedRules: String
    var glossary: String
    var actions: [TextAction]
    var pinnedLanguages: [String]
    var recentLanguages: [String]
    var paletteHotkey: Hotkey?
    /// Puts the original text back after Textly replaced it.
    var revertHotkey: Hotkey?
    var paletteStyle: PaletteStyle
    var noTraining: Bool
    var fastMode: Bool
    var hasCompletedOnboarding: Bool
    var menuBarIcon: String
    /// Used by the cost estimator in Settings › Usage.
    var usesPerDay: Int
    /// Asset name of the logo shown in Textly's windows and alerts.
    var appLogo: String
    /// Bumped when default branding changes, so existing installs pick up the new icons once.
    var brandingVersion: Int
    /// OpenRouter or a local server.
    var provider: AIProvider
    /// Base URL of the local OpenAI-compatible server, e.g. http://localhost:11434/v1 (Ollama).
    var localBaseURL: String
    /// Model used for every action when the provider is local.
    var localModel: String
    /// Languages and style, used to generate the shared rules.
    var writingProfile: WritingProfile
    /// Keep the recent results after Textly quits (they are always kept while it runs).
    var keepHistory: Bool
    /// Look for a new version on GitHub once a day.
    var checkForUpdates: Bool
    /// Paste lists, bold and headings as real formatting in apps that support it.
    var richText: Bool

    static func defaults() -> AppSettings {
        let profile = WritingProfile.suggested()
        return AppSettings(
            defaultModel: DefaultPrompts.defaultModel,
            sharedRules: SharedRulesBuilder.build(profile),
            glossary: "",
            actions: DefaultPrompts.defaultActions(),
            pinnedLanguages: Languages.defaultPinned(),
            recentLanguages: [],
            paletteHotkey: .defaultPalette,
            revertHotkey: .defaultRevert,
            paletteStyle: .list,
            noTraining: false,
            fastMode: true,
            hasCompletedOnboarding: false,
            menuBarIcon: MenuBarIcons.defaultIcon,
            usesPerDay: 20,
            appLogo: AppLogos.defaultLogo,
            brandingVersion: AppLogos.brandingVersion,
            provider: .openRouter,
            localBaseURL: LocalServer.ollama,
            localModel: "",
            writingProfile: profile,
            keepHistory: false,
            checkForUpdates: true,
            richText: true
        )
    }

    /// The model an action runs with (local mode uses the one local model for everything).
    func model(for action: TextAction) -> String {
        if provider == .local { return localModel.trimmingCharacters(in: .whitespaces) }
        let chosen = action.model.trimmingCharacters(in: .whitespaces)
        return chosen.isEmpty ? defaultModel : chosen
    }

    /// Every shortcut in use, keyed by owner. Used to know when to re-register global shortcuts.
    var hotkeyBindings: [String: Hotkey] {
        var bindings: [String: Hotkey] = [:]
        if let paletteHotkey { bindings["palette"] = paletteHotkey }
        if let revertHotkey { bindings["revert"] = revertHotkey }
        for action in actions {
            if let shortcut = action.shortcut { bindings[action.id.uuidString] = shortcut }
        }
        return bindings
    }

    /// Adds anything new versions expect (e.g. a built-in action that is missing).
    func migrated() -> AppSettings {
        var copy = self
        for builtin in DefaultPrompts.builtins where !copy.actions.contains(where: { $0.builtin == builtin.key }) {
            copy.actions.append(builtin.makeAction())
        }
        if copy.defaultModel.trimmingCharacters(in: .whitespaces).isEmpty {
            copy.defaultModel = DefaultPrompts.defaultModel
        }
        // Prompts never edited by the user follow the new defaults.
        for index in copy.actions.indices {
            let action = copy.actions[index]
            let key = action.builtin ?? "shorten"
            guard let earlier = DefaultPrompts.earlierDefaults[key],
                  let current = DefaultPrompts.currentPrompt(for: key) else { continue }
            let saved = action.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
            if earlier.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == saved }) {
                copy.actions[index].prompt = current
            }
        }
        if copy.brandingVersion < AppLogos.brandingVersion {
            copy.menuBarIcon = MenuBarIcons.defaultIcon
            copy.appLogo = AppLogos.defaultLogo
            copy.brandingVersion = AppLogos.brandingVersion
        }
        return copy
    }
}

extension AppSettings {
    enum CodingKeys: String, CodingKey {
        case defaultModel, sharedRules, glossary, actions, pinnedLanguages, recentLanguages
        case paletteHotkey, revertHotkey, paletteStyle, noTraining, fastMode, hasCompletedOnboarding
        case menuBarIcon, usesPerDay, appLogo, brandingVersion
        case provider, localBaseURL, localModel, writingProfile, keepHistory, checkForUpdates, richText
    }

    init(from decoder: Decoder) throws {
        let d = AppSettings.defaults()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultModel = try c.decodeIfPresent(String.self, forKey: .defaultModel) ?? d.defaultModel
        sharedRules = try c.decodeIfPresent(String.self, forKey: .sharedRules) ?? d.sharedRules
        glossary = try c.decodeIfPresent(String.self, forKey: .glossary) ?? d.glossary
        actions = try c.decodeIfPresent([TextAction].self, forKey: .actions) ?? d.actions
        pinnedLanguages = try c.decodeIfPresent([String].self, forKey: .pinnedLanguages) ?? d.pinnedLanguages
        recentLanguages = try c.decodeIfPresent([String].self, forKey: .recentLanguages) ?? []
        paletteHotkey = try c.decodeIfPresent(Hotkey.self, forKey: .paletteHotkey)
        // Missing before 0.5: turn the revert shortcut on. A saved "null" means the user cleared it.
        revertHotkey = c.contains(.revertHotkey) ? try c.decodeIfPresent(Hotkey.self, forKey: .revertHotkey) : .defaultRevert
        paletteStyle = try c.decodeIfPresent(PaletteStyle.self, forKey: .paletteStyle) ?? d.paletteStyle
        noTraining = try c.decodeIfPresent(Bool.self, forKey: .noTraining) ?? d.noTraining
        fastMode = try c.decodeIfPresent(Bool.self, forKey: .fastMode) ?? d.fastMode
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        menuBarIcon = try c.decodeIfPresent(String.self, forKey: .menuBarIcon) ?? d.menuBarIcon
        usesPerDay = try c.decodeIfPresent(Int.self, forKey: .usesPerDay) ?? d.usesPerDay
        appLogo = try c.decodeIfPresent(String.self, forKey: .appLogo) ?? d.appLogo
        brandingVersion = try c.decodeIfPresent(Int.self, forKey: .brandingVersion) ?? 0
        provider = try c.decodeIfPresent(AIProvider.self, forKey: .provider) ?? .openRouter
        localBaseURL = try c.decodeIfPresent(String.self, forKey: .localBaseURL) ?? LocalServer.ollama
        localModel = try c.decodeIfPresent(String.self, forKey: .localModel) ?? ""
        // Settings saved before 0.4 were written for French and English.
        writingProfile = try c.decodeIfPresent(WritingProfile.self, forKey: .writingProfile) ?? .classic
        keepHistory = try c.decodeIfPresent(Bool.self, forKey: .keepHistory) ?? false
        checkForUpdates = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdates) ?? true
        richText = try c.decodeIfPresent(Bool.self, forKey: .richText) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(defaultModel, forKey: .defaultModel)
        try c.encode(sharedRules, forKey: .sharedRules)
        try c.encode(glossary, forKey: .glossary)
        try c.encode(actions, forKey: .actions)
        try c.encode(pinnedLanguages, forKey: .pinnedLanguages)
        try c.encode(recentLanguages, forKey: .recentLanguages)
        // Written even when empty (null), so a cleared shortcut stays cleared.
        try c.encode(paletteHotkey, forKey: .paletteHotkey)
        try c.encode(revertHotkey, forKey: .revertHotkey)
        try c.encode(paletteStyle, forKey: .paletteStyle)
        try c.encode(noTraining, forKey: .noTraining)
        try c.encode(fastMode, forKey: .fastMode)
        try c.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try c.encode(menuBarIcon, forKey: .menuBarIcon)
        try c.encode(usesPerDay, forKey: .usesPerDay)
        try c.encode(appLogo, forKey: .appLogo)
        try c.encode(brandingVersion, forKey: .brandingVersion)
        try c.encode(provider, forKey: .provider)
        try c.encode(localBaseURL, forKey: .localBaseURL)
        try c.encode(localModel, forKey: .localModel)
        try c.encode(writingProfile, forKey: .writingProfile)
        try c.encode(keepHistory, forKey: .keepHistory)
        try c.encode(checkForUpdates, forKey: .checkForUpdates)
        try c.encode(richText, forKey: .richText)
    }
}

/// Icons offered for the menu bar (Settings › General › Appearance).
/// "asset:Name" is a custom template image in Assets.xcassets; anything else is an SF Symbol.
enum MenuBarIcons {
    static let defaultIcon = "asset:MenuT"
    static let options = [
        "asset:MenuT",
        "asset:MenuTSquare",
        "asset:MenuTItalic",
        "asset:MenuAa",
        "character.cursor.ibeam",
        "sparkles",
        "wand.and.stars",
    ]

    static func assetName(_ name: String) -> String? {
        name.hasPrefix("asset:") ? String(name.dropFirst(6)) : nil
    }

    static func label(_ name: String) -> String {
        switch name {
        case "asset:MenuT": return "T with cursor"
        case "asset:MenuTSquare": return "T in a square"
        case "asset:MenuTItalic": return "Italic T"
        case "asset:MenuAa": return "Aa with cursor"
        case "character.cursor.ibeam": return "A with cursor"
        case "sparkles": return "Sparkles"
        case "wand.and.stars": return "Wand"
        default: return name
        }
    }

    /// Falls back to a safe symbol if a name doesn't exist.
    static func image(_ name: String, description: String = "Textly") -> NSImage? {
        if let asset = assetName(name), let image = NSImage(named: asset) {
            image.isTemplate = true
            return image
        }
        return NSImage(systemSymbolName: name, accessibilityDescription: description)
            ?? NSImage(systemSymbolName: "textformat", accessibilityDescription: description)
    }
}

/// Logo variants (Fraunces Black T). The Finder icon is always the bundled AppIcon (Ink);
/// the chosen logo is used for Textly's windows, alerts and the About page.
enum AppLogos {
    static let defaultLogo = "LogoInk"
    static let brandingVersion = 1
    static let options: [(id: String, label: String)] = [
        ("LogoInk", "Ink"),
        ("LogoCream", "Cream"),
        ("LogoBlue", "Blue"),
        ("LogoItalic", "Italic"),
        ("LogoSparkle", "Sparkle"),
    ]

    @MainActor
    static func apply(_ name: String) {
        NSApp.applicationIconImage = NSImage(named: name) ?? NSImage(named: defaultLogo)
    }
}
