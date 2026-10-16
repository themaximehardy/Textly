# Action packs

An action pack is a `.json` file with a few ready-made actions. Import one in **Settings › Actions**, with **Import…** under the action list. The actions are added to yours; nothing is replaced, and you can edit or delete them afterwards.

| Pack | Actions |
|---|---|
| [email.json](email.json) | Reply: yes · Reply: politely no · More formal · Friendlier · Bullet points |
| [work.json](work.json) | Action items · Status update · Ticket · Explain simply |
| [social.json](social.json) | LinkedIn post · Short post · Catchy title |

To download one, open it above and click the download button (**Download raw file**).

## Share your own

1. In **Settings › Actions**, click **Export…** under the action list › **Export all my actions…** (or just the selected one).
2. Send the file to anyone, or add it here with a pull request so everyone can use it.

Shortcuts are never exported, so importing a pack can't clash with anyone's shortcuts.

## Format

```json
{
  "format": "textly-action-pack",
  "version": 1,
  "name": "Email and messages",
  "description": "Replies and tone changes for email, Slack and Teams.",
  "actions": [
    {
      "name": "Friendlier",
      "icon": "face.smiling",
      "prompt": "MODE: FRIENDLIER\nRewrite the text so it sounds warmer…",
      "output": "replace",
      "temperature": 0.4,
      "useSharedRules": true
    }
  ]
}
```

- `icon` is an [SF Symbol](https://developer.apple.com/sf-symbols/) name.
- `output` is `replace` (swap the selection) or `show` (show the result first).
- `model` is optional. Leave it out to use the default model.
- `temperature` goes from 0 (precise) to 1 (creative).
