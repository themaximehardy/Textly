# Changelog

All notable changes to Textly. Versions follow [Semantic Versioning](https://semver.org): 0.x while the app is in early development.

## [0.4.0] - 2026-10-15

### Added
- **Live results**: the answer appears word by word in the palette while it's being written (streaming).
- **Local models**: run Textly with Ollama, LM Studio or any OpenAI-compatible server instead of OpenRouter (Settings › General › AI). Free, private, works offline.
- **Your languages during setup**: pick the languages you write in, British or American English, whether you mix languages, and whether to avoid long dashes. Textly writes its shared rules from this and pins those languages for Translate. Also in Settings › Rules & Glossary.
- **Right-click › Services › Textly**: Open Palette, Fix, Improve, Summarise and Translate from the context menu of apps built with Apple's text controls.
- **Recent results** in the menu bar: the last 20 results, to paste or copy again (result or original). Kept in memory, or after quitting if you turn it on in Settings › General › History.
- **Action packs**: export your actions to a file and import other people's (Settings › Actions › share button). Three packs to start with in [docs/packs](docs/packs): Email and messages, Work, Social.
- **Try it** box under each action in Settings › Actions: test your prompt on sample text before using it, with time, tokens and cost.
- **Update check**: Textly looks for a new version on GitHub once a day and offers to download it. Also in the menu bar › Check for Updates…
- Better support for apps that don't share their selection: Electron apps (Slack, VS Code, Notion…) and Chromium browsers are asked to turn on accessibility, and browsers (Google Docs…) always fall back to copying. See [COMPATIBILITY.md](COMPATIBILITY.md).
- Unit tests (prompts, clean-up, diff, shortcuts, languages, settings migration, streaming parser, packs, history, versions) and a CI workflow that builds and tests every push.
- Open-source basics: contributing guide, security policy, code of conduct, issue and pull request templates.

### Changed
- The built-in Fix and Improve prompts no longer mention French and English specifically (they say "never translate into another language"). Your edited prompts are kept.
- Thinking from local reasoning models (`<think>…</think>`) is removed from results.

## [0.3.0] - 2026-10-15

### Added
- App icon: a bold Fraunces "T" with a blue text cursor on dark ink. Shown in Finder, Launchpad and the Applications folder.
- Logo picker (Settings › General › Appearance) with 5 variants: Ink, Cream, Blue, Italic, Sparkle. Used in Textly's windows, alerts, setup window and About page.
- Downloadable DMG on GitHub Releases, built automatically by GitHub Actions when a version is tagged (`scripts/make-dmg.sh` does the same locally).
- Custom menu bar icons drawn to match the logo: T with cursor (new default), T in a square, italic T, Aa with cursor. The A with cursor, sparkles and wand icons are still available.

### Changed
- Existing installs switch once to the new default logo and menu bar icon. You can change both anytime.
- Removed the menu bar icons nobody liked (text cursor, Aa, pencil, speech bubbles).

## [0.2.0] - 2026-10-15

### Added
- **Usage** tab in Settings: what you've spent today, this week and this month (exact cost reported by OpenRouter), plus a cost estimator per use, day, week and month based on a "uses per day" slider and your real average request size.
- Menu bar icon picker (Settings › General › Appearance). The palette header and About page use the same icon.
- Language suggestions while typing in Settings › General › Translate.
- The default model's price is shown under the model field.

### Changed
- API key row: the key is masked (`sk-or-••••••••1234`) with **Change** and **Test** buttons. Saving a key tests it automatically.
- Narrower model and language fields in Settings.
- Default menu bar icon is now "A with a text cursor" instead of the wand.

### Fixed
- You couldn't type in the "Add a language" field in Settings.

## [0.1.0] - 2026-10-15

### Added
- First version: menu bar app with a palette (⌃⌥T) next to the selected text in any app.
- Built-in actions: Fix, Improve, Summarise, Translate (pinned languages plus any language), and an example "Make shorter" action.
- Custom actions with their own instruction, shortcut, model, creativity and result mode (replace or show first).
- Two palette styles: command list, or preview before replacing with changes highlighted.
- Shared rules and glossary (`wrong → right` corrections).
- OpenRouter with your own key (stored in the Keychain), model browser, fast mode, and an option to avoid providers that train on your text.
- Setup window: API key, Accessibility permission, try it.
