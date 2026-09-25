# Changelog

All notable changes to Revzen are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.3.1] - 2026-09-25

### Changed
- The README shows a screenshot of the window previews.

### Fixed
- Moving the pointer from an app's icon to the icon of an app that is not running, or is excluded, now closes the preview of the first app.

## [1.3.0] - 2026-09-25

### Fixed
- Moving the pointer over a window preview no longer reaches the app under the preview, so that app no longer reacts to a pointer it cannot see.

## [1.2.2] - 2026-09-25

### Added
- The update window shows a progress bar with the size received and the total size while it downloads a release, then shows that it verifies the download.

## [1.2.1] - 2026-09-25

### Fixed
- The release notes in the update window no longer start with an empty line and end with two.

## [1.2.0] - 2026-09-25

### Changed
- The repository has VS Code launch targets for debug and release builds.

### Fixed
- An app that runs more than once, such as two Chrome instances, gets the right windows on each of its Dock icons. Before, every icon showed the windows of one copy, and click and scroll acted on that copy. Quitting one copy no longer stops Revzen from handling the others.

## [1.1.0] - 2026-09-24

### Added
- After a Dock click minimizes a window, switching to another window of the app makes the next click minimize that window. The first window stays minimized.
- Settings > Diagnostics has a Delete Log button, and it says that the debug log records the window titles and names of other apps.

### Changed
- Debug logging is no longer saved and turns off when Revzen quits, so no other app can turn it on through the stored settings.
- The debug log file and its folder can be read only by your user account.
- The release workflow runs only for a version tag, keeps no repository token in the git config, and installs fixed, checksum-verified releases of minisign and create-dmg. CI uses a fixed, checksum-verified SwiftLint 0.65.1.
- The update verification rules and the update window states have unit tests, and the tests no longer leave files in `~/Library/Preferences`.

### Fixed
- An update that has to ask for the administrator password keeps the installed app until the new copy is complete. Before, a failed copy could leave no working Revzen.
- A download or install result shows even when the update window was closed. Closing the window on an offered update no longer stops the daily check for the rest of the session.
- A manual check during a background check shows its result instead of an endless spinner.
- Cancelling the administrator password prompt keeps the update ready to install instead of showing a raw error.
- A GitHub rate limit says when to try again.
- Only one install runs at a time.
- The downloaded app is checked again right before it is installed.
- The update downloads only from Revzen's GitHub releases and follows redirects only to GitHub's asset servers over https.
- A stalled disk image or copy step ends with an error after 5 minutes.
- Downloads of an installed update are removed at the next launch.
- A failed relaunch after an update is recorded, also when debug logging is off.
- Revzen still starts when a macOS update removes the private calls it uses for window previews.
- Clicks and scrolls away from the Dock no longer wait for a slow Dock.
- Clicking the icon of an app that does not respond no longer blocks all input long enough for macOS to disable Revzen's event handling.
- A minimize from an earlier Dock click no longer hides a window that a later click restored.
- Fast scrolling over the icon of a slow app switches windows once for the whole scroll instead of once per step long after the scroll ended.
- The live window images appear in the preview when the pointer moves from the icon into the panel.
- Moving across Dock icons no longer captures every window of every icon passed.
- A window title can no longer add a fake line to the debug log.
- Errors in the system log carry their area as the category.


## [1.0.2] - 2026-09-24

### Added
- With debug logging on, the log records every update step, each helper tool run and its exit status, and the state in which the update window closed.

### Fixed
- A click on the icon of the active app minimizes its focused window, and the next click restores that same window. Before, macOS focused another window of the app after the minimize, so every click minimized one more window.
- The in-app update no longer stops after it unmounts the downloaded disk image.
- Revzen starts again after an in-app update. Before, the relaunch could fail because macOS still held the old app for a moment after it quit.
- `make run` starts the new build reliably after it quits the old one.

## [1.0.1] - 2026-09-24

### Added
- Minimized windows show their last image in the preview, also when they were minimized before Revzen started or before a restart. Revzen reads the image from the window server.
- Settings > Diagnostics > Debug logging writes every Dock click, hover, scroll, preview and window action to `~/Library/Logs/Revzen/revzen.log`, for reporting a problem. It is off by default.

### Changed
- CI and release workflows use the Node 24 releases of their GitHub Actions.

### Fixed
- The preview no longer opens when the Dock menu of an icon closes with the pointer still on the icon. It opens again once the pointer leaves the icon and returns.
- Moving the pointer slowly onto a Dock icon from above opens its preview. Before, the preview did not open until another icon was hovered first.
