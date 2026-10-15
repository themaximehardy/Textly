# Security

## Reporting a vulnerability

Please don't open a public issue. Use GitHub's private reporting instead: **Security › Report a vulnerability** on this repository. You'll get an answer within a week.

## How Textly handles your data

- **API key**: stored in the macOS Keychain, sent only to OpenRouter.
- **Selected text**: sent only when you run an action, only to the AI you chose (OpenRouter, or the local server you configured). Password fields are never read.
- **Clipboard**: Textly borrows it to copy or paste when an app doesn't expose the selection, then restores it. Temporary entries are marked so clipboard managers ignore them.
- **On disk** (`~/Library/Application Support/Textly/`): settings, a usage log without any text, and, only if you turn it on, the last 20 results.
- **Network**: OpenRouter, your local model server, and GitHub once a day to check for updates (no data is sent). No analytics.
- **Permissions**: Accessibility, to read the selection and paste the result.

## Supported versions

Only the latest release gets fixes.
