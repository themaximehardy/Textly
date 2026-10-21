# Signing and notarising Textly

With an Apple Developer account, the release workflow signs Textly with your **Developer ID** and has Apple **notarise** it. Then:

- macOS opens the downloaded app without any warning (no more "Open Anyway").
- The Accessibility permission survives updates (macOS recognises each new version as the same app).
- The in-app updater only installs a download signed by the same developer, so nobody can slip in a fake update.

It takes about 15 minutes, once. You need a Mac with Xcode, and you must be the account's **Account Holder** (true for an individual account).

## 1. Create the Developer ID certificate

1. Open **Xcode › Settings › Accounts**, select your Apple ID, then your team, and click **Manage Certificates…**
2. Click **+** at the bottom left › **Developer ID Application**.
3. Open **Keychain Access** › **login** › **My Certificates**. You'll see *Developer ID Application: Your Name (TEAMID)* with a key under it.
4. Right-click it › **Export…** › format **Personal Information Exchange (.p12)** › save to the Desktop as `DeveloperID.p12` › choose a strong password (keep it in your password manager).
5. In Terminal, copy it as text:
   ```
   base64 -i ~/Desktop/DeveloperID.p12 | pbcopy
   ```

## 2. Create a notarisation key

1. Go to [App Store Connect](https://appstoreconnect.apple.com) › **Users and Access** › **Integrations** › **App Store Connect API** › **Team Keys**. (The first time, click **Request Access** and accept.)
2. Click **+** › name it `Textly notarisation`, access **Developer** › **Generate**.
3. **Download API Key** (a file named `AuthKey_XXXXXXXXXX.p8`, downloadable only once).
4. Note the **Key ID** (in the list) and the **Issuer ID** (above the list).

## 3. Add five secrets to GitHub

On GitHub: the Textly repository › **Settings** › **Secrets and variables** › **Actions** › **New repository secret**, five times:

| Name | Value |
|---|---|
| `MACOS_CERTIFICATE` | the text copied in step 1.5 (paste with ⌘V) |
| `MACOS_CERTIFICATE_PASSWORD` | the .p12 password from step 1.4 |
| `NOTARY_API_KEY` | the whole content of the .p8 file, including the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines (`pbcopy < ~/Downloads/AuthKey_XXXXXXXXXX.p8`) |
| `NOTARY_KEY_ID` | the Key ID |
| `NOTARY_ISSUER_ID` | the Issuer ID |

Secrets are encrypted: nobody can read them back, not even you, and they're never shown in logs.

## 4. Release

Run **Actions › Release › Run workflow** with the version tag (for example `v0.6.0`), or push a tag. The log shows `Signing as: Developer ID Application: …`, then the notarisation (1 to 5 minutes). The DMG on the release page is now signed and notarised.

To check a download on your Mac:
```
spctl --assess --type execute --verbose /Applications/Textly.app
```
It should say `accepted` and `source=Notarized Developer ID`.

## 5. Clean up

Delete `DeveloperID.p12` and the `.p8` file from your Desktop and Downloads once they're in GitHub (keep a copy in your password manager: Apple lets you create only a few Developer ID certificates).

## Building on your own Mac

In Xcode, select the **Textly** target › **Signing & Capabilities** › **Team**: your developer team. Builds from Xcode are for testing; the signed, notarised DMG comes from GitHub Actions.

## Without the secrets

If the secrets aren't set (for example in a fork), the workflow still builds a DMG, signed ad hoc. It works, but macOS shows the "Open Anyway" warning and asks for Accessibility again after each update.
