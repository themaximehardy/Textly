# Textly

<p align="center"><img src="docs/images/hero.png" alt="Textly: write it once, let your Mac fix the rest" width="800"></p>

<p align="center"><a href="https://github.com/themaximehardy/Textly/releases/latest"><b>Download for macOS</b></a> · macOS 14+ · Free and open source</p>

**Fix, improve, summarise and translate any text on your Mac.** Select text in any app, press a shortcut, pick an action. The result replaces your selection, or shows up first so you can check it.

Textly lives in the menu bar, uses [OpenRouter](https://openrouter.ai) with your own API key (so you choose the model and pay only for what you use), and is open source.

- Works in any app where you can select text: Mail, Slack, Notion, Chrome, Word, VS Code…
- Built-in actions: **Fix**, **Improve**, **Summarise**, **Translate** (to any language)
- **Your own actions**: give it a name and an instruction, e.g. "Make shorter" or "Reply politely"
- **Glossary**: brand and product names are always spelled your way, and never translated
- Every prompt is editable. Pick any model on OpenRouter, globally or per action
- Two palette styles: a compact **command list**, or **preview before replacing** with changes highlighted
- No account, no telemetry. Your text goes only to OpenRouter

<p align="center"><img src="docs/images/before-after.png" alt="Fix, translate and shorten the same sentence" width="800"></p>

The default prompts are tuned for people who write in French and English and mix the two (Franglais). Change the shared rules in Settings to match how you write.

## Install

**Requirements:** macOS 14 (Sonoma) or later and an [OpenRouter API key](https://openrouter.ai/keys).

### Download

1. Download the latest **Textly-x.y.z.dmg** from [Releases](https://github.com/themaximehardy/textly/releases/latest).
2. Open it and drag **Textly** to **Applications**.
3. Open Textly. Because it isn't notarised by Apple yet, macOS says it can't verify the app. Click **Done**, then go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**. You only need to do this once.
4. Follow the setup window: paste your API key, then allow Accessibility.

> After installing a new version, macOS may ask for Accessibility again. If Textly stops responding to the shortcut, open System Settings › Privacy & Security › Accessibility, remove Textly with **−** and add it again.

### Build from source

1. Clone this repo and open `Textly.xcodeproj` in Xcode 16 or later.
2. Select the **Textly** target › **Signing & Capabilities** and choose your own **Team** (a free Apple ID "Personal Team" works). This keeps the Accessibility permission from being reset every time you rebuild.
3. Press **Run** (⌘R). Textly appears in the menu bar and opens the setup window.
4. To make a DMG yourself: `scripts/make-dmg.sh` creates `dist/Textly-x.y.z.dmg`.

## First run

1. Paste your OpenRouter API key.
2. Allow Accessibility (System Settings › Privacy & Security › Accessibility). Textly needs it to read your selection and paste the result.
3. Select some text anywhere and press **⌃⌥T**.

## Using it

| | |
|---|---|
| **⌃⌥T** | Open the palette next to your selection |
| **F / I / S / E / R / T…** | Run an action from the palette (each row shows its letter) |
| **↑ ↓ ↵** | Move and run |
| **T** | Translate to any language: type it, press ↵ (⌘P pins it) |
| **⌃⌥F** | Fix the selection directly, no palette |
| **⌘Z** | Undo the change, in the app you were writing in |
| **esc** | Close or cancel |

Every action can have its own shortcut (Settings › Actions). Actions are also in the menu bar icon.

<p align="center"><img src="docs/images/palette.png" alt="The palette next to selected text in an email" width="800"></p>

**Translate to any language.** Pinned languages get their own letter. Press **T** and type any other language, even "Spanish (Mexico)" or "formal German".

<p align="center"><img src="docs/images/translate.png" alt="Translate to any language" width="800"></p>

**Preview before replacing.** Prefer to check first? Switch the palette style in Settings › General: every result appears with the changes highlighted.

<p align="center"><img src="docs/images/preview.png" alt="Preview with changes highlighted" width="800"></p>

<p align="center"><img src="docs/images/menubar.png" alt="Every action is also in the menu bar" width="800"></p>

## Customise

**Settings › Actions**: add, edit, reorder or delete actions. Each action has:
- an instruction (what to do with the text)
- a result mode: replace the selection, or show the result first
- an optional shortcut
- an optional model (otherwise the default model is used)
- a "creativity" (temperature) slider

**Settings › Rules & Glossary**:
- *Shared rules* are added to every action: tone, spelling (e.g. British English), punctuation habits.
- *Glossary*: one term per line. `wrong → right` always corrects a spelling.

<p align="center"><img src="docs/images/settings.png" alt="Settings: edit any action and its instructions" width="800"></p>

**Settings › Usage**: see what you've spent today, this week and this month (exact costs from OpenRouter), and estimate your monthly cost from how often you use it.

<p align="center"><img src="docs/images/usage.png" alt="Usage and cost estimator" width="600"></p>

Settings are stored in `~/Library/Application Support/Textly/settings.json`. The API key is stored in your Keychain.

## How it works

1. The selection is read with the macOS Accessibility API. If an app doesn't expose it, Textly simulates ⌘C and restores your clipboard afterwards.
2. The prompt is built from the shared rules, the action's instruction, your glossary and fixed output rules. The selected text is sent inside `<text>` tags, so it is never treated as instructions.
3. The request goes to OpenRouter's chat completions API.
4. The result is pasted with ⌘V into the app you were in, then your clipboard is restored. Spaces and line breaks around the selection are preserved.

## Privacy

- Text is sent only when you trigger an action, and only to OpenRouter (then to the model provider you chose).
- Turn on *Only use providers that don't store or train on my text* in Settings to restrict routing to providers that don't collect data.
- Textly never reads password fields.
- No analytics, no tracking.

## Roadmap

- Signed and notarised download, Homebrew cask, automatic updates
- Right-click › Services entry
- Import and export actions to share them
- History of recent results
- Local models (Ollama, LM Studio)

## Contributing

Issues and pull requests are welcome. The code is plain Swift and SwiftUI with no dependencies:

```
Textly/
  App/         entry point, menu bar, palette and run logic (AppController)
  Core/        settings, prompts, OpenRouter client, diff, languages
  System/      selection capture and paste, global shortcuts, permissions
  UI/          palette, settings, setup window, shared components
```

## Releasing

1. In Xcode, Textly target › General: bump **Version** (e.g. 0.4.0) and **Build**.
2. Add what changed to `CHANGELOG.md` under the new version.
3. Commit, tag and push:
   ```
   git commit -am "Release 0.4.0"
   git tag v0.4.0
   git push origin main --tags
   ```
4. GitHub Actions builds the DMG on a Mac and publishes the release with the changelog as notes (about 5 minutes).

## Credits

The logo is set in [Fraunces](https://fonts.google.com/specimen/Fraunces) by Undercase Type, used under the SIL Open Font License.

## Changelog

See [CHANGELOG.md](CHANGELOG.md).

## Licence

MIT. See [LICENSE](LICENSE).
