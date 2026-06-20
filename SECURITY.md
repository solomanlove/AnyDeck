# Security Policy

## Supported Versions

AnyDeck is still in early public development. Security fixes are applied to the
latest code on the `main` branch unless a stable release branch is announced.

| Version | Supported |
| --- | --- |
| `main` | Yes |
| Older snapshots | No |

## Reporting a Vulnerability

Please do not open a public issue for sensitive security reports.

Report vulnerabilities through GitHub Security Advisories when available, or
contact the maintainer privately before publishing details. Include the
following information:

1. Affected platform: macOS, Windows, or Linux.
2. AnyDeck version, commit hash, or release package name.
3. Reproduction steps and expected impact.
4. Whether the issue requires a connected Android device, Root access, ADB over
   Wi-Fi, or a malicious local file.
5. Relevant logs with personal data removed.

## Security Scope

Security-sensitive areas in this project include:

- ADB command execution and argument handling.
- Wireless ADB pairing, TCP/IP switching, and device discovery.
- File upload/download operations against connected Android devices.
- Logcat, terminal, and long-running Process management.
- Screen mirroring, input injection, and scrcpy server delivery.
- Bundled native libraries under `scrcpy_flutter/macos/Libs/`.
- Local storage such as SharedPreferences and cached device metadata.

## Disclosure Process

1. The maintainer acknowledges the report after receiving enough detail.
2. The issue is reproduced and scoped.
3. A fix is prepared with the smallest practical code change.
4. A release note or advisory is published when the fix is available.

Please give the maintainer reasonable time to investigate before public
disclosure.

## Dependency And Binary Notice

AnyDeck depends on ADB, scrcpy-related components, FFmpeg-related libraries, and
desktop native integrations. Reports about vulnerable bundled binaries should
include the library name, version, platform, and CVE reference when possible.
