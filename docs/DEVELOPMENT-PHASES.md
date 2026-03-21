## 10. Development Phases

### v1 — macOS + Linux + Web Client

#### Phase 1: Foundation & Discovery
- [x] Setup Flutter project (desktop only: Linux) ✅
- [ ] Implementasi mDNS discovery (advertise + browse)
  - [x] Discovery service implementation (macOS ready) ✅
  - [ ] Linux mDNS — `nsd` plugin tidak support Linux, perlu alternatif (avahi/dbus)
- [x] Desktop device list UI ✅
- [x] Basic TCP server/client between desktops ✅

**Catatan Phase 1:**
- Flutter snap tidak bisa dipakai (AppArmor confinement issue) — pakai manual install
- `nsd` plugin hanya support Android/iOS/macOS, **tidak support Linux desktop**
- mDNS discovery di-skip di Linux, perlu implementasi via `avahi-daemon` / D-Bus di fase selanjutnya
- Device list sudah menampilkan connected web clients (Android & iOS browser)

#### Phase 2: Desktop Clipboard Sync
- [x] Binary protocol message frame (v2 — 12-byte header with payload length) ✅
- [x] Text clipboard monitoring (polling via Flutter Clipboard API) ✅
- [x] Send/receive text between desktops (TCP) ✅
- [x] Clipboard history (in-memory, synced ke web clients) ✅
- [x] Manual IP connection (connect to desktop via IP:port) ✅
- [x] PIN-based pairing (6-digit PIN + HMAC-SHA256 verification) ✅
- [x] Session key derivation (HKDF-SHA256) ✅
- [x] HMAC authentication on all clipboard messages ✅
- [x] Persistent TCP connections (PeerConnection with message framing) ✅
- [x] Auto clipboard sync to all paired desktops ✅

**Catatan Phase 2:**
- Clipboard monitoring menggunakan polling (`500ms`) karena platform-specific listener belum diimplementasi
- Clipboard sync antara desktop ↔ mobile browser sudah berfungsi penuh
- Desktop ↔ desktop clipboard sync sudah berfungsi via TCP dengan PIN-based pairing
- Protocol version bumped ke v2 (header 12 bytes, tambah payloadLength field)
- Pairing flow: pairRequest → pairChallenge(nonce) → pairResponse(HMAC) → pairConfirm
- Session key di-derive via HKDF(PIN + nonce) untuk HMAC authentication ongoing messages
- Manual IP connection sebagai alternatif mDNS (Linux tidak support mDNS via nsd)

#### Phase 3: Embedded Web Server + Web Client
- [x] Embedded HTTP server di desktop app ✅
- [x] WebSocket handler ✅
- [x] Web SPA: HTML/CSS/JS skeleton ✅
- [x] QR code generation ✅
- [x] PIN-based auth for web clients (6-digit PIN verification) ✅
- [x] Session token caching (reconnect tanpa PIN ulang via localStorage) ✅
- [x] Mobile → Desktop: send clipboard text via WebSocket ✅
- [x] Desktop → Mobile: push clipboard updates via WebSocket ✅
- [x] Device identification via User-Agent parsing ✅
- [x] Web client auto-reconnect ✅
- [x] Clipboard history sync saat mobile connect ✅
- [x] Device list broadcast ke web clients ✅
- [x] Device list di desktop app (web clients dengan nama device) ✅

**Catatan Phase 3:**
- Web client berfungsi di Android Chrome dan iOS Safari
- Device name di-parse dari User-Agent (misal: "SM-A546E", "iPhone")
- Static files di-serve dengan no-cache header (development)
- Dark/light theme mengikuti system preference (CSS `prefers-color-scheme`)
- PIN auth: server generates PIN + nonce → mobile input PIN → verify → issue session token
- Web Crypto API (`crypto.subtle`) tidak tersedia di HTTP — fallback ke direct PIN verification
- Session token disimpan di localStorage (`cp_session_token`), dikirim via WebSocket query param saat reconnect

#### Phase 3.5: macOS Build & Test
- [x] Generate macOS platform files (`flutter create --platforms macos .`) ✅
- [x] Configure macOS entitlements (network.server, network.client) ✅
- [x] Tambah Bonjour service declaration di Info.plist (`_copypaste._tcp`) ✅
- [x] Tambah `NSLocalNetworkUsageDescription` di Info.plist ✅
- [x] Fix dependency/compatibility issues untuk macOS ✅
- [ ] ~~Test mDNS discovery (advertise + browse) di macOS~~ — deferred (manual IP connection cukup untuk v1)
- [x] Test web server + QR code + mobile browser access ✅
- [x] Test clipboard sync (desktop ↔ mobile browser) ✅
- [x] Build release: `flutter build macos` ✅

#### Phase 4: File Transfer
- [x] Desktop ↔ Desktop: chunked file transfer via TCP (64KB chunks) ✅
- [x] Mobile → Desktop: file upload via HTTP multipart ✅
- [x] Desktop → Mobile: file download via HTTP ✅
- [x] Transfer progress UI (desktop + web) ✅
- [x] Checksum verification (SHA-256) ✅

**Catatan Phase 4:**
- File transfer desktop ↔ desktop menggunakan chunked binary protocol (64KB per chunk)
- Upload mobile via multipart/form-data, download via `/api/download/:fileId`
- SHA-256 checksum verification di kedua sisi (sender & receiver)
- Transfer progress real-time di desktop (LinearProgressIndicator) dan web client
- Desktop UI memiliki tab Files dengan FAB untuk pick & send file
- File disimpan di temp directory (`/tmp/copypaste_files/`)
- Custom multipart parser (`mime_parser.dart`) karena Dart tidak ada built-in parser

#### Phase 5: Security
- [x] Desktop ↔ Desktop: PIN-based pairing + HMAC-SHA256 + HKDF session key ✅
- [x] Desktop ↔ Mobile: PIN-based authentication + session token ✅
- [x] Session management + token expiry + revocation ✅
- [ ] ~~Desktop ↔ Desktop: upgrade to X25519 key exchange + AES-256-GCM~~ — deferred (optional, tidak prioritas untuk local network)
- [ ] ~~Desktop ↔ Mobile: self-signed TLS (HTTPS + WSS)~~ — deferred (menambah UX friction di mobile browser)
- [ ] Secure key storage (macOS Keychain, Linux libsecret)

**Catatan Phase 5:**
- Desktop↔Desktop: PIN pairing + HMAC auth sudah berjalan penuh
- Desktop↔Mobile: PIN auth + session token caching sudah berjalan penuh
- Session management: token expiry 24 jam, max 10 sessions, revoke dari desktop UI, auto-cleanup tiap 15 menit
- X25519 + AES-256-GCM deferred — HMAC auth sudah cukup untuk local network, encryption bisa ditambah di v2
- Self-signed TLS deferred — menambah UX friction di mobile (terutama iOS Safari) tanpa benefit signifikan di local network
- Key storage masih in-memory (hilang saat app restart)

#### Phase 6: Polish & UX
- [ ] Image clipboard support
- [ ] Desktop notifications
- [ ] System tray (Linux) / menu bar (macOS) — minimize to background
- [ ] Web client PWA support (add to homescreen)
- [x] Dark/light theme (web client) ✅
- [ ] Dark/light theme (desktop — sudah pakai ThemeMode.system)
- [ ] Settings UI
- [ ] Multi-file transfer

#### Phase 7: v1 Release
- [ ] Unit tests & integration tests
- [ ] CI/CD pipeline (GitHub Actions)
- [x] Packaging: .deb (Linux) — `scripts/build-deb.sh` ✅
- [x] Packaging: .dmg (macOS) — `scripts/build-dmg.sh` ✅
- [x] README & user documentation ✅
- [x] Architecture documentation ✅
- [x] MIT License ✅
- [ ] First GitHub release

**Catatan Phase 7:**
- `scripts/build-deb.sh` — Build .deb package, auto Flutter build + dpkg-deb
- `scripts/build-dmg.sh` — Build .dmg package, auto Flutter build + code sign + hdiutil/create-dmg
- .deb installs ke `/usr/lib/copypaste/`, launcher di `/usr/bin/copypaste`, .desktop file included
- .dmg menggunakan `create-dmg` jika tersedia, fallback ke `hdiutil`

---

### Progress Summary

| Phase | Status | Completion |
|-------|--------|------------|
| Phase 1: Foundation & Discovery | Mostly done (mDNS Linux deferred) | ~85% |
| Phase 2: Desktop Clipboard Sync | **Complete** | 100% |
| Phase 3: Web Server + Web Client | **Complete** | 100% |
| Phase 3.5: macOS Build & Test | **Complete** (mDNS test deferred) | ~95% |
| Phase 4: File Transfer | **Complete** | 100% |
| Phase 5: Security | Auth + session mgmt done, encryption deferred, key storage pending | ~65% |
| Phase 6: Polish & UX | Theme done, rest pending | ~15% |
| Phase 7: v1 Release | Packaging & docs done, tests/CI pending | ~60% |

---

### Known Issues & TODO

| Issue | Detail | Priority |
|-------|--------|----------|
| Linux mDNS | `nsd` plugin tidak support Linux desktop. Workaround: manual IP connection | Medium |
| Clipboard polling | Menggunakan polling 500ms, bukan native listener per-platform | Low |
| Flutter snap | Tidak bisa dipakai karena AppArmor. Harus manual install | Info |
| Key persistence | Session keys hilang saat app restart — perlu secure storage | Medium |
| ~~Desktop ↔ Desktop sync~~ | ~~Solved~~ — PIN-based pairing + HMAC + persistent TCP | Done |
| ~~Mobile auth~~ | ~~Solved~~ — PIN verification + session token caching | Done |
| ~~Token auth (QR)~~ | ~~Replaced~~ — PIN-based auth menggantikan one-time QR token | Done |

---

### v2 — Windows Support (Future)

- [ ] Tambah Windows platform support di Flutter project
- [ ] Clipboard listener via Win32 API (`AddClipboardFormatListener`)
- [ ] System tray icon
- [ ] Windows Firewall auto-prompt
- [ ] Key storage via DPAPI / Windows Credential Store
- [ ] Packaging: .exe installer / MSIX
- [ ] Autostart via registry (optional)

---

### v3 — Native Mobile App (Future)

- [ ] Flutter mobile app (Android + iOS)
- [ ] Native clipboard monitoring (Android: `ClipboardManager`, iOS: `UIPasteboard`)
- [ ] mDNS discovery dari mobile (langsung P2P, tanpa web server)
- [ ] Background service (Android Foreground Service, iOS Background App Refresh)
- [ ] Push notifications
- [ ] App Store / Play Store distribution
