# Changelog

## v0.5.0 - 2026-04-01

### New Features
- **Desktop notifications** — notify when clipboard text or file is received from a remote device (Linux, macOS, Windows)
- **System tray / menu bar** — app minimizes to tray instead of quitting; click icon to show/hide window (Linux AppIndicator, macOS menu bar, Windows tray)
- **Settings UI** — new settings screen accessible via gear icon: device info, paired desktops management (unpair), web session management (revoke), data clearing
- **Dark/Light/System theme toggle** — manual theme selector in Settings, persisted across restarts
- **Web client PWA** — web client installable as app on Android/iOS (Add to Home Screen)
- **App version display** — version shown at bottom of Settings screen

### Bug Fixes
- Fixed macOS window close quitting the app instead of hiding to tray (`applicationShouldTerminateAfterLastWindowClosed`)
- Fixed tray icon race condition on macOS (`setPreventClose` now registered before window listener)
- Fixed tray icon blank on Windows (use `.ico` format instead of `.png`)
- Fixed `setToolTip` crash on Linux (not supported by tray_manager)
- Fixed macOS tray left-click behavior (now shows context menu per macOS convention)
- Fixed version not showing on macOS Settings (graceful fallback for stale xcconfig)

### Improvements
- Build scripts (`build-deb.sh`, `build-dmg.sh`, `build-windows.ps1`, `installer.iss`) now auto-read version from `pubspec.yaml` — no more manual version bumps in scripts
- `.deb` package now declares `libayatana-appindicator3-1` as dependency for system tray support
- Upgraded `window_manager` to 0.5.1, `shared_preferences` to 2.5.5, `flutter_lints` to 6.0.0

## v0.4.0 - 2026-03-22

### New Features
- **HTTPS-only mode** — Removed HTTP mode, all connections now enforce HTTPS with self-signed TLS certificates
- **Pure Dart certificate generation** — Replaced OpenSSL CLI dependency with built-in Dart certificate generation, improving cross-platform compatibility
- **Windows Installer** — Added Inno Setup-based installer (`_Setup.exe`) alongside the existing portable ZIP
- **Safari iOS support** — Added HTTP polling fallback for Safari iOS which doesn't support self-signed WebSocket connections

### Bug Fixes
- Fixed SSL bug on Windows version

### Improvements
- Improved AppBar UX
- Added release directory to `.gitignore`

## v0.3.0

_Initial tracked release._
