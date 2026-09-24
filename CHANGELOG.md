# Changelog

All notable changes to Revzen are documented in this file. The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.0.1] - 2026-09-24

### Added
- Minimized windows show their last image in the preview, also when they were minimized before Revzen started or before a restart. Revzen reads the image from the window server.
- Settings > Diagnostics > Debug logging writes every Dock click, hover, scroll, preview and window action to `~/Library/Logs/Revzen/revzen.log`, for reporting a problem. It is off by default.

### Changed
- CI and release workflows use the Node 24 releases of their GitHub Actions.

### Fixed
- The preview no longer opens when the Dock menu of an icon closes with the pointer still on the icon. It opens again once the pointer leaves the icon and returns.
- Moving the pointer slowly onto a Dock icon from above opens its preview. Before, the preview did not open until another icon was hovered first.
