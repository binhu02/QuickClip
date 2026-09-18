# QuickClip technical documentation

Native Objective-C + AppKit menu-bar app. Apple frameworks only: AppKit, LocalAuthentication, Security, ServiceManagement. No Swift, SwiftUI, or third-party dependencies.

User-facing overview: [README](../README.md).

## Contents

- [Build and run](#build-and-run)
- [Architecture](#architecture)
- [JSON configuration](#json-configuration)
- [Security](#security)
- [Defaults](#defaults)
- [Limitations](#limitations)
- [Releasing](#releasing)

## Build and run

Requires Xcode 15+.

Open `QuickClip.xcodeproj` and run the **QuickClip** scheme, or:

```bash
xcodebuild -project QuickClip.xcodeproj -scheme QuickClip -configuration Debug \
  -derivedDataPath build/DerivedData CODE_SIGN_IDENTITY="-" build

open build/DerivedData/Build/Products/Debug/QuickClip.app
```

JSON round-trip tests (no Keychain, no UI):

```bash
clang -fobjc-arc -fmodules -framework Foundation -framework Security \
  -I QuickClip -o /tmp/qc-json-tests \
  QuickClip/SnippetNode.m QuickClip/QCErrors.m QuickClipTests/JSONTests.m
/tmp/qc-json-tests
```

Keychain, LocalAuthentication, clipboard expiration, and sleep/lock behavior require running the app.

`LSUIElement` is set. The app does not appear in the Dock or Command-Tab at launch. **Edit Snippets** and **Settings** switch it to a foreground app so a Dock icon appears; closing those windows returns it to a menu-bar extra.

If Secure Snippets exist, the app starts locked unless the previous session was left unlocked (`QCRememberedUnlocked` in `NSUserDefaults`). Unlock uses `LAPolicyDeviceOwnerAuthentication`. QuickClip does not implement a custom password dialog.

## Architecture

| Class | Responsibility |
| --- | --- |
| `AppDelegate` | Status item, menus, sleep/lock, copy coordination, Dock policy |
| `SnippetManager` | `snippets.json` load/save, tree mutations, atomic writes |
| `SnippetNode` | Item / secureItem / group / separator model |
| `SecureSnippetStore` | All Keychain CRUD, `SecAccessControl`, Data Protection Keychain |
| `AuthenticationManager` | App unlock, `LAContext`, timeout, lock |
| `SecureAuthenticationManager` | Secure-item auth policy and reusable secure `LAContext` |
| `ClipboardManager` | Normal and secure pasteboard writes, expiration, `changeCount` |
| `SnippetEditorWindowController` | Create, edit, delete, convert snippets |
| `SettingsWindowController` | Preferences UI |
| `LoginItemManager` | `SMAppService` Start at Login |
| `QCPreferences` | `NSUserDefaults` keys and defaults |

The Application Support directory is resolved with `NSFileManager`.

## JSON configuration

Path: `~/Library/Application Support/QuickClip/snippets.json`

On first launch QuickClip creates that file with non-sensitive example snippets (email, phone, website, address). It does not generate example passwords or API keys.

The file is a JSON array of nodes.

Normal snippet:

```json
{
  "type": "item",
  "id": "some-stable-uuid",
  "title": "Email",
  "text": "example@umd.edu"
}
```

Secure snippet (metadata only — there is no `text` field):

```json
{
  "type": "secureItem",
  "id": "550E8400-E29B-41D4-A716-446655440000",
  "title": "OpenAI API Key"
}
```

Group:

```json
{
  "type": "group",
  "title": "Credentials",
  "items": []
}
```

Separator:

```json
{
  "type": "separator"
}
```

Groups nest recursively and become `NSMenu` submenus. Secure snippets work at any depth.

Malformed JSON never crashes the app. QuickClip keeps the last successfully loaded menu when possible and shows a native `NSAlert`.

**Reload Snippets** re-reads this file and rebuilds menu metadata. It does not read Secure Snippet values from Keychain.

**Open Config File** opens `snippets.json` with `NSWorkspace`.

## Security

### Normal vs Secure Snippets

**Normal Snippets** are convenience clipboard items. Their values are plaintext in `snippets.json`, protected only by the app lock and ordinary macOS account/filesystem permissions.

**Secure Snippets** never store the secret in `snippets.json`. Only `type`, `id`, and `title` are written. The UUID is the stable Keychain account; titles can change.

QuickClip refuses to write a `secureItem` that contains `text`. If a hand-edited file includes `text` on a `secureItem`, the value is ignored, never kept in the model, and stripped on the next save.

### Keychain

Secure values are `kSecClassGenericPassword` items.

| Attribute | Value |
| --- | --- |
| Service | `<bundle-id>.secure-snippet` (`com.quickclip.QuickClip.secure-snippet`) |
| Account | snippet UUID |
| Value | UTF-8 secret data |
| Accessibility | `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` |
| Access control | `kSecAccessControlUserPresence` |
| Data Protection Keychain | `kSecUseDataProtectionKeychain = YES` when App ID signing is present; otherwise the login keychain |
| iCloud sync | not enabled |

Signed with an Apple Development or Developer ID team, QuickClip uses the Data Protection Keychain. Ad-hoc (`Sign to Run Locally`) builds get `errSecMissingEntitlement` (-34018) and fall back to the login keychain. App unlock and Secure Snippet authentication still apply.

Do not change the bundle identifier after Secure Snippets exist unless you add a migration. Service name includes the bundle id.

Secrets are device-local. Copying `snippets.json` to another Mac does not copy Keychain values. Missing Keychain items are reported; metadata is not auto-deleted.

### Authentication

**Application lock** uses `LAPolicyDeviceOwnerAuthentication`.

Timeout options (preference only; do not treat `NSUserDefaults` as a substitute for Keychain):

- Every time (locks when the menu closes, unless a QuickClip window is open)
- After 1 / 5 / 15 / 30 minutes, or 1 hour
- Only after app launch

Whether the last session was unlocked is stored as `QCRememberedUnlocked` so the next launch can skip the lock screen. The `LAContext` itself is never persisted.

**Secure Snippet authentication** (reading a Keychain secret):

- Use current QuickClip unlock session (default) — reuse the app `LAContext` via `kSecUseAuthenticationContext`
- Every secure copy — fresh `LAContext`, then invalidate
- After 1 / 5 / 15 minutes — separate in-memory secure session

Timeouts are enforced by QuickClip. Cancelling or failing authentication does not expose the secret. Locking the app invalidates every reusable `LAContext`. A Secure Snippet session never outlives the application lock.

If there are no Secure Snippets, the app does not lock.

### Clipboard

Copying a Secure Snippet writes plaintext to `NSPasteboard`. QuickClip records `changeCount` and can clear the clipboard later if the count is unchanged (15 / 30 / 60 seconds, or never). Sleep and screen lock also clear a still-current secure copy.

If `changeCount` has changed, newer clipboard content is left alone.

Keychain protects the secret at rest. After copy, the value is on the system pasteboard. Auto-clear only shortens exposure. It does not make `NSPasteboard` private.

QuickClip does not invent encryption or store an encryption key in JSON or `NSUserDefaults`.

Secrets are retrieved lazily from Keychain only to copy, reveal/edit, or convert. Menu items carry a non-secret `SnippetNode` (UUID, title, type).

## Defaults

- QuickClip authentication: 15 minutes
- Lock after sleep / screen lock: yes
- Secure Snippet authentication: use current QuickClip unlock session
- Secure clipboard expiration: 30 seconds

## Limitations

- Ad-hoc builds work for development. Start at Login via `SMAppService` generally needs a properly signed app in `/Applications`.
- Secure Snippets do not sync to other Macs.
- QuickClip never automatically deletes Keychain items whose UUIDs are missing from JSON.
- Clipboard auto-clear cannot prevent other apps from reading a copied secret while it is on the pasteboard.
- Immutable Objective-C `NSString` / `NSData` objects are not guaranteed to be zeroized when released.
- Changing the bundle identifier breaks Keychain lookup for existing Secure Snippets.

## Releasing

Version is `0.1.0` (`CFBundleShortVersionString` / `MARKETING_VERSION`).

```bash
git tag v0.1.0
git push origin v0.1.0
```

`.github/workflows/release.yml` runs on `macos-latest`, builds Release, and uploads `QuickClip-0.1.0.zip` to a GitHub Release. You can also run the **Release** workflow from the Actions tab.

The CI build is ad-hoc signed. Users may need Control-click → Open the first time.
