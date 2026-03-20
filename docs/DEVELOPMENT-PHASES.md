## 10. Development Phases

### v1 — macOS + Linux + Web Client

#### Phase 1: Foundation & Discovery
- [x] Setup Flutter project (desktop only: Linux) ✅
- [ ] Implementasi mDNS discovery (advertise + browse)
  - [x] Discovery service implementation (macOS ready)
  - [ ] Linux mDNS — `nsd` plugin tidak support Linux, perlu alternatif (avahi/dbus)
- [x] Desktop device list UI ✅
- [x] Basic TCP server/client between desktops ✅

**Catatan Phase 1:**
- Flutter snap tidak bisa dipakai (AppArmor confinement issue) — pakai manual install
- `nsd` plugin hanya support Android/iOS/macOS, **tidak support Linux desktop**
- mDNS discovery di-skip di Linux, perlu implementasi via `avahi-daemon` / D-Bus di fase selanjutnya
- Device list sudah menampilkan connected web clients (Android & iOS browser)

#### Phase 2: Desktop Clipboard Sync
- [x] Binary protocol message frame ✅
- [x] Text clipboard monitoring (polling via Flutter Clipboard API) ✅
- [ ] Send/receive text between desktops (TCP) — protocol ready, belum wired antar desktop
- [x] Clipboard history (in-memory, synced ke web clients) ✅

**Catatan Phase 2:**
- Clipboard monitoring menggunakan polling (`500ms`) karena platform-specific listener belum diimplementasi
- Clipboard sync antara desktop ↔ mobile browser sudah berfungsi penuh
- Desktop ↔ desktop clipboard sync via TCP belum di-wire

#### Phase 3: Embedded Web Server + Web Client
- [x] Embedded HTTP server di desktop app ✅
- [x] WebSocket handler ✅
- [x] Web SPA: HTML/CSS/JS skeleton ✅
- [x] QR code generation ✅
- [ ] Token auth (QR code berisi one-time token)
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

#### Phase 4: File Transfer
- [ ] Desktop ↔ Desktop: chunked file transfer via TCP
- [ ] Mobile → Desktop: file upload via HTTP multipart
- [ ] Desktop → Mobile: file download via HTTP
- [ ] Transfer progress UI (desktop + web)
- [ ] Checksum verification

#### Phase 5: Security
- [ ] Desktop ↔ Desktop: X25519 key exchange + AES-256-GCM
- [ ] Desktop ↔ Mobile: self-signed TLS (HTTPS)
- [ ] Session management + token expiry
- [ ] Secure key storage (macOS Keychain, Linux libsecret)

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
- [ ] Packaging: AppImage / .deb (Linux), .dmg (macOS)
- [ ] README & user documentation
- [x] MIT License ✅
- [ ] First GitHub release

---

### Known Issues & TODO

| Issue | Detail | Priority |
|-------|--------|----------|
| Linux mDNS | `nsd` plugin tidak support Linux desktop. Perlu implementasi via `avahi-daemon` D-Bus API | High |
| Desktop ↔ Desktop sync | TCP protocol ready tapi belum di-wire untuk clipboard sync antar desktop | Medium |
| Token auth | QR code belum berisi one-time token, URL langsung tanpa auth | Medium |
| Clipboard polling | Menggunakan polling 500ms, bukan native listener per-platform | Low |
| Flutter snap | Tidak bisa dipakai karena AppArmor. Harus manual install | Info |

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
