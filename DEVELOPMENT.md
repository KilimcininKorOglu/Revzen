# Development

This document covers building, testing and releasing Revzen. For installation and usage, see the [README](README.md).

## Requirements

- macOS 15 or later
- Xcode or the Swift toolchain with Swift 6
- [SwiftLint](https://github.com/realm/SwiftLint) for `make lint`
- [create-dmg](https://github.com/create-dmg/create-dmg) for `make dmg`
- [minisign](https://jedisct1.github.io/minisign/) for `make release`

## Project structure

The project is a Swift package with two targets:

- `RevzenCore` holds the decision logic without AppKit, Accessibility or ScreenCaptureKit code: click policy, hover state, window order, panel placement, settings, version parsing, update schedule, minisign verification and the release verification rules. Its tests are in `Tests/RevzenCoreTests` and use Swift Testing.
- `Revzen` is the menu bar app. It reads the system state, asks `RevzenCore` for the decision and performs the action. The state machine of the updater (`UpdateService`) takes its network, file and install actions as `UpdateService.Dependencies`, so `Tests/RevzenTests` tests its states with fakes through `@testable import Revzen`.

## Building and testing

| Target | Description |
|---|---|
| `make build` | Builds the release binary. |
| `make test` | Runs the unit tests. |
| `make lint` | Runs SwiftLint in strict mode. Cyclomatic complexity is limited to 10. |
| `make app` | Builds `build/Revzen.app` and signs it. |
| `make run` | Builds, signs and launches the app, replacing a running instance. |
| `make icon` | Regenerates `Resources/AppIcon.icns` from the `dock.rectangle` SF Symbol. |
| `make dmg` | Builds `dist/Revzen.dmg` from the app bundle. |
| `make release` | Builds, signs and notarizes the app and the DMG, then signs the DMG with minisign. |
| `make clean` | Deletes `.build`, `build` and `dist`. |

Run one suite or test with `swift test --filter <name>`, for example `swift test --filter ClickPolicy`.

The binary is universal (arm64 and x86_64).

`make app` signs with the identity in `SIGN_IDENTITY`. A stable identity keeps the Accessibility and Screen Recording grants across rebuilds. Use `make app SIGN_IDENTITY=-` for an ad-hoc signature.

A Homebrew install in `/Applications` and a local build share one bundle ID. Run only one of them at a time.

## Update verification

Before a new version replaces the running app, the updater checks:

1. The SHA-256 of the downloaded DMG against the `digest` that GitHub computed at upload. A missing digest is an error.
2. The minisign signature of the DMG against the release public key (`Resources/minisign.pub`, also compiled into the app as `AppInfo.minisignPublicKey`). Only prehashed `ED` signatures are accepted. The trusted comment must be `Revzen <version>`, so an older signed DMG cannot pass as a newer release.
3. The bundle ID and the version of the app in the DMG.
4. The code signature: Developer ID of team `5U4P8ULV68` and a notarization ticket.

The decisions of these checks, and the rule that only a newer release is offered, are in `ReleaseVerification` in `RevzenCore`, with tests in `ReleaseVerificationTests`. The app target only reads the files, mounts the image and runs `SecStaticCodeCheckValidity`.

Downloads go to `~/Library/Caches/Revzen/updates/<version>`. At launch and before each download, the updater deletes the folders of releases that are not newer than the running app, and folders older than seven days.

## Releasing

1. Set `CFBundleShortVersionString` in `Resources/Info.plist` to the new version and increase `CFBundleVersion` by 1.
2. Add a `## [X.Y.Z] - YYYY-MM-DD` section to `CHANGELOG.md`, then commit.
3. Push a tag with the same version: `git tag -a vX.Y.Z -m vX.Y.Z && git push origin vX.Y.Z`.

The `Release` workflow builds, signs and notarizes the app and the DMG, signs the DMG with minisign, publishes the GitHub release with the tag's `CHANGELOG.md` section as its notes and `Revzen.dmg` and `Revzen.dmg.minisig` as assets, and bumps `Casks/revzen.rb` in [KilimcininKorOglu/homebrew-tap](https://github.com/KilimcininKorOglu/homebrew-tap). The workflow fails when the tag does not match `Info.plist` or when `CHANGELOG.md` has no section for the version.

Sign a DMG only with `make sign-minisign`, because it writes the trusted comment that the updater requires.

The workflow downloads fixed releases of `minisign` and `create-dmg` and checks them against the SHA-256 values in `release.yml`, because both tools run next to the signing secrets. To move to a newer release, verify the minisign archive with its `.minisig` and the upstream public key, then update the URL and the SHA-256 together.

The workflow needs these repository secrets: `APPLE_DEVELOPER_ID_CERT_P12`, `APPLE_DEVELOPER_ID_CERT_PWD`, `APPLE_ID`, `APPLE_TEAM_ID`, `APPLE_APP_SPECIFIC_PWD`, `MINISIGN_KEY`, `MINISIGN_KEY_PWD` and `HOMEBREW_TAP_TOKEN`.

## Private API

Revzen uses three private functions, as AltTab and DockDoor do:

- `_AXUIElementGetWindow` (HIServices) maps an Accessibility window to its window ID, which ScreenCaptureKit needs.
- `_AXUIElementCreateWithRemoteToken` (HIServices) reaches windows on other Spaces.
- `CGSHWCaptureWindowList` (SkyLight) reads the image of a minimized window.

Revzen looks up all three at run time with `dlsym`, so their removal does not stop the app from launching. A macOS update can remove them. The preview then shows the app icon instead of the window image, lists only the current Space, and shows minimized windows only from the images Revzen took earlier. List every new private function here.
