# Contributing

Thank you for contributing to AnyDeck. This project is a Flutter Desktop
toolbox for Android debugging, ADB workflows, and scrcpy-based screen mirroring.

## Development Setup

Install the required CLI tools first:

```bash
brew install android-platform-tools ffmpeg scrcpy
flutter pub get
```

Use the platform target that matches your local machine:

```bash
flutter run -d macos
flutter run -d windows
flutter run -d linux
```

## Before You Start

Read the project rules and knowledge entry points:

```text
agent/rules/
agent/skills/index.md
agent/knowledge/index.md
```

For code changes, keep the diff focused on the requested task. Do not include
unrelated formatting, whitespace-only changes, generated build output, or IDE
metadata.

## Code Guidelines

| Area | Requirement |
| --- | --- |
| Language | Dart and Flutter conventions |
| Comments | Chinese for code comments and project notes; keep API, CLI, class names, and protocols in English |
| File size | New or refactored Dart files should stay under 500 lines |
| UI structure | Separate data, logic, and style |
| State | Prefer Riverpod Providers and immutable models |
| Process | Always set practical timeout and cleanup rules for ADB, scrcpy, and shell Process code |
| Localization | Do not hardcode visible UI text; update l10n tables |
| Theme | Verify both Light and Dark modes for UI changes |

## Pull Request Checklist

Before opening a PR:

```bash
git status --short
git diff
dart format --set-exit-if-changed lib test
dart analyze
flutter test
```

If a check cannot be run locally, mention the reason in the PR description.

## ADB And Device Safety

Changes that execute ADB commands must consider:

1. Argument injection and path escaping.
2. Timeout handling for offline or unauthorized devices.
3. Process stream cleanup to avoid zombie processes.
4. Root-only behavior and Android version differences.
5. Whether the command mutates device data, settings, apps, or files.

Destructive actions must be clearly labeled in the UI and guarded against
duplicate clicks.

## Documentation Updates

Update documentation when a change affects:

- User-visible behavior.
- Build or installation steps.
- ADB command mechanisms.
- Multi-window behavior.
- scrcpy or native binary packaging.
- Security-sensitive flows.

For major feature work, also update the relevant document under
`agent/knowledge/` and register it in `agent/knowledge/index.md`.

## Commit Style

Use concise commit messages that describe the actual change:

```text
docs: add security and contribution guides
fix: prevent duplicate adb process start
feat: add wireless pairing status panel
```

Keep one commit focused on one logical change.
