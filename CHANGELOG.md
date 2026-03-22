# Changelog

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
