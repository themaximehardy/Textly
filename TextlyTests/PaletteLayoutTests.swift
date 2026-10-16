import XCTest
import AppKit
@testable import Textly

/// Measures the real SwiftUI palette, so a panel that is too small (cut-off text) fails here.
final class PaletteLayoutTests: XCTestCase {
    @MainActor
    private func model(style: PaletteStyle) -> PaletteModel {
        let titles = ["Fix", "Improve", "Summarise", "Translate to English (UK)", "Translate to French", "Translate to…", "Make shorter"]
        let items = PaletteItem.assignKeys(titles.map {
            PaletteItem(id: $0, kind: .action(UUID()), title: $0, icon: "checkmark", keySource: $0, isCustom: $0 == "Make shorter")
        })
        let model = PaletteModel()
        model.configure(style: style, items: items, pinned: ["English (UK)", "French"], recent: [],
                        source: "The idea is, with the text I've selected, I need you to make it a better prompt.",
                        brandIcon: MenuBarIcons.defaultIcon)
        return model
    }

    @MainActor
    private func output(_ text: String, original: String) -> RunOutput {
        RunOutput(full: text, core: text, original: original, lead: "", trail: "",
                  completion: CompletionResult(content: text, promptTokens: 0, completionTokens: 0, cost: nil))
    }

    @MainActor
    func testCommandListFitsItsContent() {
        let size = PaletteSizing.idealSize(for: model(style: .list), fallbackHeight: 1)
        XCTAssertEqual(size.width, PaletteMetrics.listWidth)
        // Header (34) + 7 rows of 30 + divider + footer (28).
        XCTAssertGreaterThan(size.height, 34 + 7 * 30 + 28)
        XCTAssertLessThan(size.height, 500)
    }

    @MainActor
    func testPreviewIsWideAndFitsItsContent() {
        let size = PaletteSizing.idealSize(for: model(style: .preview), fallbackHeight: 1)
        XCTAssertEqual(size.width, PaletteMetrics.previewWidth)
        XCTAssertGreaterThanOrEqual(size.width, 640)
        XCTAssertGreaterThan(size.height, 7 * 30)
        XCTAssertLessThan(size.height, 600)
    }

    @MainActor
    func testLongerResultsMakeTheListPanelTaller() {
        let palette = model(style: .list)
        palette.showResult(title: "Improve", output: output("Short.", original: "Shrt."), showDiff: true, review: false)
        let short = PaletteSizing.idealSize(for: palette, fallbackHeight: 1).height
        let long = String(repeating: "A longer answer that wraps over several lines in the palette. ", count: 6)
        palette.showResult(title: "Improve", output: output(long, original: long), showDiff: true, review: false)
        let tall = PaletteSizing.idealSize(for: palette, fallbackHeight: 1).height
        XCTAssertGreaterThan(short, 60)
        XCTAssertGreaterThan(tall, short + 40)
    }

    @MainActor
    func testReviewScreenInPreviewStyle() {
        let palette = model(style: .preview)
        palette.showResult(title: "Fix", output: output("Je vais check ça demain.", original: "Je vais check sa demain."), showDiff: true, review: true)
        XCTAssertEqual(palette.screen, .review)
        XCTAssertEqual(palette.textToInsert, "Je vais check ça demain.")
        palette.setAllChanges(false)
        XCTAssertEqual(palette.textToInsert, "Je vais check sa demain.")
        let size = PaletteSizing.idealSize(for: palette, fallbackHeight: 1)
        XCTAssertEqual(size.width, PaletteMetrics.previewWidth)
        XCTAssertGreaterThan(size.height, 100)
    }
}
