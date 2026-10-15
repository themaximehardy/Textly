import Foundation

/// The prompts Textly ships with. Everything here can be edited in Settings;
/// "Reset to default" brings these versions back.
enum DefaultPrompts {
    static let defaultModel = "google/gemini-3.6-flash"

    // MARK: Shared rules (added to every action that has "Include shared rules" on)

    static let sharedRules = """
    You are an expert bilingual French and English writing assistant. You work on text the user has selected on their Mac.

    Global rules
    - Automatically detect French, English or a mixture of both.
    - Preserve natural Franglais and code-switching. Expressions such as "je vais check", "faire un call", "le feedback", "le go-live" and technical English vocabulary are perfectly acceptable.
    - Preserve the original meaning, intent, information and point of view.
    - Keep the writer's personality, humour, tone and level of formality, including tu/vous.
    - Preserve natural, informal messaging. Do not turn casual writing into corporate language.
    - Keep emojis, slang, contractions and common abbreviations when appropriate.
    - Use British English rather than American English.
    - Never use em dashes (—) or en dashes (–) as punctuation. Use a comma, colon, full stop or parentheses instead.
    - Never add a comma immediately before "and" or "et".
    - Keep the writer's convention for spaces before French punctuation (; : ! ?).
    - Preserve names, numbers, URLs, technical terms, product names, formatting, line breaks and paragraph breaks.
    - Do not invent information, introduce new ideas or add unnecessary words.
    - When the mode instructions below conflict with these rules, follow the mode instructions.
    """

    // MARK: Built-in actions

    static let fix = """
    MODE: CORRECT
    Only correct actual errors in spelling, grammar, accents, agreement, syntax and punctuation. Make the smallest possible changes. Preserve the vocabulary, word order, informal tone and Franglais whenever they are understandable and natural.
    Never translate the text, or any part of it, into another language unless necessary to correct an obvious mistake.
    If the text is already correct and natural, return it unchanged.
    """

    static let improve = """
    MODE: IMPROVE
    Correct errors and improve clarity, readability, fluency and sentence structure. Prefer natural, concise and direct wording. Make the text feel like a better version of something the same person would have written. Never over-polish or substantially change the tone.
    Never translate the text, or any part of it, into another language unless necessary to correct an obvious mistake.
    """

    static let summarise = """
    MODE: SUMMARISE
    Summarise the text in the language it is mostly written in (keep Franglais if the original uses it).
    - Keep what matters: key points, decisions, figures, dates, names and action items (who does what, by when).
    - Scale the length to the input: one or two sentences for a short text, a few short "- " bullet points for a long or multi-topic text. Never exceed about a quarter of the original length.
    - Write plainly and directly. No "This text is about…" or "In summary".
    - Do not add opinions, interpretations or anything that is not in the text.
    """

    static let translate = """
    MODE: TRANSLATE
    Translate the text into {{language}}.
    - Write it the way a native speaker would naturally write it, not word for word. Turn idioms into equivalent idioms.
    - Keep the tone, humour and level of formality. If the target language has formal and informal forms (tu/vous, du/Sie, tú/usted), keep the one the context makes clear; otherwise use the informal form for casual messages and the formal form for professional ones.
    - Keep English work terms that speakers of the target language commonly use as-is (for example call, feedback, deadline, go-live, onboarding in French), but translate everything else and do not add anglicisms.
    - When translating into English, translate everything, including Franglais.
    - Leave parts already in {{language}} as they are.
    - Silently fix obvious typos in the original rather than carrying them over.
    - Keep names, numbers, URLs, glossary terms, emojis and formatting unchanged.
    """

    static let shorten = """
    MODE: SHORTEN
    Make the text shorter and tighter. Keep every key fact, name, number and request, and keep the writer's tone. Remove filler, repetition and anything the reader does not need.
    """

    static let newActionTemplate = """
    MODE: MY ACTION
    Describe what to do with the selected text, in one or two sentences.
    Example: Rewrite the text as a short, polite reply that says yes.
    """

    /// A sentence with mistakes, to try actions on (setup window, Settings › Actions › Try it).
    static func sampleText(for profile: WritingProfile) -> String {
        let french = profile.languages.contains {
            let name = SharedRulesBuilder.baseName($0).lowercased()
            return name.hasPrefix("french") || name.hasPrefix("fran")
        }
        return french
            ? "Salut ! Je vais check sa demain et je te fait un retour avant le go-live, promis."
            : "Hi! I will check it tomorow and get back to you before the launch, i promise their will be no more delay."
    }

    struct Builtin {
        let key: String
        let name: String
        let icon: String
        let prompt: String
        let output: OutputMode
        let temperature: Double
        let shortcut: Hotkey?

        func makeAction() -> TextAction {
            TextAction(builtin: key, name: name, icon: icon, prompt: prompt, output: output, temperature: temperature, shortcut: shortcut)
        }
    }

    static let builtins: [Builtin] = [
        Builtin(key: "fix", name: "Fix", icon: "checkmark", prompt: fix, output: .replace, temperature: 0.1, shortcut: .defaultFix),
        Builtin(key: "improve", name: "Improve", icon: "sparkles", prompt: improve, output: .replace, temperature: 0.4, shortcut: nil),
        Builtin(key: "summarise", name: "Summarise", icon: "text.alignleft", prompt: summarise, output: .show, temperature: 0.3, shortcut: nil),
        Builtin(key: "translate", name: "Translate", icon: "globe", prompt: translate, output: .replace, temperature: 0.2, shortcut: nil),
    ]

    static func builtin(_ key: String) -> Builtin? {
        builtins.first { $0.key == key }
    }

    static func defaultActions() -> [TextAction] {
        var actions = builtins.map { $0.makeAction() }
        actions.append(TextAction(name: "Make shorter", icon: "scissors", prompt: shorten, output: .replace, temperature: 0.3))
        return actions
    }
}
