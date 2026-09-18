# QuickClip

A macOS menu-bar app for copying text snippets. Version **0.1.0**. Requires macOS 13+.

## Install

Download `QuickClip-0.1.0.zip` from [Releases](../../releases). Open the app. If macOS blocks it, Control-click → **Open**.

QuickClip lives in the **menu bar**, not the Dock. Look for a clipboard or lock icon.

## Use

1. Click the menu bar icon.
2. If it is locked, choose **Unlock QuickClip…** (Touch ID or your Mac password).
3. Click a snippet to copy it.

**Edit Snippets…** and **Settings…** are in the same menu. While those windows are open, QuickClip appears in the Dock.

- **Normal snippets** are stored as plain text on this Mac.
- **Secure snippets** keep only a title in the config file. The secret is stored in Keychain. After you copy one, it is on the system clipboard until it expires or something else overwrites it.

Config file: `~/Library/Application Support/QuickClip/snippets.json`

## License

[MIT](LICENSE).

## Docs

- [Technical documentation](docs/technical.md) — architecture, security model, JSON schema, building, and releasing
