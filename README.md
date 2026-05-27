# AdbManage

AdbManage is a lightweight Flutter Desktop toolbox for Android development and QA workflows.

The first version follows `FLUTTER_ADB_DESKTOP_TECH_PLAN.md`:

```text
Flutter Desktop UI
  -> Dart Process calls adb
  -> Dart Process starts external scrcpy
  -> Riverpod manages devices, sessions, and long-running processes
```

## Current Scope

| Module | Status | Notes |
|---|---:|---|
| Device list | Initial | Polls `adb devices -l` through `AdbService` |
| TCP/IP connect | Initial | Calls `adb connect <ip>:<port>` |
| scrcpy launcher | Initial | Starts external `scrcpy` with default MVP args |
| Device actions | Initial | Input text, Home/Back/Power, volume, Wi-Fi on/off |
| Layout helper | Initial | Layout bounds and dark/light mode |
| App management | Initial | Install APK, list packages, launch, stop, clear data, uninstall |
| File manager | Initial | Browse `/sdcard/`, drag files to push, pull, delete |
| Logcat | Initial | Start/stop stream, keep last 1000 lines, keyword filter |
| Shell / Performance | Planned | Directory structure is ready for feature expansion |

Drag and drop behavior:

| Dropped file | Action |
|---|---|
| `.apk` | `adb install -r <apk>` |
| other files | `adb push <file> <current remote path>` |

## Project Layout

```text
lib/
  app/
    router/
    theme/
  core/
    adb/
    apps/
    device_actions/
    files/
    logcat/
    providers/
    scrcpy/
  features/
    dashboard/
      presentation/
```

## Development Commands

```bash
flutter pub get
flutter analyze
flutter test
```

Run command for local manual checks:

```bash
flutter run -d macos
```

## Local Requirements

| Tool | Purpose |
|---|---|
| `adb` | Device discovery and shell commands |
| `scrcpy` | External screen mirroring MVP |
| Flutter Desktop | macOS, Windows, and Linux targets are generated |

ADB and scrcpy path customization is planned for the settings module.
