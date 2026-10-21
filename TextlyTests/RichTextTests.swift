import XCTest
@testable import Textly

final class RichTextTests: XCTestCase {
    func testDetectsStructure() {
        XCTAssertTrue(RichText.hasFormatting("Points:\n- one\n- two"))
        XCTAssertTrue(RichText.hasFormatting("1. First\n2. Second"))
        XCTAssertTrue(RichText.hasFormatting("## Title\nText"))
        XCTAssertTrue(RichText.hasFormatting("This is **important**."))
        XCTAssertTrue(RichText.hasFormatting("•\tfrom Mail"))
        XCTAssertFalse(RichText.hasFormatting("Just a sentence, with a - dash and 2.5 numbers."))
        XCTAssertFalse(RichText.hasFormatting("Salut ! Je vais check ça demain."))
    }

    func testBulletListToHTML() {
        XCTAssertEqual(RichText.html(fromMarkdown: "- a\n- **b**"), "<ul><li>a</li><li><strong>b</strong></li></ul>")
    }

    func testNumberedListAndParagraphs() {
        let html = RichText.html(fromMarkdown: "Main point.\n\n1. First\n2. Second\n\nThanks")
        XCTAssertEqual(html, "<p>Main point.</p><ol><li>First</li><li>Second</li></ol><p>Thanks</p>")
    }

    func testNestedList() {
        let html = RichText.html(fromMarkdown: "- a\n  - a1\n  - a2\n- b")
        XCTAssertEqual(html, "<ul><li>a<ul><li>a1</li><li>a2</li></ul></li><li>b</li></ul>")
    }

    func testHeadingsLinksAndEscaping() {
        XCTAssertEqual(RichText.html(fromMarkdown: "## Plan"), "<h2>Plan</h2>")
        XCTAssertEqual(RichText.html(fromMarkdown: "See [docs](https://example.com) & <tags>"),
                       "<p>See <a href=\"https://example.com\">docs</a> &amp; &lt;tags&gt;</p>")
        XCTAssertEqual(RichText.html(fromMarkdown: "an *emphasis* here"), "<p>an <em>emphasis</em> here</p>")
    }

    func testPlainText() {
        let plain = RichText.plain(fromMarkdown: "The **launch** is on Thursday.\n\n- Paul: send the deck\n- Max: book the room\n\n1) Check\n2) Ship")
        XCTAssertEqual(plain, "The launch is on Thursday.\n\n• Paul: send the deck\n• Max: book the room\n1. Check\n2. Ship")
    }

    func testPlainKeepsLinks() {
        XCTAssertEqual(RichText.plain(fromMarkdown: "Read [this](https://a.b/c)"), "Read this (https://a.b/c)")
    }

    @MainActor
    func testPasteContentChoices() {
        let markdown = "Summary:\n\n- one\n- two"
        let rich = PasteContent.make(for: markdown, app: nil, richText: true)
        XCTAssertEqual(rich.plain, "Summary:\n\n• one\n• two")
        XCTAssertEqual(rich.html, "<p>Summary:</p><ul><li>one</li><li>two</li></ul>")

        let plainOnly = PasteContent.make(for: markdown, app: nil, richText: false)
        XCTAssertNil(plainOnly.html)
        XCTAssertEqual(plainOnly.plain, "Summary:\n\n• one\n• two")

        let simple = PasteContent.make(for: "  Hello there.\n", app: nil, richText: true)
        XCTAssertEqual(simple, PasteContent(plain: "  Hello there.\n"))
    }
}

final class PromptUpgradeTests: XCTestCase {
    func testUneditedOldPromptsAreUpgraded() throws {
        var settings = AppSettings.defaults()
        let fixIndex = try XCTUnwrap(settings.actions.firstIndex { $0.builtin == "fix" })
        let improveIndex = try XCTUnwrap(settings.actions.firstIndex { $0.builtin == "improve" })
        let shorterIndex = try XCTUnwrap(settings.actions.firstIndex { $0.name == "Make shorter" })
        settings.actions[fixIndex].prompt = try XCTUnwrap(DefaultPrompts.earlierDefaults["fix"]?.first)
        settings.actions[improveIndex].prompt = "My own improve prompt"
        settings.actions[shorterIndex].prompt = try XCTUnwrap(DefaultPrompts.earlierDefaults["shorten"]?.first) + "\n"

        let migrated = settings.migrated()
        XCTAssertEqual(migrated.actions[fixIndex].prompt, DefaultPrompts.fix)
        XCTAssertEqual(migrated.actions[improveIndex].prompt, "My own improve prompt", "Edited prompts are never touched")
        XCTAssertEqual(migrated.actions[shorterIndex].prompt, DefaultPrompts.shorten)
    }

    func testEveryBuiltinHasItsCurrentPrompt() {
        for key in ["fix", "improve", "summarise", "translate", "shorten"] {
            XCTAssertNotNil(DefaultPrompts.currentPrompt(for: key), key)
            XCTAssertFalse(DefaultPrompts.earlierDefaults[key]?.contains(DefaultPrompts.currentPrompt(for: key)!) ?? true, key)
        }
    }

    func testOutputRulesMentionFormatting() {
        XCTAssertTrue(PromptBuilder.outputRules.contains("Markdown"))
    }
}

final class ActionExamplesTests: XCTestCase {
    func testEveryActionHasSeveralExamples() {
        for action in DefaultPrompts.defaultActions() {
            let examples = ActionExamples.examples(for: action)
            XCTAssertGreaterThanOrEqual(examples.count, 3, action.name)
            XCTAssertEqual(Set(examples.map(\.label)).count, examples.count, "Labels are unique for \(action.name)")
            for example in examples {
                XCTAssertGreaterThan(example.text.count, 120, example.label)
            }
        }
        XCTAssertTrue(ActionExamples.translate.allSatisfy { $0.targetLanguage != nil })
    }
}
