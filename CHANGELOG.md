# Changelog

All notable changes to AnyDeck will be documented in this file.

This project follows a lightweight changelog format inspired by
[Keep a Changelog](https://keepachangelog.com/), but does not currently promise
Semantic Versioning while the project is in early development.

## [Unreleased]

### Added

- Added public project documents: `SECURITY.md`, `CONTRIBUTING.md`, and this
  changelog.

### Changed

- Updated public repository references for `solomanlove/AnyDeck`.

### Fixed

- No fixes yet.

## [1.0.2]

### Added

- Device wall and list views with custom groups, live screenshot previews, and batch actions.
- Service diagnostics and improved local emulator discovery and setup guidance.
- Separate Android, HarmonyOS, and iOS MCP endpoints, with a persistent audit history and support for discovering and launching cloned Android apps.

### Changed

- Local screen recordings use the built-in Rust recorder for H.264/AAC MP4 output.
- File sharing combines the Honor and HarmonyOS flows in one view.

### Fixed

- Reduced UI stalls during device discovery and shell commands.
- Fixed iOS simulator window visibility with Xcode 27 and incorrect ports in DLNA device descriptions.

## [1.0.0] - 2026-06-20

### Added

- Initial public-ready Flutter Desktop project structure.
- ADB device discovery, connection, and control workflows.
- Screen mirroring integration with scrcpy-related components.
- Dashboard modules for apps, files, logcat, terminal, layout inspection, and
  emulator management.
- macOS, Windows, and Linux desktop targets.
