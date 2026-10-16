import XCTest
@testable import Textly

final class ChangeReviewTests: XCTestCase {
    private let original = "Je vais check sa demain et je te fait un retour."
    private let updated = "Je vais check ça demain et je te fais un retour."

    func testEachEditIsASeparateChange() throws {
        let review = try XCTUnwrap(ChangeReview(original: original, updated: updated))
        XCTAssertEqual(review.changes.count, 2)
        XCTAssertEqual(review.changes[0].removed, "sa")
        XCTAssertEqual(review.changes[0].added, "ça")
        XCTAssertEqual(review.changes[1].removed, "fait")
        XCTAssertEqual(review.changes[1].added, "fais")
    }

    func testAcceptingAllOrNothing() throws {
        let review = try XCTUnwrap(ChangeReview(original: original, updated: updated))
        XCTAssertEqual(review.text(accepting: review.allIDs), updated)
        XCTAssertEqual(review.text(accepting: []), original)
    }

    func testAcceptingSome() throws {
        let review = try XCTUnwrap(ChangeReview(original: original, updated: updated))
        XCTAssertEqual(review.text(accepting: [1]), "Je vais check sa demain et je te fais un retour.")
    }

    func testNeighbouringEditsAreOneChange() throws {
        let review = try XCTUnwrap(ChangeReview(original: "I has went home", updated: "I had gone home"))
        XCTAssertEqual(review.changes.count, 1)
        XCTAssertEqual(review.changes[0].removed, "has went")
        XCTAssertEqual(review.changes[0].added, "had gone")
        XCTAssertEqual(review.text(accepting: []), "I has went home")
        XCTAssertEqual(review.text(accepting: [0]), "I had gone home")
    }

    func testInsertionsAndDeletions() throws {
        let added = try XCTUnwrap(ChangeReview(original: "Hello world", updated: "Hello big world"))
        XCTAssertEqual(added.text(accepting: added.allIDs), "Hello big world")
        XCTAssertEqual(added.text(accepting: []), "Hello world")

        let removed = try XCTUnwrap(ChangeReview(original: "Hello big world", updated: "Hello world"))
        XCTAssertEqual(removed.text(accepting: removed.allIDs), "Hello world")
        XCTAssertEqual(removed.text(accepting: []), "Hello big world")
    }

    func testContextAroundAChange() throws {
        let review = try XCTUnwrap(ChangeReview(original: original, updated: updated))
        XCTAssertEqual(review.changes[0].before, "Je vais check ")
        XCTAssertTrue(review.changes[0].after.hasPrefix(" demain"))
    }

    func testLongContextIsShortened() {
        XCTAssertEqual(ChangeReview.tail("one two three four five six seven eight nine", limit: 12), "… eight nine")
        XCTAssertEqual(ChangeReview.head("one two three four five six", limit: 12), "one two …")
        XCTAssertEqual(ChangeReview.tail("short", limit: 12), "short")
    }

    func testNoChanges() throws {
        let review = try XCTUnwrap(ChangeReview(original: "Same text", updated: "Same text"))
        XCTAssertTrue(review.changes.isEmpty)
        XCTAssertEqual(review.text(accepting: []), "Same text")
    }
}

final class RevertSettingsTests: XCTestCase {
    func testRevertShortcutIsOnForOldSettings() throws {
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(settings.revertHotkey, .defaultRevert)
        XCTAssertEqual(Hotkey.defaultRevert.display, "⌃⌥Z")
    }

    func testClearedShortcutsStayCleared() throws {
        var settings = AppSettings.defaults()
        settings.revertHotkey = nil
        settings.paletteHotkey = nil
        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertNil(decoded.revertHotkey)
        XCTAssertNil(decoded.paletteHotkey)
        XCTAssertEqual(decoded, settings)
    }

    func testReviewModeIsSaved() throws {
        var action = TextAction(name: "Improve", icon: "sparkles", prompt: "p", output: .review)
        action.temperature = 0.4
        let decoded = try JSONDecoder().decode(TextAction.self, from: JSONEncoder().encode(action))
        XCTAssertEqual(decoded.output, .review)
    }
}
