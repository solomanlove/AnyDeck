# AnyDeck (AdbManage) 🚀

[![License](https://img.shields.io/badge/License-Apache--2.0-blue.svg)](LICENSE)
[![Flutter](https://img.shields.io/badge/Flutter-%5E3.11.4-blue.svg?logo=flutter)](https://flutter.dev)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Windows%20%7C%20Linux-lightgrey.svg)](#)

**English** | [简体中文](README_ZH.md)

AnyDeck is a lightweight desktop developer toolbox for Android debugging and scrcpy workflows, built with Flutter Desktop. It streamlines daily Android development and QA testing operations by integrating commonly used ADB commands and screen mirroring controls into a clean, modern graphical interface.

---

## 📷 Screenshots & Demos

*(Replace these placeholders with actual screenshots of your running application)*

| 📱 Device Overview | 📺 Screen Mirroring | 📁 File Manager |
| :---: | :---: | :---: |
| ![Overview](https://raw.githubusercontent.com/solomanlove/AnyDeck/main/docs/screenshots/overview.png) | ![Mirroring](https://raw.githubusercontent.com/solomanlove/AnyDeck/main/docs/screenshots/mirror.png) | ![File Manager](https://raw.githubusercontent.com/solomanlove/AnyDeck/main/docs/screenshots/files.png) |

---

## ✨ Features

*   **🔌 Device Discovery & Pairing**: Automatically scan and connect via USB or wireless methods (TCP/IP, QR code scanning, and pairing code).
*   **📺 HD Screen Mirroring (Scrcpy)**: Start screen mirroring and reverse control using external Scrcpy settings or built-in decoders.
*   **⚙️ Quick Control Center**: Send text input, emulate hardware key events (Home, Back, Power, volume), toggle Wi-Fi, rotate screen, and inspect current window focus.
*   **📦 Application Manager**: Drag-and-drop APK files to install. Support app searching (pinyin supported), clearing data, freezing/unfreezing, uninstalling, and exporting/backing up APKs.
*   **🔍 Layout Inspector**: View the XML hierarchy layout tree of the current Android screen with interactive screenshot outlines.
*   **📂 File Browser**: Explore `/sdcard/`, upload files via drag-and-drop, batch-download files, and delete them.
*   **📄 Live Logcat**: Start/stop active Logcat logging with dynamic keyword filters and high-priority flags.
*   **🐚 Interactive Terminal**: Multi-tab embedded ADB Shell emulator with shell command history and a collection of custom diagnostic bookmarks.
*   **🤖 Emulator Manager**: List, start, and monitor local Android Virtual Devices (AVD).

---

## 🛠️ Architecture & Package ID

AnyDeck uses a clean, state-separated architecture:
-   **UI Layer (Flutter Desktop)**: Implements responsive grids and glassmorphism styling.
-   **State Management (Riverpod)**: Controls long-running processes (like terminal sessions and ADB connections), device sessions, and local configuration cache.
-   **Package Name (Bundle ID)**: The default unique application identifier is configured as **`com.github.anydeck`** across all desktop platforms:
    *   macOS: `com.github.anydeck` (configured in `macos/Runner/Configs/AppInfo.xcconfig`)
    *   Windows: CompanyName `github` (configured in `windows/runner/Runner.rc`)
    *   Linux: Application ID `com.github.anydeck` (configured in `linux/CMakeLists.txt`)

---

## 🚀 Quick Start

### 1. Prerequisites
AnyDeck relies on ADB and Scrcpy. Install them via your package manager:

#### 🍏 macOS
```bash
# Install ADB, FFmpeg, and Scrcpy
brew install android-platform-tools ffmpeg scrcpy
```

####  Windows
We recommend using `Chocolatey` or `Scoop`:
```bash
# Using Chocolatey
choco install adb ffmpeg scrcpy
```

### 2. Build & Run
Ensure Flutter SDK (`^3.11.4`) is configured locally.

```bash
# 1. Fetch dependencies
flutter pub get

# 2. Run in development mode
flutter run -d macos  # for macOS
# or
flutter run -d windows # for Windows

# 3. Build Release version
./script/build_macos.sh # builds and copies the .app to the Products/ folder
```

---

## 🤝 Contributing

Contributions are welcome! Please follow these standards when contributing:
*   Keep modified/new Dart files under **500 lines** for readability.
*   Separate UI presentation code from background services or state controllers.
*   Write inline comments in **Chinese** (comments inside `lib/` default to Chinese as per workspace rules).
*   Check out [AGENTS.md](AGENTS.md) to see the rules used to guide our AI coding workflows.

---

## 📄 License & Disclaimers

*   **License**: Licensed under the [Apache-2.0 License](LICENSE).
*   **Third-party Components**:
    *   `assets/scrcpy/scrcpy-server.jar` is compiled from the open-source [Genymobile/scrcpy](https://github.com/Genymobile/scrcpy) project and respects its license.
    *   Video decoding functionality links dynamically with [FFmpeg](https://ffmpeg.org).
*   **Trademarks**: All brand logos (Google, Xiaomi, Huawei, etc.) in `assets/brand/` are properties of their respective trademark holders. They are used in this project solely for non-commercial device identification purposes.
