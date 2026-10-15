import XCTest
import AppKit
import Carbon.HIToolbox
@testable import Textly

final class PaletteKeyTests: XCTestCase {
    private func item(_ title: String, key: String? = nil) -> PaletteItem {
        PaletteItem(id: title, kind: .action(UUID()), title: title, icon: "checkmark", keySource: key ?? title, isCustom: false)
    }

    func testFirstFreeLetterWins() {
        let items = PaletteItem.assignKeys([item("Fix"), item("Improve"), item("Summarise"), item("Français"), item("translate")])
        XCTAssertEqual(items.map(\.key), ["f", "i", "s", "r", "t"])
    }

    func testDigitsWhenLettersRunOut() {
        let items = PaletteItem.assignKeys([item("a"), item("a"), item("a")])
        XCTAssertEqual(items.map(\.key), ["a", "1", "2"])
    }
}

final class HotkeyTests: XCTestCase {
    func testDisplayOrderFollowsMacConventions() {
        let hotkey = Hotkey(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: NSEvent.ModifierFlags([.command, .shift, .option, .control]).rawValue,
            keyLabel: "T"
        )
        XCTAssertEqual(hotkey.display, "⌃⌥⇧⌘T")
    }

    func testDefaultShortcuts() {
        XCTAssertEqual(Hotkey.defaultPalette.display, "⌃⌥T")
        XCTAssertEqual(Hotkey.defaultFix.display, "⌃⌥F")
        XCTAssertEqual(Hotkey.defaultPalette.carbonModifiers, UInt32(controlKey | optionKey))
    }
}

final class LanguagesTests: XCTestCase {
    func testSearchMatchesEnglishAndNativeNames() {
        XCTAssertEqual(Languages.search("spa").first?.name, "Spanish")
        XCTAssertTrue(Languages.search("deutsch").contains { $0.name == "German" })
        XCTAssertTrue(Languages.search("francais").contains { $0.name == "French" })
    }

    func testEmptySearch() {
        XCTAssertTrue(Languages.search("   ").isEmpty)
    }

    func testDefaultPinnedAlwaysHasEnglish() {
        XCTAssertTrue(Languages.defaultPinned().contains { $0.hasPrefix("English") })
    }
}
