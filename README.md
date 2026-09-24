# Revzen

Revzen brings Windows-style taskbar behavior to the macOS Dock. It runs as a menu bar app.

## Features

- **Click to minimize.** Click the icon of the active app to minimize its focused window. Click it again to restore the window minimized last. Modified clicks (Command, Option, Control, Shift) keep their Dock meaning.
- **Window previews.** Hover a Dock icon to see a preview of each window of the app, with the window title under it. Click a preview to bring that window to the front, restoring it when minimized.
- **Close from the preview.** Close a window with the "x" in the corner of its preview, or with a middle click on the preview. The app may still ask to save changes.
- **Minimized windows.** macOS cannot capture a minimized window, so Revzen keeps the last image of each window. Images are taken during previews, before a Dock click minimizes a window, when an app stops being active, and every 10 seconds for the active app. The images live in memory only, so a window minimized before Revzen started shows the app icon.
- **Scroll to switch.** Scroll over a Dock icon to bring the app's windows to the front one after another, in the order they were created.
- **Spaces.** Optionally show windows from other Spaces in the preview.
- **Settings.** Preview delay, excluded apps, other Spaces and launch at login. Revzen does nothing for an excluded app: the Dock handles its clicks, and it gets no preview or scroll switching.
- **Appearance.** The preview panel and the Settings window use system materials and colors, so they follow the light and dark appearance.

## Requirements

- macOS 15 or later
- Accessibility permission: Dock clicks, scroll handling and window control
- Screen Recording permission: window previews

Revzen asks for both permissions on first launch. You can also grant them from the menu bar menu or the Settings window.

Launch at login is on by default. The first launch registers Revzen as a login item once. If you turn it off, it stays off.

## Building

The project is a Swift package. The Makefile builds a signed app bundle.

| Target       | Description                                                                      |
|--------------|----------------------------------------------------------------------------------|
| `make build` | Builds the release binary.                                                       |
| `make test`  | Runs the unit tests.                                                             |
| `make lint`  | Runs SwiftLint in strict mode. Cyclomatic complexity is limited to 10.            |
| `make app`   | Builds `build/Revzen.app` and signs it.                                          |
| `make run`   | Builds, signs and launches the app, replacing a running instance.                |
| `make clean` | Deletes `.build` and `build`.                                                    |

`make app` signs with the identity in `SIGN_IDENTITY`. A stable identity keeps the Accessibility and Screen Recording grants across rebuilds. Use `make app SIGN_IDENTITY=-` for an ad-hoc signature.

## Private API

Revzen uses two private HIServices functions, as AltTab and DockDoor do:

- `_AXUIElementGetWindow` maps an Accessibility window to its window ID, which ScreenCaptureKit needs.
- `_AXUIElementCreateWithRemoteToken` reaches windows on other Spaces.

A macOS update can remove them. The preview then shows the app icon instead of the window image and lists only the current Space. The app cannot ship in the Mac App Store, because the Accessibility permission rules out the App Sandbox.

## License

MIT. See [LICENSE](LICENSE).
