import XCTest
@testable import Textly

final class PromptBuilderTests: XCTestCase {
    private func action(prompt: String, sharedRules: Bool = true) -> TextAction {
        TextAction(name: "Test", icon: "checkmark", prompt: prompt, output: .replace, useSharedRules: sharedRules)
    }

    func testSystemPromptHasRulesInstructionsGlossaryAndOutputRulesInOrder() {
        var settings = AppSettings.defaults()
        settings.sharedRules = "SHARED"
        settings.glossary = "Textly\nmac book -> MacBook"
        let prompt = PromptBuilder.messages(for: action(prompt: "DO IT"), language: nil, text: "hello", settings: settings)

        let shared = prompt.system.range(of: "SHARED")
        let instructions = prompt.system.range(of: "DO IT")
        let glossary = prompt.system.range(of: "Glossary")
        let output = prompt.system.range(of: "Output rules")
        XCTAssertNotNil(shared)
        XCTAssertNotNil(instructions)
        XCTAssertNotNil(glossary)
        XCTAssertNotNil(output)
        XCTAssertLessThan(shared!.lowerBound, instructions!.lowerBound)
        XCTAssertLessThan(instructions!.lowerBound, glossary!.lowerBound)
        XCTAssertLessThan(glossary!.lowerBound, output!.lowerBound)
        XCTAssertTrue(prompt.system.contains("- mac book → MacBook"))
        XCTAssertEqual(prompt.user, "<text>\nhello\n</text>")
    }

    func testSharedRulesCanBeLeftOut() {
        var settings = AppSettings.defaults()
        settings.sharedRules = "SHARED"
        let prompt = PromptBuilder.messages(for: action(prompt: "DO IT", sharedRules: false), language: nil, text: "x", settings: settings)
        XCTAssertFalse(prompt.system.contains("SHARED"))
    }

    func testLanguagePlaceholderIsReplaced() {
        let prompt = PromptBuilder.messages(for: action(prompt: "Translate into {{language}}."), language: "Spanish", text: "x", settings: .defaults())
        XCTAssertTrue(prompt.system.contains("Translate into Spanish."))
        XCTAssertFalse(prompt.system.contains("{{language}}"))
    }

    func testEmptyGlossaryAddsNothing() {
        XCTAssertNil(PromptBuilder.glossaryBlock("  \n \n"))
    }
}

final class TextCleanupTests: XCTestCase {
    func testSplitKeepsSurroundingWhitespace() {
        let parts = TextCleanup.split("\n  Hello world \n")
        XCTAssertEqual(parts.lead, "\n  ")
        XCTAssertEqual(parts.core, "Hello world")
        XCTAssertEqual(parts.trail, " \n")
    }

    func testSplitOfOnlyWhitespace() {
        let parts = TextCleanup.split("   ")
        XCTAssertEqual(parts.core, "")
        XCTAssertEqual(parts.lead + parts.core + parts.trail, "   ")
    }

    func testCleanRemovesTextTags() {
        XCTAssertEqual(TextCleanup.clean("<text>\nBonjour\n</text>", original: "Bonjour"), "Bonjour")
    }

    func testCleanRemovesCodeFenceUnlessOriginalHadOne() {
        XCTAssertEqual(TextCleanup.clean("```\nHello\n```", original: "Helo"), "Hello")
        XCTAssertEqual(TextCleanup.clean("```\nHello\n```", original: "```\nHelo\n```"), "```\nHello\n```")
    }

    func testCleanRemovesWrappingQuotes() {
        XCTAssertEqual(TextCleanup.clean("\"Hello\"", original: "Helo"), "Hello")
        XCTAssertEqual(TextCleanup.clean("« Salut »", original: "Salu"), "Salut")
        XCTAssertEqual(TextCleanup.clean("\"Hello\"", original: "\"Helo\""), "\"Hello\"")
    }

    func testPartialHidesTheOpeningTagWhileItArrives() {
        XCTAssertEqual(TextCleanup.partial("<te"), "")
        XCTAssertEqual(TextCleanup.partial("<text>\nBon"), "Bon")
        XCTAssertEqual(TextCleanup.partial("<text>Bonjour</text>"), "Bonjour")
        XCTAssertEqual(TextCleanup.partial("Hello wor"), "Hello wor")
    }
}

final class TextDiffTests: XCTestCase {
    func testIdenticalTextsHaveNoChanges() throws {
        let segments = try XCTUnwrap(TextDiff.diff("Hello world", "Hello world"))
        XCTAssertEqual(TextDiff.changeCount(segments), 0)
        XCTAssertEqual(segments, [.same("Hello world")])
    }

    func testSingleWordFix() throws {
        let segments = try XCTUnwrap(TextDiff.diff("Je vais check sa demain", "Je vais check ça demain"))
        XCTAssertEqual(TextDiff.changeCount(segments), 1)
        XCTAssertTrue(segments.contains(.removed("sa")))
        XCTAssertTrue(segments.contains(.added("ça")))
        XCTAssertTrue(TextDiff.isWorthShowing(segments))
    }

    func testCompletelyDifferentTextIsNotWorthShowing() throws {
        let segments = try XCTUnwrap(TextDiff.diff("one two three", "alpha beta gamma delta"))
        XCTAssertFalse(TextDiff.isWorthShowing(segments))
    }
}

final class ThinkingTests: XCTestCase {
    func testThinkingIsRemovedFromLocalReasoningModels() {
        XCTAssertEqual(TextCleanup.clean("<think>\nLet me fix it.\n</think>\n\nBonjour", original: "Bonjur"), "Bonjour")
        XCTAssertEqual(TextCleanup.partial("<think>Still thinking"), "")
        XCTAssertEqual(TextCleanup.partial("<think>Done</think>\nBon"), "Bon")
    }
}
