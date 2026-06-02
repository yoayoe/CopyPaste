# Changelog

## v0.5.1 - 2026-06-03

### New Features

- **Android native app (Beta)** — Flutter Android build that pairs with desktops over TCP, just like another desktop (PIN pairing + HMAC + auto clipboard receive). On Android, sending is a manual **Read & Send** action on the Clipboard tab (the OS blocks background clipboard reads since Android 10); receiving is automatic — written to the clipboard and shown in history.
- **Android build script** (`scripts/build-apk.sh`) — builds a release `.apk` named after the release version (`CopyPaste_<version>_Android.apk`), auto-detecting `JAVA_HOME` / `ANDROID_HOME`.

### Bug Fixes

- **Safari iOS false "Connected" status** — Safari aggressively caches GET `/api/poll` responses, causing the web client to always display "Connected" even when the desktop app is unreachable. Fixed by adding `Cache-Control: no-cache, no-store, must-revalidate` headers to all HTTP responses and `cache: 'no-cache'` on client fetch calls.
- **Service worker caching stale JS** — PWA service worker previously cached JS files, causing users to run old code after page refresh. JS files are now fetched live from the server.
- **Polling connection state** — Added proper polling fail count tracking (`pollingFailCount`), auth state management (`_pollingAuthenticated`), and a 5-second fetch timeout in `pollMessages()` to correctly detect disconnections in polling mode.
- **Android launch crash** — fixed a `MainActivity` package mismatch (`com.example.copypaste` → `com.copypaste.app`) that caused an immediate `ClassNotFoundException` on launch.
- **Android build failure** — forced `compileSdk 36` on the app and all plugins (`file_picker` pulls in `flutter_plugin_android_lifecycle`, which requires SDK 36).
- Guarded desktop-only services (`window_manager`, tray, notifications) behind a platform check so they no longer run on Android.

### Improvements

- Web client now correctly shows "Disconnected" in polling mode when the server is unreachable (previously guarded by `WS.isPolling()` check).
- **Connection resilience** — added a 15-second heartbeat (PING/PONG) to keep idle TCP connections alive, plus automatic reconnect when a paired peer drops unexpectedly (Wi-Fi blip, idle timeout, Android backgrounding). Intentional unpair/shutdown is excluded.
- Build outputs now follow the release version across all platforms.

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
