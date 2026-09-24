<p align="center">
  <img src="docs/logo.png" width="128" height="128" alt="Revzen logo">
</p>

# Revzen

Revzen brings Windows-style taskbar behavior to the macOS Dock. It runs as a menu bar app.

Developer: Kerem Gök ([x.com/KogOglan](https://x.com/KogOglan))

## Install

```
brew install --cask KilimcininKorOglu/tap/revzen
```

Or download `Revzen.dmg` from the [latest release](https://github.com/KilimcininKorOglu/Revzen/releases/latest) and drag Revzen to Applications.

## Features

- **Click to minimize.** Click the icon of the active app to minimize its focused window. Click it again to restore that window. Modified clicks (Command, Option, Control, Shift) keep their Dock meaning.
- **Window previews.** Hover a Dock icon to see a preview of each window of the app, with the window title under it. The previews are in alphabetical order of the titles. Click a preview to bring that window to the front, restoring it when minimized.
- **Close from the preview.** Close a window with the "x" in the corner of its preview, or with a middle click on the preview. The app may still ask to save changes.
- **Minimized windows.** ScreenCaptureKit cannot capture a minimized window, so Revzen reads its last image from the window server through a private SkyLight call. When that call fails, the preview shows the last image Revzen took of the window: during previews, before a Dock click minimizes a window, when an app stops being active, and every 10 seconds for the active app. Without either image, the tile shows the app icon.
- **Scroll to switch.** Scroll over a Dock icon to bring the app's windows to the front one after another, in the order they were created.
- **Spaces.** Optionally show windows from other Spaces in the preview.
- **Updates.** Revzen checks GitHub for a new release once a day, and "Check for Updates…" in the menu checks at once. A new release opens a window with its notes, and Revzen installs it in place (see [Updates](#updates)).
- **Settings.** Preview delay, excluded apps, other Spaces, launch at login, the automatic update check and debug logging. Revzen does nothing for an excluded app: the Dock handles its clicks, and it gets no preview or scroll switching.
- **Appearance.** The preview panel and the Settings window use system materials and colors, so they follow the light and dark appearance.

## Requirements

- macOS 15 or later
- Accessibility permission: Dock clicks, scroll handling and window control
- Screen Recording permission: window previews

Revzen asks for both permissions on first launch. You can also grant them from the menu bar menu or the Settings window.

Launch at login is on by default. The first launch registers Revzen as a login item once. If you turn it off, it stays off.

## Updates

Before the new version replaces the running app, Revzen checks:

1. The SHA-256 of the downloaded DMG against the digest GitHub computed at upload.
2. The minisign signature of the DMG against the release public key (`Resources/minisign.pub`, also compiled into the app). The trusted comment must be `Revzen <version>`, so an older signed DMG cannot pass as a newer release.
3. The bundle ID and the version of the app in the DMG.
4. The code signature: Developer ID of team `5U4P8ULV68` and a notarization ticket.

A failed check stops the update and shows the reason. When Revzen is in a folder that the user cannot write, macOS asks for an administrator password. Downloads stay in `~/Library/Caches/Revzen/updates` and are deleted after seven days.

## Diagnostics

Settings > Diagnostics > Debug logging writes every Dock click, hover, scroll, preview, window and update event to `~/Library/Logs/Revzen/revzen.log`. It is off by default. When the file grows past 5 MB, Revzen renames it to `revzen.log.1` and starts a new file, so at most two files remain.

## Building

The project is a Swift package (Swift 6). The Makefile builds a signed app bundle. `make lint` needs SwiftLint. `make dmg` needs `create-dmg`, and `make release` also needs `minisign`.

| Target       | Description                                                                      |
|--------------|----------------------------------------------------------------------------------|
| `make build` | Builds the release binary.                                                       |
| `make test`  | Runs the unit tests.                                                             |
| `make lint`  | Runs SwiftLint in strict mode. Cyclomatic complexity is limited to 10.            |
| `make app`   | Builds `build/Revzen.app` and signs it.                                          |
| `make run`   | Builds, signs and launches the app, replacing a running instance.                |
| `make icon`  | Regenerates `Resources/AppIcon.icns` from the `dock.rectangle` SF Symbol.        |
| `make dmg`   | Builds `dist/Revzen.dmg` from the app bundle.                                    |
| `make release` | Builds, signs and notarizes the app and the DMG, then signs the DMG with minisign. |
| `make clean` | Deletes `.build`, `build` and `dist`.                                            |

`make app` signs with the identity in `SIGN_IDENTITY`. A stable identity keeps the Accessibility and Screen Recording grants across rebuilds. Use `make app SIGN_IDENTITY=-` for an ad-hoc signature.

The binary is universal (arm64 and x86_64).

## Releasing

1. Set `CFBundleShortVersionString` in `Resources/Info.plist` to the new version and increase `CFBundleVersion` by 1.
2. Add a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md`, then commit.
3. Push a tag with the same version: `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.

The `Release` workflow builds, signs and notarizes the app and the DMG, signs the DMG with minisign, publishes the GitHub release with the tag's `CHANGELOG.md` section as its notes and `Revzen.dmg` and `Revzen.dmg.minisig` as assets, and bumps `Casks/revzen.rb` in [KilimcininKorOglu/homebrew-tap](https://github.com/KilimcininKorOglu/homebrew-tap). The workflow fails when the tag does not match `Info.plist` or when `CHANGELOG.md` has no section for the version. It needs these repository secrets: `APPLE_DEVELOPER_ID_CERT_P12`, `APPLE_DEVELOPER_ID_CERT_PWD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PWD`, `MINISIGN_KEY`, `MINISIGN_KEY_PWD` and `HOMEBREW_TAP_TOKEN`.

## Private API

Revzen uses three private functions, as AltTab and DockDoor do:

- `_AXUIElementGetWindow` (HIServices) maps an Accessibility window to its window ID, which ScreenCaptureKit needs.
- `_AXUIElementCreateWithRemoteToken` (HIServices) reaches windows on other Spaces.
- `CGSHWCaptureWindowList` (SkyLight) reads the image of a minimized window. Revzen looks it up at run time.

A macOS update can remove them. The preview then shows the app icon instead of the window image, lists only the current Space, and shows minimized windows only from the images Revzen took earlier. The app cannot ship in the Mac App Store, because the Accessibility permission rules out the App Sandbox.

## License

MIT. See [LICENSE](LICENSE).
