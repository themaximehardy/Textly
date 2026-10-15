import AppKit
import Carbon.HIToolbox

enum AppInfo {
    /// Change this to the public GitHub URL once the repo exists.
    /// It is also sent to OpenRouter as the app's referrer, so Textly appears in OpenRouter's app rankings.
    static let homepage = "https://github.com/themaximehardy/textly"
    static var homepageURL: URL { URL(string: homepage) ?? URL(string: "https://github.com")! }
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
    }
}

extension Notification.Name {
    /// Posted by the shortcut recorder (object: Bool) so global shortcuts pause while recording.
    static let textlyRecordingChanged = Notification.Name("TextlyRecordingChanged")
}

// MARK: - Output and palette style

enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case replace
    case show

    var id: String { rawValue }
    var label: String {
        switch self {
        case .replace: return "Replace the selected text"
        case .show: return "Show the result first"
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

    static func defaults() -> AppSettings {
        AppSettings(
            defaultModel: DefaultPrompts.defaultModel,
            sharedRules: DefaultPrompts.sharedRules,
            glossary: "",
            actions: DefaultPrompts.defaultActions(),
            pinnedLanguages: Languages.defaultPinned(),
            recentLanguages: [],
            paletteHotkey: .defaultPalette,
            paletteStyle: .list,
            noTraining: false,
            fastMode: true,
            hasCompletedOnboarding: false,
            menuBarIcon: MenuBarIcons.defaultIcon,
            usesPerDay: 20,
            appLogo: AppLogos.defaultLogo,
            brandingVersion: AppLogos.brandingVersion
        )
    }

    /// Every shortcut in use, keyed by owner. Used to know when to re-register global shortcuts.
    var hotkeyBindings: [String: Hotkey] {
        var bindings: [String: Hotkey] = [:]
        if let paletteHotkey { bindings["palette"] = paletteHotkey }
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
        case paletteHotkey, paletteStyle, noTraining, fastMode, hasCompletedOnboarding
        case menuBarIcon, usesPerDay, appLogo, brandingVersion
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
        paletteStyle = try c.decodeIfPresent(PaletteStyle.self, forKey: .paletteStyle) ?? d.paletteStyle
        noTraining = try c.decodeIfPresent(Bool.self, forKey: .noTraining) ?? d.noTraining
        fastMode = try c.decodeIfPresent(Bool.self, forKey: .fastMode) ?? d.fastMode
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        menuBarIcon = try c.decodeIfPresent(String.self, forKey: .menuBarIcon) ?? d.menuBarIcon
        usesPerDay = try c.decodeIfPresent(Int.self, forKey: .usesPerDay) ?? d.usesPerDay
        appLogo = try c.decodeIfPresent(String.self, forKey: .appLogo) ?? d.appLogo
        brandingVersion = try c.decodeIfPresent(Int.self, forKey: .brandingVersion) ?? 0
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
