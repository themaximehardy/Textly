import XCTest
@testable import Textly

final class SharedRulesBuilderTests: XCTestCase {
    func testClassicProfileGivesTheOriginalRules() {
        XCTAssertEqual(SharedRulesBuilder.build(.classic), DefaultPrompts.sharedRules)
    }

    func testSingleLanguageAmerican() {
        let rules = SharedRulesBuilder.build(WritingProfile(languages: ["English (US)"], englishVariant: .american, mixesLanguages: true, avoidDashes: false))
        XCTAssertTrue(rules.hasPrefix("You are an expert English writing assistant."))
        XCTAssertTrue(rules.contains("Use American English"))
        XCTAssertFalse(rules.contains("Franglais"))
        XCTAssertFalse(rules.contains("code-switching"), "One language can't be mixed")
        XCTAssertFalse(rules.contains("em dashes"))
        XCTAssertFalse(rules.contains("comma immediately before"))
    }

    func testSpanishAndGermanMixed() {
        let rules = SharedRulesBuilder.build(WritingProfile(languages: ["Spanish", "German", "English"], englishVariant: .british, mixesLanguages: true, avoidDashes: true))
        XCTAssertTrue(rules.contains("multilingual writing assistant for Spanish, German and English"))
        XCTAssertTrue(rules.contains("Automatically detect Spanish, German, English or a mixture of them."))
        XCTAssertTrue(rules.contains("code-switching between Spanish, German and English"))
        XCTAssertTrue(rules.contains("including tú/usted and du/Sie"))
        XCTAssertTrue(rules.contains("Never add a comma immediately before \"and\"."))
        XCTAssertFalse(rules.contains("French punctuation"))
    }

    func testNotMixing() {
        let rules = SharedRulesBuilder.build(WritingProfile(languages: ["French", "English"], englishVariant: .british, mixesLanguages: false, avoidDashes: true))
        XCTAssertTrue(rules.contains("Automatically detect French or English."))
        XCTAssertFalse(rules.contains("Franglais"))
    }

    func testDuplicatesAndBlanksAreIgnored() {
        let rules = SharedRulesBuilder.build(WritingProfile(languages: ["english", " ", "English (UK)"], englishVariant: .british, mixesLanguages: true, avoidDashes: true))
        XCTAssertTrue(rules.hasPrefix("You are an expert English writing assistant."))
    }

    func testLists() {
        XCTAssertEqual(SharedRulesBuilder.list(["A"], "and"), "A")
        XCTAssertEqual(SharedRulesBuilder.list(["A", "B"], "or"), "A or B")
        XCTAssertEqual(SharedRulesBuilder.list(["A", "B", "C"], "and"), "A, B and C")
    }

    func testSuggestedProfileFromSystemLanguages() {
        let profile = WritingProfile.suggested(preferred: ["fr-FR", "en-US", "fr-CA"])
        XCTAssertEqual(profile.languages, ["French", "English"])
        XCTAssertEqual(profile.englishVariant, .american)
        XCTAssertTrue(profile.mixesLanguages)
        XCTAssertEqual(WritingProfile.suggested(preferred: []).languages, ["English"])
    }
}

final class AppSettingsTests: XCTestCase {
    func testOldSettingsFileStillLoads() throws {
        // A settings file from 0.3 (no provider, writing profile or history keys).
        let json = """
        {"defaultModel": "openai/gpt-5-mini", "glossary": "Textly", "paletteStyle": "preview", "brandingVersion": 1}
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8)).migrated()
        XCTAssertEqual(settings.defaultModel, "openai/gpt-5-mini")
        XCTAssertEqual(settings.glossary, "Textly")
        XCTAssertEqual(settings.paletteStyle, .preview)
        XCTAssertEqual(settings.provider, .openRouter)
        XCTAssertEqual(settings.localBaseURL, LocalServer.ollama)
        XCTAssertEqual(settings.writingProfile, .classic)
        XCTAssertFalse(settings.keepHistory)
        XCTAssertTrue(settings.checkForUpdates)
        for key in ["fix", "improve", "summarise", "translate"] {
            XCTAssertTrue(settings.actions.contains { $0.builtin == key }, "Missing built-in \(key)")
        }
    }

    func testRoundTrip() throws {
        var settings = AppSettings.defaults()
        settings.provider = .local
        settings.localModel = "llama3.2"
        settings.writingProfile = WritingProfile(languages: ["German"], englishVariant: .american, mixesLanguages: false, avoidDashes: false)
        let data = try JSONEncoder().encode(settings)
        XCTAssertEqual(try JSONDecoder().decode(AppSettings.self, from: data), settings)
    }

    func testMigrationResetsEmptyModelAndOldBranding() {
        var settings = AppSettings.defaults()
        settings.defaultModel = "  "
        settings.brandingVersion = 0
        settings.menuBarIcon = "sparkles"
        let migrated = settings.migrated()
        XCTAssertEqual(migrated.defaultModel, DefaultPrompts.defaultModel)
        XCTAssertEqual(migrated.menuBarIcon, MenuBarIcons.defaultIcon)
    }

    func testModelForAction() {
        var settings = AppSettings.defaults()
        var action = TextAction(name: "A", icon: "checkmark", prompt: "p", output: .replace)
        XCTAssertEqual(settings.model(for: action), settings.defaultModel)
        action.model = "anthropic/claude-haiku"
        XCTAssertEqual(settings.model(for: action), "anthropic/claude-haiku")
        settings.provider = .local
        settings.localModel = "qwen3:8b"
        XCTAssertEqual(settings.model(for: action), "qwen3:8b", "Local mode uses the local model for every action")
    }
}

final class ActionPackTests: XCTestCase {
    func testExportThenImport() throws {
        let original = TextAction(name: "Friendlier", icon: "face.smiling", prompt: "Be nice", output: .show, model: "x/y", temperature: 0.4, useSharedRules: false, shortcut: .defaultFix)
        let data = try ActionPack(name: "Mine", actions: [original]).encoded()
        let pack = try ActionPack.decode(data)
        let imported = pack.makeActions(existingNames: [])
        XCTAssertEqual(imported.count, 1)
        let action = try XCTUnwrap(imported.first)
        XCTAssertEqual(action.name, "Friendlier")
        XCTAssertEqual(action.icon, "face.smiling")
        XCTAssertEqual(action.prompt, "Be nice")
        XCTAssertEqual(action.output, .show)
        XCTAssertEqual(action.model, "x/y")
        XCTAssertEqual(action.temperature, 0.4)
        XCTAssertFalse(action.useSharedRules)
        XCTAssertNil(action.shortcut, "Shortcuts are never shared")
        XCTAssertNil(action.builtin)
        XCTAssertNotEqual(action.id, original.id)
    }

    func testNameClashesGetANumber() throws {
        let pack = ActionPack(name: "P", actions: [
            TextAction(name: "Fix", icon: "checkmark", prompt: "p", output: .replace),
            TextAction(name: "Fix", icon: "checkmark", prompt: "p", output: .replace),
        ])
        let names = pack.makeActions(existingNames: ["fix"]).map(\.name)
        XCTAssertEqual(names, ["Fix 2", "Fix 3"])
    }

    func testRejectsOtherFiles() {
        XCTAssertThrowsError(try ActionPack.decode(Data("{\"hello\": 1}".utf8)))
        XCTAssertThrowsError(try ActionPack.decode(Data("{\"format\": \"other\", \"actions\": []}".utf8)))
        XCTAssertThrowsError(try ActionPack.decode(Data("{\"format\": \"textly-action-pack\", \"version\": 1, \"actions\": []}".utf8)))
        XCTAssertThrowsError(try ActionPack.decode(Data("{\"format\": \"textly-action-pack\", \"version\": 9, \"actions\": [{\"name\": \"a\", \"icon\": \"b\", \"prompt\": \"c\", \"output\": \"show\"}]}".utf8)))
    }

    func testBundledPacksAreValid() throws {
        // docs/packs/*.json, relative to this file.
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("docs/packs")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
        XCTAssertFalse(files.isEmpty)
        for file in files {
            let pack = try ActionPack.decode(Data(contentsOf: file))
            XCTAssertEqual(pack.makeActions(existingNames: []).count, pack.actions.count, file.lastPathComponent)
        }
    }
}

final class HistoryStoreTests: XCTestCase {
    private func temporaryFile() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("textly-history-\(UUID().uuidString).json")
    }

    @MainActor
    func testKeepsTheLastTwentyNewestFirst() {
        let fileURL = temporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = HistoryStore(fileURL: fileURL)
        for index in 1...25 {
            store.add(title: "Fix", original: "o\(index)", result: "r\(index)", appName: nil)
        }
        XCTAssertEqual(store.entries.count, HistoryStore.limit)
        XCTAssertEqual(store.entries.first?.result, "r25")
        XCTAssertEqual(store.entries.last?.result, "r6")
    }

    @MainActor
    func testOnlySavedWhenPersistent() {
        let fileURL = temporaryFile()
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = HistoryStore(fileURL: fileURL)
        store.add(title: "Fix", original: "a", result: "b", appName: "Mail")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))

        store.setPersistent(true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(HistoryStore(fileURL: fileURL).entries.first?.appName, "Mail")

        store.setPersistent(false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }
}
