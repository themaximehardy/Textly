# Contributing to Textly

Thanks for helping. Bug reports, app compatibility reports, action packs and pull requests are all welcome.

## Report a bug

Open an [issue](https://github.com/themaximehardy/textly/issues/new/choose) with:
- your macOS version and Textly version (Settings › About),
- the app you were in (e.g. Slack, Google Docs in Chrome),
- what you did, what you expected and what happened.

Never paste your API key or private text in an issue.

## Report an app that doesn't work

If Textly can't read or replace text in an app, open a *compatibility* issue. The list of tested apps is in [COMPATIBILITY.md](COMPATIBILITY.md).

## Share actions

Export your actions (Settings › Actions › share button › Export) and add the file to [`docs/packs/`](docs/packs) with a pull request. Add a line for it to `docs/packs/README.md`.

## Change the code

**Setup**
1. Install Xcode 16 or later (macOS 14 or later).
2. Clone the repo and open `Textly.xcodeproj`.
3. Textly target › Signing & Capabilities: pick your own Team (a free Apple ID works).
4. Run with ⌘R. Run the tests with ⌘U.

**Layout**
```
Textly/
  App/         entry point, menu bar, palette and run logic (AppController)
  Core/        settings, prompts, AI client (OpenRouter + local), diff, history, packs, updates
  System/      selection capture and paste, shortcuts, Services, app compatibility
  UI/          palette, settings, setup window, shared components
TextlyTests/   unit tests (no network, no UI)
Config/        Info.plist additions (Services, local networking)
```

**Guidelines**
- Keep it simple and native: Swift, SwiftUI and AppKit, no third-party dependencies.
- Add or update a test when you change logic in `Core/`.
- User-facing text is in British English, short and plain. No em dashes.
- Add a line to `CHANGELOG.md` under *Unreleased*.
- One pull request per change. CI builds the app and runs the tests on every push.

## Release (maintainers)

See *Releasing* in the [README](README.md#releasing).

By contributing you agree that your work is released under the [MIT licence](LICENSE) and that you follow the [code of conduct](CODE_OF_CONDUCT.md).
