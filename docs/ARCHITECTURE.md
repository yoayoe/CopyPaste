# CopyPaste - Architecture Document

## 1. Overview

**CopyPaste** adalah open-source, self-hosted, cross-platform clipboard sharing dan file transfer tool yang bekerja melalui local network (P2P). Copy di satu device, paste di device lain — tanpa cloud, tanpa server, tanpa internet.

### Arsitektur Hybrid

CopyPaste menggunakan **arsitektur hybrid** dengan dua tipe client:

| Tipe | Platform | Teknologi | Kapabilitas | Status |
|------|----------|-----------|-------------|--------|
| **Desktop App** | macOS, Linux | Flutter | Full-featured: auto clipboard sync, background service, file transfer, mDNS discovery, **embedded web server**, system tray | **v1 ✅** |
| **Web Client** | Android, iOS (any mobile browser) | HTML/CSS/JS (SPA) | Manual clipboard (browser limitation), file transfer, **no install required**, PWA installable | **v1 ✅** |
| **Desktop App** | Windows | Flutter | Same as macOS/Linux | **v2 ✅** |
| **Mobile App** | Android, iOS | Flutter | Full-featured native mobile app dengan auto clipboard sync | **v3 (Future)** |

Mobile device cukup **scan QR code** dari desktop app → buka browser → langsung pakai.

### Roadmap

| Versi | Scope | Deskripsi | Status |
|-------|-------|-----------|--------|
| **v1** | macOS + Linux + Web Client | Desktop app untuk macOS & Linux dengan embedded web server. Mobile akses via browser. | ✅ Released |
| **v2** | + Windows | Tambah Windows desktop support, system tray, settings UI, notifications. | ✅ Released |
| **v3** | + Mobile Native App | Flutter mobile app (Android/iOS) untuk full-featured experience di mobile. | Planned |

### Prinsip Desain

- **Zero Server** — Tidak ada central server. Semua komunikasi P2P dalam local network.
- **Privacy First** — Data tidak pernah keluar dari jaringan lokal. Semua transfer dienkripsi.
- **Simple & Fast** — UI minimal, transfer langsung, tanpa overhead.
- **No Install on Mobile** — Mobile user akses via browser, tidak perlu install app.
- **Desktop as Hub** — Desktop app menjadi hub yang serve web UI untuk mobile client.

---

## 2. High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      LOCAL NETWORK (LAN/WiFi)                    │
│                                                                  │
│  ┌────────────────────┐  TCP (P2P)  ┌────────────────────┐      │
│  │   Desktop A        │◄═══════════►│   Desktop B        │      │
│  │   (macOS/Linux/    │  mDNS       │   (macOS/Linux/    │      │
│  │    Windows)        │  Discovery  │    Windows)        │      │
│  │                    │  Discovery  │                    │      │
│  │  ┌──────────────┐  │             │  ┌──────────────┐  │      │
│  │  │ Flutter App  │  │             │  │ Flutter App  │  │      │
│  │  │ - Clipboard  │  │             │  │ - Clipboard  │  │      │
│  │  │ - TCP P2P    │  │             │  │ - TCP P2P    │  │      │
│  │  │ - Web Server │  │             │  │ - Web Server │  │      │
│  │  └──────┬───────┘  │             │  └──────┬───────┘  │      │
│  └─────────┼──────────┘             └─────────┼──────────┘      │
│            │ HTTP + WebSocket                  │                  │
│            │ (serve web UI)                    │                  │
│            ▼                                   ▼                  │
│  ┌────────────────────┐             ┌────────────────────┐      │
│  │   Mobile Phone     │             │   Mobile Tablet    │      │
│  │   (Android)        │             │   (iPad)           │      │
│  │                    │             │                    │      │
│  │  ┌──────────────┐  │             │  ┌──────────────┐  │      │
│  │  │   Browser    │  │             │  │   Browser    │  │      │
│  │  │   (Web SPA)  │  │             │  │   (Web SPA)  │  │      │
│  │  └──────────────┘  │             │  └──────────────┘  │      │
│  └────────────────────┘             └────────────────────┘      │
│                                                                  │
│  Komunikasi:                                                     │
│  Desktop ◄══► Desktop : TCP direct (P2P, auto clipboard sync)   │
│  Desktop ◄──► Mobile  : WebSocket (manual clipboard, file xfer) │
└──────────────────────────────────────────────────────────────────┘
```

### Dua Mode Komunikasi

| Mode | Channel | Use Case |
|------|---------|----------|
| **Desktop ↔ Desktop** | TCP direct + mDNS discovery | Full auto-sync clipboard, file transfer |
| **Desktop ↔ Mobile** | HTTP + WebSocket (served by desktop) | Manual clipboard, file transfer via browser |

---

## 3. Komponen Arsitektur

### 3.1 Discovery Layer (mDNS/DNS-SD)

Bertanggung jawab untuk menemukan desktop device lain di jaringan lokal secara otomatis. **Hanya berlaku untuk Desktop ↔ Desktop.**

```
┌─────────────────────────────────────────┐
│            Discovery Layer              │
│         (Desktop only)                  │
│                                         │
│  ┌─────────────┐   ┌─────────────────┐  │
│  │  Advertise   │   │   Browse/Listen │  │
│  │  Service     │   │   for Services  │  │
│  │              │   │                 │  │
│  │  _copypaste  │   │  Discover       │  │
│  │  ._tcp.local │   │  nearby desktops│  │
│  └─────────────┘   └─────────────────┘  │
└─────────────────────────────────────────┘
```

**Detail:**
- **Service Type**: `_copypaste._tcp.local.`
- **Port**: Dynamic (dipilih saat startup, di-advertise via mDNS)
- **TXT Record** berisi metadata device:
  ```
  id=<unique-device-id>
  name=<device-display-name>
  platform=<windows|macos|linux>
  version=<protocol-version>
  web_port=<http-server-port>
  ```
- **Library**: `nsd` (Flutter plugin untuk Network Service Discovery)

**Flow:**
1. App start → register mDNS service dengan info device
2. Secara bersamaan, browse/listen untuk service `_copypaste._tcp`
3. Saat device baru ditemukan → tambahkan ke device list
4. Saat device hilang → hapus dari device list

**Mobile Discovery:**
Mobile tidak menggunakan mDNS. Koneksi ke desktop dilakukan via **QR code scan** yang berisi URL web server desktop.

---

### 3.2 Network Layer

Dua channel komunikasi terpisah:

```
┌───────────────────────────────────────────────────────────────┐
│                      Network Layer                            │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Channel 1: TCP Direct (Desktop ↔ Desktop)             │  │
│  │                                                         │  │
│  │  ┌──────────┐  connect(ip:port)  ┌──────────┐          │  │
│  │  │  TCP     │ ──────────────────►│  TCP     │          │  │
│  │  │  Client  │  encrypted data    │  Server  │          │  │
│  │  └──────────┘                    └──────────┘          │  │
│  │                                                         │  │
│  │  - Binary protocol v2 (12-byte header)                   │  │
│  │  - PeerConnection: persistent TCP with message framing  │  │
│  │  - PIN-based pairing + HMAC-SHA256 authentication       │  │
│  │  - Auto clipboard sync + chunked file transfer (64KB)   │  │
│  └─────────────────────────────────────────────────────────┘  │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐  │
│  │  Channel 2: HTTP + WebSocket (Desktop ↔ Mobile)        │  │
│  │                                                         │  │
│  │  ┌──────────┐   GET /            ┌──────────────────┐  │  │
│  │  │  Mobile  │ ──────────────────►│  Desktop         │  │  │
│  │  │  Browser │   WS /ws           │  HTTP Server     │  │  │
│  │  │          │ ◄════════════════► │  + WebSocket     │  │  │
│  │  └──────────┘                    │  + Static Files  │  │  │
│  │                                  └──────────────────┘  │  │
│  │  - JSON messages over WebSocket                        │  │
│  │  - PIN-based authentication + session token caching    │  │
│  │  - File upload/download via HTTP multipart             │  │
│  │  - Web UI served as static SPA                         │  │
│  └─────────────────────────────────────────────────────────┘  │
└───────────────────────────────────────────────────────────────┘
```

---

### 3.3 Embedded Web Server (Desktop)

Setiap desktop app menjalankan embedded HTTP server yang serve web UI untuk mobile client.

```
┌──────────────────────────────────────────────────────────────┐
│              Embedded Web Server (dalam Desktop App)         │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  HTTP Server (dart:io HttpServer)                      │  │
│  │  Port: dynamic (e.g. 8080-8099)                        │  │
│  │                                                        │  │
│  │  Routes:                                               │  │
│  │  ┌──────────────────────────────────────────────────┐  │  │
│  │  │  GET  /              → Web SPA (index.html)      │  │  │
│  │  │  GET  /assets/*      → Static files (JS/CSS)     │  │  │
│  │  │  WS   /ws            → WebSocket endpoint        │  │  │
│  │  │  POST /api/upload    → File upload dari mobile    │  │  │
│  │  │  GET  /api/download/:id → File download ke mobile│  │  │
│  │  │  GET  /api/status    → Server status / health     │  │  │
│  │  └──────────────────────────────────────────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  WebSocket Handler                                     │  │
│  │                                                        │  │
│  │  Events (Server → Client):                             │  │
│  │  - clipboard:update   → New clipboard content          │  │
│  │  - transfer:incoming  → Incoming file notification     │  │
│  │  - transfer:progress  → Transfer progress update       │  │
│  │  - device:list        → Connected devices update       │  │
│  │                                                        │  │
│  │  Events (Client → Server):                             │  │
│  │  - clipboard:send     → Send text to clipboard/device  │  │
│  │  - clipboard:fetch    → Request current clipboard      │  │
│  │  - transfer:accept    → Accept incoming file           │  │
│  │  - transfer:reject    → Reject incoming file           │  │
│  └────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────┘
```

**QR Code + PIN Connection Flow:**
```
Desktop App                              Mobile Phone
    │                                        │
    │  1. Generate QR code containing:       │
    │     http://<local-ip>:<port>           │
    │     (tampil di desktop screen)         │
    │                                        │
    │                          2. Scan QR    │
    │                          3. Open URL   │
    │                             in browser │
    │                                        │
    │  4. Serve Web SPA     ◄────────────────│  GET /
    │  ────────────────────►                 │
    │                                        │
    │  5. WebSocket connect ◄════════════════│  WS /ws
    │  ═════════════════════►                │
    │                                        │
    │  6. Generate 6-digit PIN               │
    │  7. Show PIN dialog on desktop         │
    │  8. Send auth:challenge to mobile      │
    │  ════════════════════════════════►      │
    │                                        │
    │                          9. Show PIN   │
    │                             input      │
    │                         10. User       │
    │                             enters PIN │
    │                                        │
    │  11. Verify PIN       ◄════════════════│  auth:verify
    │  12. Generate session token            │
    │  13. Send auth:success + token         │
    │  ════════════════════════════════►      │
    │                                        │  14. Save token
    │  15. Add to connected devices          │      to localStorage
    │                                        │
    │  ◄──── Real-time sync active ────►     │
    │                                        │
```

**Reconnect Flow (tanpa PIN ulang):**
```
Mobile Phone                             Desktop App
    │                                        │
    │  1. Page refresh / reconnect           │
    │  2. Read token from localStorage       │
    │  3. WebSocket connect with token       │
    │  WS /ws?token=<saved-token>            │
    │  ════════════════════════════════►      │
    │                                        │
    │                       4. Validate token │
    │                       5. Auto-auth     │
    │  auth:success         ◄════════════════│
    │                                        │
    │  ◄──── Sync resumed instantly ────►    │
```

**Session Security:**
- PIN 6-digit generated per mobile connection
- Session token generated setelah PIN verified
- Token disimpan di browser localStorage (`cp_session_token`)
- Token disimpan di server in-memory Set
- Reconnect via token — no PIN re-entry needed
- Token hilang saat server restart (by design — re-pair needed)

---

### 3.4 Protocol Layer

Dua format protocol berbeda untuk dua channel komunikasi:

#### 3.4.1 Binary Protocol v2 (Desktop ↔ Desktop via TCP)

```
┌──────────────────────────────────────────────────────┐
│           Binary Message Frame v2 (TCP)              │
│                                                      │
│  ┌───────────┬──────────┬───────────────────┐        │
│  │  Header   │  Meta    │     Payload       │        │
│  │  12 bytes │  N bytes │     M bytes       │        │
│  └───────────┴──────────┴───────────────────┘        │
│                                                      │
│  Header (12 bytes):                                  │
│    [0]   magic byte 1 (0x43 = 'C')                   │
│    [1]   magic byte 2 (0x50 = 'P')                   │
│    [2]   protocol version (currently: 2)             │
│    [3]   message type code                           │
│    [4-7] metadata length (uint32, big-endian)        │
│    [8-11] payload length (uint32, big-endian)        │
│                                                      │
│  Meta (JSON):                                        │
│    - filename, mime_type, size, checksum,            │
│      sender, senderName, hmac, dll                   │
│                                                      │
│  Payload:                                            │
│    - raw bytes (text content / file chunk bytes)     │
└──────────────────────────────────────────────────────┘
```

**Message Types (TCP):**

| Type Code | Nama | Deskripsi |
|-----------|------|-----------|
| `0x01` | `TEXT` | Clipboard text content |
| `0x02` | `IMAGE` | Clipboard image (planned) |
| `0x03` | `FILE` | File transfer chunk (64KB per chunk) |
| `0x04` | `FILES` | Multiple files transfer (planned) |
| `0x05` | `PING` | Heartbeat / connectivity check |
| `0x06` | `PONG` | Response to PING |
| `0x07` | `ACK` | Transfer acknowledgement |
| `0x08` | `REJECT` | Transfer ditolak |
| `0x10` | `PAIR_REQUEST` | Pairing handshake: initiate pairing |
| `0x11` | `PAIR_CHALLENGE` | Pairing handshake: server sends nonce |
| `0x12` | `PAIR_RESPONSE` | Pairing handshake: client sends HMAC(PIN+nonce) |
| `0x13` | `PAIR_CONFIRM` | Pairing handshake: server confirms pairing |
| `0x14` | `DISCONNECT` | Connection control: graceful disconnect |

**Pairing Handshake Flow (TCP):**
```
Desktop A (initiator)                  Desktop B (responder)
    │                                       │
    │  pairRequest(deviceId, deviceName)     │
    │  ────────────────────────────────────► │
    │                                       │  Generate 6-digit PIN
    │                                       │  Generate random nonce
    │                                       │  Show PIN to user
    │  pairChallenge(nonce)                 │
    │  ◄──────────────────────────────────── │
    │                                       │
    │  User enters PIN on Desktop A         │
    │  Compute HMAC-SHA256(PIN, nonce)       │
    │  Derive session key via HKDF          │
    │                                       │
    │  pairResponse(hmac)                   │
    │  ────────────────────────────────────► │
    │                                       │  Verify HMAC
    │                                       │  Derive session key
    │  pairConfirm(success)                 │
    │  ◄──────────────────────────────────── │
    │                                       │
    │  ◄═══ Paired: auto clipboard sync ═══►│
```

#### 3.4.2 JSON Protocol (Desktop ↔ Mobile via WebSocket)

WebSocket menggunakan JSON messages yang lebih sederhana (browser-friendly).

```json
{
  "event": "clipboard:send",
  "data": {
    "id": "msg-uuid-123",
    "type": "text",
    "content": "Hello from mobile",
    "timestamp": 1710900000
  }
}
```

**WebSocket Events:**

| Event | Direction | Deskripsi |
|-------|-----------|-----------|
| `auth:challenge` | Server → Client | PIN challenge (nonce) — mobile harus input PIN |
| `auth:verify` | Client → Server | Mobile mengirim PIN untuk verifikasi |
| `auth:success` | Server → Client | PIN verified, berisi session token |
| `auth:failed` | Server → Client | PIN salah |
| `auth:required` | Server → Client | Token expired, perlu PIN ulang |
| `clipboard:update` | Server → Client | Desktop clipboard berubah, kirim ke mobile |
| `clipboard:send` | Client → Server | Mobile mengirim teks ke desktop clipboard |
| `clipboard:fetch` | Client → Server | Mobile request clipboard content saat ini |
| `clipboard:history` | Server → Client | Kirim clipboard history |
| `transfer:incoming` | Server → Client | Ada file masuk dari device lain |
| `transfer:progress` | Server → Client | Progress update file transfer |
| `transfer:accept` | Client → Server | Mobile terima file |
| `transfer:reject` | Client → Server | Mobile tolak file |
| `device:list` | Server → Client | Daftar device yang terkoneksi |
| `device:connected` | Server → Client | Device baru bergabung |
| `device:disconnected` | Server → Client | Device disconnect |

**File Transfer via HTTP (bukan WebSocket):**
- **Upload (Mobile → Desktop)**: `POST /api/upload` dengan `multipart/form-data`
- **Download (Desktop → Mobile)**: `GET /api/download/:id` → browser download file
- WebSocket hanya untuk signaling & progress, actual file data via HTTP

---

### 3.5 Security Layer

```
┌──────────────────────────────────────────────────────────────┐
│                     Security Layer                           │
│                                                              │
│  Desktop ↔ Desktop (TCP):                                   │
│  ┌──────────┐   6-digit PIN   ┌──────────┐                  │
│  │ Desktop A│ ◄──────────────► │ Desktop B│                  │
│  │          │  HMAC-SHA256     │          │                  │
│  │          │  verification    │          │                  │
│  └──────────┘                  └──────────┘                  │
│       │                             │                        │
│       ▼                             ▼                        │
│  Session key (HKDF) ────────► HMAC on all messages          │
│                                                              │
│  Desktop ↔ Mobile (WebSocket):                              │
│  ┌──────────┐   QR Code       ┌──────────┐                  │
│  │ Desktop  │ ──────────────► │  Mobile  │                  │
│  │          │  URL + PIN      │  Browser │                  │
│  │          │                 │          │                  │
│  │  HTTP +  │ ◄═════════════► │  HTTP +  │                  │
│  │  WS      │  PIN verify     │  WS      │                  │
│  └──────────┘                  └──────────┘                  │
│                                                              │
│  Mobile connection dilindungi oleh:                          │
│  - 6-digit PIN verification (shown on desktop)              │
│  - Session token setelah PIN verified (localStorage)        │
│  - Auto-reconnect tanpa PIN ulang (token-based)             │
└──────────────────────────────────────────────────────────────┘
```

**Desktop ↔ Desktop (Current Implementation):**
- **Pairing**: 6-digit PIN displayed on responder
- **Verification**: HMAC-SHA256(PIN, nonce) — nonce dari server
- **Session Key**: HKDF-SHA256(PIN + nonce) untuk ongoing authentication
- **Per-message**: HMAC authentication menggunakan session key
- **Persistent Connection**: TCP connection tetap terbuka setelah pairing
- **Future upgrade**: X25519 ECDH key exchange + AES-256-GCM encryption (Phase 5)

**Desktop ↔ Mobile (Current Implementation):**
- **Authentication**: 6-digit PIN shown on desktop, entered on mobile
- **PIN Verification**: Direct PIN match (HTTPS enforced — no fallback needed)
- **Session Token**: Generated setelah PIN verified, saved di localStorage
- **Auto-reconnect**: Token dikirim via WebSocket query param `?token=...`
- **Transport**: HTTPS + WSS dengan self-signed TLS certificate (pure Dart, no OpenSSL)
- **Certificate**: Generated at first run, persisted to app support directory

---

### 3.6 Clipboard Service (Desktop Only)

Auto-monitor clipboard. Hanya berjalan di desktop app.

```
┌──────────────────────────────────────────────────┐
│       Clipboard Service (Desktop Only)           │
│                                                  │
│  ┌────────────────┐    ┌──────────────────┐      │
│  │  Clipboard     │    │  Clipboard       │      │
│  │  Monitor       │    │  Writer          │      │
│  │                │    │                  │      │
│  │  Poll/Listen   │    │  Set clipboard   │      │
│  │  for changes   │    │  from received   │      │
│  │  ──────────►   │    │  data            │      │
│  │  Trigger send  │    │  ◄──────────     │      │
│  │  to paired     │    │                  │      │
│  │  desktops +    │    │                  │      │
│  │  connected     │    │                  │      │
│  │  web clients   │    │                  │      │
│  └────────────────┘    └──────────────────┘      │
│                                                  │
│  ┌────────────────────────────────────────────┐  │
│  │  Clipboard History (local storage)         │  │
│  │  - Last 50 items                           │  │
│  │  - Text, images                            │  │
│  │  - Timestamp + source device               │  │
│  └────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

**Mode Operasi:**
- **Auto-sync**: Clipboard change → kirim ke semua paired desktop + connected mobile
- **Manual**: User pilih item dan target device
- **Selective**: Auto-sync hanya ke device tertentu

**Platform-specific:**
| Platform | Clipboard Access | Status |
|----------|-----------------|--------|
| macOS    | `NSPasteboard` + polling (500ms) | ✅ |
| Linux    | `X11/Wayland clipboard` + polling (500ms) | ✅ |
| Windows  | Flutter Clipboard API + polling (500ms) | ✅ |

---

### 3.7 Web Client (Mobile SPA)

Single Page Application yang diakses via browser di mobile device.

```
┌──────────────────────────────────────────────────────────────┐
│                   Web Client (SPA)                           │
│                   Served by Desktop App                      │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  UI Components                                         │  │
│  │                                                        │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌─────────────┐  │  │
│  │  │  Clipboard   │  │  File        │  │  Devices    │  │  │
│  │  │  Panel       │  │  Transfer    │  │  List       │  │  │
│  │  │              │  │              │  │             │  │  │
│  │  │ - Text input │  │ - Pick file  │  │ - Connected │  │  │
│  │  │ - Paste btn  │  │ - Upload btn │  │   desktops  │  │  │
│  │  │ - Copy btn   │  │ - Progress   │  │ - Connected │  │  │
│  │  │ - History    │  │ - Download   │  │   mobiles   │  │  │
│  │  │   list       │  │   received   │  │             │  │  │
│  │  └──────────────┘  └──────────────┘  └─────────────┘  │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  Browser Clipboard Interaction                         │  │
│  │                                                        │  │
│  │  Send to desktop:                                      │  │
│  │  1. User paste (Ctrl+V) ke text area                   │  │
│  │  2. Tap "Send" button                                  │  │
│  │  3. → WebSocket event: clipboard:send                  │  │
│  │                                                        │  │
│  │  Receive from desktop:                                 │  │
│  │  1. WebSocket event: clipboard:update                  │  │
│  │  2. Content tampil di UI                               │  │
│  │  3. User tap "Copy" button                             │  │
│  │  4. → navigator.clipboard.writeText()                  │  │
│  │  5. User bisa paste di app lain                        │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐  │
│  │  File Transfer (via HTTP)                              │  │
│  │                                                        │  │
│  │  Send file to desktop:                                 │  │
│  │  1. User tap "Pick File" → <input type="file">        │  │
│  │  2. Upload via POST /api/upload (multipart)            │  │
│  │  3. Progress via WebSocket                             │  │
│  │                                                        │  │
│  │  Receive file from desktop:                            │  │
│  │  1. Notification via WebSocket (transfer:incoming)     │  │
│  │  2. User tap "Accept"                                  │  │
│  │  3. Browser downloads via GET /api/download/:id        │  │
│  └────────────────────────────────────────────────────────┘  │
│                                                              │
│  Tech: Vanilla JS + minimal CSS (< 50KB total)              │
│  No framework dependency — fast load, zero build step        │
└──────────────────────────────────────────────────────────────┘
```

**Browser Clipboard Limitations & Mitigations:**

| Limitasi | Mitigasi |
|----------|----------|
| Tidak bisa auto-read clipboard | User paste manual ke text area atau tap "Read Clipboard" button (requires user gesture) |
| Tidak bisa monitor clipboard di background | Tampilkan clipboard history dari desktop, user manual send |
| `navigator.clipboard.writeText()` butuh user gesture | Tap "Copy" button triggers clipboard write |
| Tab ditutup = disconnect | Reconnect otomatis saat tab dibuka kembali, session persisted |
| Tidak bisa terima push notification | In-page notification saat tab aktif |

---

### 3.8 File Transfer Service

Menangani pengiriman dan penerimaan file. Berbeda flow untuk desktop dan mobile.

```
┌──────────────────────────────────────────────────────────────┐
│                  File Transfer Service                       │
│                                                              │
│  Desktop ↔ Desktop (TCP):                                   │
│  ┌──────────┐  ┌──────────┐  ┌────────────────────────┐     │
│  │  Pick    │─►│  Chunk   │─►│  Stream via TCP        │     │
│  │  File(s) │  │  File    │  │  (binary, 64KB chunks) │     │
│  └──────────┘  └──────────┘  └────────────────────────┘     │
│                                                              │
│  Mobile → Desktop (HTTP Upload):                            │
│  ┌──────────┐  ┌──────────────────┐  ┌─────────────────┐   │
│  │  <input  │─►│  POST /api/upload │─►│  Save to disk   │   │
│  │  file>   │  │  multipart/form  │  │  Notify other   │   │
│  └──────────┘  └──────────────────┘  │  devices         │   │
│                                      └─────────────────┘   │
│                                                              │
│  Desktop → Mobile (HTTP Download):                          │
│  ┌──────────┐  ┌──────────────────────┐  ┌──────────────┐  │
│  │  WS:     │─►│  GET /api/download/id│─►│  Browser     │  │
│  │  notify  │  │  Content-Disposition │  │  saves file  │  │
│  └──────────┘  └──────────────────────┘  └──────────────┘  │
│                                                              │
│  Features:                                                   │
│  - Chunk size: 64KB (TCP) / HTTP streaming (Web)            │
│  - Progress tracking via WebSocket                           │
│  - SHA-256 checksum verification                             │
│  - Max file size configurable (default: 2GB)                │
└──────────────────────────────────────────────────────────────┘
```

---

### 3.9 Desktop UX Layer

Komponen tambahan untuk pengalaman desktop yang lengkap (ditambahkan di v0.5.0):

#### System Tray / Menu Bar

```
┌──────────────────────────────────────────────────┐
│              TrayService                         │
│                                                  │
│  Platform:                                       │
│  - Linux  : AppIndicator3 (libayatana)           │
│  - macOS  : NSStatusBar (menu bar)               │
│  - Windows: Win32 Shell_NotifyIcon               │
│                                                  │
│  Icon:                                           │
│  - Linux/Windows : app_icon.png / app_icon.ico   │
│  - macOS         : app_icon.png (template image) │
│                                                  │
│  Behavior:                                       │
│  - Close window → hide to tray (app stays alive) │
│  - Left click (Linux/Win) → toggle show/hide     │
│  - Left click (macOS) → show context menu        │
│  - Right click → context menu                    │
│                                                  │
│  Context Menu:                                   │
│  ┌─────────────────────┐                         │
│  │ Show CopyPaste      │ → windowManager.show()  │
│  │ ─────────────────── │                         │
│  │ Quit                │ → windowManager.destroy()│
│  └─────────────────────┘                         │
└──────────────────────────────────────────────────┘
```

**macOS note:** `AppDelegate.applicationShouldTerminateAfterLastWindowClosed` di-set `false` agar app tidak terminate saat window ditutup.

#### Desktop Notifications

```
┌──────────────────────────────────────────────────┐
│              NotificationService                 │
│              (local_notifier)                    │
│                                                  │
│  Trigger → Notification:                         │
│                                                  │
│  Clipboard received from remote device:          │
│    Title : "Clipboard from <device>"             │
│    Body  : Preview 60 chars pertama              │
│    When  : sourceId != null (bukan local)        │
│                                                  │
│  File transfer complete (received):              │
│    Title : "File received"                       │
│    Body  : "<filename> from <device>"            │
│                                                  │
│  File transfer complete (sent):                  │
│    Title : "File sent"                           │
│    Body  : "<filename>"                          │
│                                                  │
│  Platform: Linux (libnotify), macOS, Windows     │
└──────────────────────────────────────────────────┘
```

#### Settings Screen

```
┌──────────────────────────────────────────────────┐
│              Settings Screen                     │
│              (gear icon di AppBar)               │
│                                                  │
│  Sections:                                       │
│  ┌──────────────────────────────────────────┐    │
│  │ Device Info (read-only)                  │    │
│  │  - Device Name (from system hostname)    │    │
│  │  - Device ID (copyable)                  │    │
│  │  - Local IP, TCP Port, Web URL           │    │
│  └──────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────┐    │
│  │ Appearance                               │    │
│  │  - Theme toggle: Light / System / Dark   │    │
│  │  - Persisted via SharedPreferences       │    │
│  └──────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────┐    │
│  │ Paired Desktops                          │    │
│  │  - List dari SecureStorage               │    │
│  │  - Unpair button per device              │    │
│  └──────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────┐    │
│  │ Mobile Web Sessions                      │    │
│  │  - Active sessions list                  │    │
│  │  - Revoke per session / revoke all       │    │
│  └──────────────────────────────────────────┘    │
│  ┌──────────────────────────────────────────┐    │
│  │ Data                                     │    │
│  │  - Clear clipboard history               │    │
│  │  - Clear transfer history                │    │
│  └──────────────────────────────────────────┘    │
│  App version (CopyPaste vX.Y.Z)                  │
└──────────────────────────────────────────────────┘
```

---

## 4. Data Flow

### 4.1 Desktop ↔ Desktop: Clipboard Auto-Sync

```
Desktop A                                     Desktop B
   │                                              │
   │  (Already paired via PIN — persistent        │
   │   TCP connection with HKDF session key)      │
   │                                              │
   │  1. User copies text                         │
   │  ClipboardMonitor detects change (500ms poll)│
   │                                              │
   │  2. Create Message.text() with HMAC          │
   │                                              │
   │  3. Send via PeerConnection (already open)   │
   │  [12B Header][JSON Meta + HMAC][Text Payload]│
   │  ──────────────────────────────────────►     │
   │                                              │
   │                     4. Verify HMAC           │
   │                     5. Write to clipboard    │
   │                     6. Notify web clients    │
   │                     ◄──────────────────      │
```

### 4.2 Mobile → Desktop: Send Clipboard Text

```
Mobile Browser                                Desktop App
   │                                              │
   │  1. User paste text ke textarea              │
   │  2. Tap "Send" button                        │
   │                                              │
   │  3. WebSocket: clipboard:send                │
   │  ════════════════════════════════════►        │
   │  { event: "clipboard:send",                  │
   │    data: { content: "...", type: "text" }}   │
   │                                              │
   │                     4. Write to OS clipboard  │
   │                     5. Forward to paired      │
   │                        desktops (TCP)         │
   │                     6. Notify other web       │
   │                        clients (WS)           │
   │                                              │
   │  7. WebSocket: clipboard:update (confirm)    │
   │  ◄════════════════════════════════════        │
```

### 4.3 Desktop → Mobile: Receive Clipboard Update

```
Desktop App                                Mobile Browser
   │                                              │
   │  1. Clipboard changed (local or from         │
   │     another desktop)                         │
   │                                              │
   │  2. WebSocket: clipboard:update              │
   │  ════════════════════════════════════►        │
   │  { event: "clipboard:update",                │
   │    data: { content: "...", source: "..." }}  │
   │                                              │
   │                     3. Display in UI         │
   │                     4. User tap "Copy"       │
   │                     5. navigator.clipboard   │
   │                        .writeText(content)   │
   │                     6. User can paste in     │
   │                        any mobile app        │
```

### 4.4 Mobile → Desktop: File Upload

```
Mobile Browser                                Desktop App
   │                                              │
   │  1. User tap "Send File"                     │
   │  2. <input type="file"> picker               │
   │  3. File selected                            │
   │                                              │
   │  4. POST /api/upload                         │
   │     Content-Type: multipart/form-data        │
   │  ──────────────────────────────────────►     │
   │                                              │
   │  5. WebSocket: transfer:progress             │
   │  ◄════════════════════════════════════        │
   │  (progress updates during upload)            │
   │                                              │
   │                     6. Save file to disk     │
   │                     7. Notify paired desktops│
   │                                              │
   │  8. WebSocket: transfer:complete             │
   │  ◄════════════════════════════════════        │
```

### 4.5 Desktop → Mobile: File Download

```
Desktop App                                Mobile Browser
   │                                              │
   │  1. User selects file + target mobile        │
   │     (atau file masuk dari desktop lain)       │
   │                                              │
   │  2. WebSocket: transfer:incoming             │
   │  ════════════════════════════════════►        │
   │  { filename, size, mime_type }               │
   │                                              │
   │                     3. Show notification     │
   │                     4. User tap "Download"   │
   │                                              │
   │  5. GET /api/download/:id                    │
   │  ◄──────────────────────────────────────     │
   │                                              │
   │  6. Response with file stream                │
   │     Content-Disposition: attachment          │
   │  ──────────────────────────────────────►     │
   │                                              │
   │                     7. Browser download       │
   │                        dialog / auto-save    │
```

---

## 5. Project Structure

```
copy-paste/
│
├── lib/                                       # Flutter Desktop App
│   ├── main.dart                              # App entry point
│   │
│   ├── core/                                  # Core networking & protocol
│   │   ├── discovery/
│   │   │   └── discovery_service.dart         # mDNS advertise & browse (macOS)
│   │   ├── network/
│   │   │   ├── tcp_server.dart                # TCP server — accepts sockets
│   │   │   ├── tcp_client.dart                # TCP client — connect to peer
│   │   │   └── peer_connection.dart           # Persistent TCP connection with
│   │   │                                      #   message framing & buffer management
│   │   ├── protocol/
│   │   │   ├── header.dart                    # 12-byte binary header (v2)
│   │   │   ├── message.dart                   # Message frame: serialize/deserialize
│   │   │   └── message_type.dart              # Enum: text, file, pairing, disconnect
│   │   ├── encryption/                        # (Planned: X25519 + AES-256-GCM)
│   │   └── web_server/
│   │       └── http_server.dart               # Embedded HTTP + WebSocket server
│   │                                          #   PIN auth, file upload/download,
│   │                                          #   session token management
│   │
│   ├── services/                              # Business logic
│   │   ├── app_service.dart                   # Main orchestrator — wires everything
│   │   ├── clipboard_service.dart             # Clipboard monitor (500ms polling)
│   │   ├── pairing_service.dart               # PIN-based pairing + HMAC-SHA256
│   │   │                                      #   + HKDF session key derivation
│   │   ├── file_transfer_service.dart         # Chunked file transfer (64KB)
│   │   │                                      #   + SHA-256 checksum verification
│   │   ├── secure_storage_service.dart        # Encrypted storage (Keychain/libsecret/DPAPI)
│   │   │                                      #   paired peers + session keys
│   │   ├── tray_service.dart                  # System tray / menu bar (Linux/macOS/Windows)
│   │   └── notification_service.dart          # Desktop notifications (local_notifier)
│   │
│   ├── models/                                # Data models
│   │   ├── device.dart                        # Device info + PairingState enum
│   │   ├── clipboard_item.dart                # Clipboard entry (text + timestamp)
│   │   └── transfer_task.dart                 # Transfer state (progress, status)
│   │
│   ├── providers/                             # State management (Riverpod)
│   │   ├── device_provider.dart               # Desktop + mobile device list
│   │   ├── clipboard_provider.dart            # Clipboard history (max 50 items)
│   │   ├── transfer_provider.dart             # File transfer progress tracking
│   │   ├── web_client_provider.dart           # Connected web clients
│   │   └── theme_provider.dart                # ThemeMode (Light/System/Dark) + SharedPrefs
│   │
│   ├── screens/                               # Desktop UI
│   │   ├── home/
│   │   │   ├── home_screen.dart               # 3 tabs: Devices, Clipboard, Files
│   │   │   └── widgets/
│   │   │       ├── device_list.dart           # Device list + "Connect" FAB
│   │   │       ├── device_tile.dart           # Device with pairing state dot
│   │   │       ├── clipboard_history.dart     # Clipboard history list
│   │   │       ├── transfer_list.dart         # Transfer progress with bars
│   │   │       ├── connect_dialog.dart        # IP + port input
│   │   │       ├── pin_dialog.dart            # PIN display (responder) +
│   │   │       │                              #   PIN input (initiator)
│   │   │       └── qr_code_panel.dart         # QR code for mobile connection
│   │   └── settings/
│   │       └── settings_screen.dart           # Settings: device info, theme, paired
│   │                                          #   devices, web sessions, data
│   │
│   └── utils/
│       ├── constants.dart                     # Protocol version, ports, timeouts
│       ├── logger.dart                        # Colored log output with tags
│       ├── network_utils.dart                 # Get local IP addresses
│       └── mime_parser.dart                   # Multipart/form-data parser
│
├── web_client/                                # Mobile Web SPA
│   ├── index.html                             # Entry point + PIN overlay div
│   ├── css/
│   │   └── style.css                          # Mobile-first, dark/light theme
│   ├── js/
│   │   ├── app.js                             # Main logic + auth event wiring
│   │   ├── auth.js                            # PIN verify + session token cache
│   │   ├── websocket.js                       # WebSocket + auto-reconnect + token
│   │   ├── clipboard.js                       # Clipboard read/write operations
│   │   ├── transfer.js                        # File upload (XHR) + download
│   │   └── ui.js                              # DOM updates + PIN overlay
│   ├── sw.js                                  # Service worker (PWA installability)
│   └── assets/
│       ├── manifest.json                      # PWA manifest (icons, display, theme)
│       ├── icon-192.png                       # PWA icon 192x192
│       └── icon-512.png                       # PWA icon 512x512
│
├── scripts/                                   # Build & packaging scripts
│   ├── build-deb.sh                           # Linux .deb package builder
│   ├── build-dmg.sh                           # macOS .dmg package builder
│   ├── build-windows.ps1                      # Windows .zip + installer builder
│   └── installer.iss                          # Inno Setup script (Windows .exe)
│
├── docs/
│   ├── ARCHITECTURE.md                        # This file
│   ├── DEVELOPMENT-PHASES.md                  # Development roadmap & progress
│   └── WINDOWS-BUILD-GUIDE.md                 # Windows build prerequisites & steps
│
├── pubspec.yaml                               # Flutter dependencies
├── LICENSE                                    # MIT License
└── README.md
```

---

## 6. Dependencies

### Flutter Desktop App

| Package | Fungsi |
|---------|--------|
| `nsd` | mDNS/DNS-SD service discovery (macOS only) |
| `flutter_riverpod` | State management |
| `cryptography` | HMAC-SHA256, HKDF, SHA-256 (future: X25519, AES-256-GCM) |
| `file_picker` | Pilih file untuk transfer |
| `path_provider` | Lokasi save file |
| `qr_flutter` | Generate QR code untuk mobile connection |
| `shared_preferences` | Persisted settings |
| `uuid` | Generate unique IDs |
| `freezed` | Immutable data classes |
| `json_serializable` | JSON serialization |
| `local_notifier` | Desktop notifications (Linux/macOS/Windows) |
| `tray_manager` | System tray / menu bar icon (Linux/macOS/Windows) |
| `window_manager` | Window control (show/hide/prevent-close) |
| `package_info_plus` | Read app version from pubspec.yaml at runtime |
| `shelf` | HTTP server framework |
| `shelf_web_socket` | WebSocket support untuk shelf |

### Web Client (Mobile SPA)

| Teknologi | Detail |
|-----------|--------|
| Vanilla JavaScript | Tanpa framework — fast load, zero build step |
| HTML5 | Semantic HTML, responsive, PIN overlay |
| CSS3 | Mobile-first, minimal, dark/light theme (`prefers-color-scheme`) |
| Clipboard API | `navigator.clipboard.readText()` / `writeText()` |
| WebSocket API | Native browser WebSocket + auto-reconnect |
| File API | `<input type="file">` + XHR upload with progress |
| localStorage | Session token caching (`cp_session_token`) |
| Service Worker | `sw.js` — network-first strategy, enables PWA install prompt |
| PWA | `manifest.json` + icons — installable via Add to Home Screen (Android/iOS) |

**Web client modules:**
| File | Fungsi |
|------|--------|
| `app.js` | Main logic, event wiring, auth event handling |
| `auth.js` | PIN verification, HMAC fallback, session token management |
| `websocket.js` | WebSocket connection + auto-reconnect + token param |
| `clipboard.js` | Clipboard read/write operations |
| `transfer.js` | File upload (XHR with progress) + download |
| `ui.js` | DOM manipulation, PIN overlay, status updates |

**Total web client size: < 50KB** (tanpa framework, tanpa build tool).

---

## 7. Security Model

### Threat Model (Local Network)

| Threat | Mitigasi |
|--------|----------|
| Eavesdropping (sniffing LAN) | Desktop↔Desktop: HMAC-SHA256 auth. Desktop↔Mobile: self-signed TLS (HTTPS + WSS) |
| Man-in-the-Middle | Desktop pairing: PIN + HMAC verification. Mobile: QR code URL + PIN |
| Unauthorized device | Desktop: explicit PIN pairing + persistent session key. Mobile: PIN + session token |
| Replay attack | Unique nonce per pairing (TCP), session token expiry 24h (Web) |
| Clipboard data leakage | Data hanya lokal, in-memory history (hilang saat restart), no cloud |
| Rogue web client | PIN auth + session token, revoke per-session dari Settings, auto-expire 24h |
| Key leakage | Session key disimpan di Keychain (macOS) / libsecret (Linux) / DPAPI (Windows) |

### Authentication Flow

**Desktop ↔ Desktop (Implemented):**
1. Initiator sends `pairRequest` with device info
2. Responder generates 6-digit PIN + random nonce, shows PIN to user
3. Responder sends `pairChallenge(nonce)` to initiator
4. User enters PIN on initiator device
5. Initiator computes `HMAC-SHA256(PIN, nonce)` and pre-derives session key via `HKDF-SHA256(PIN + nonce)`
6. Initiator sends `pairResponse(hmac)` to responder
7. Responder verifies HMAC, derives same session key
8. Responder sends `pairConfirm(success)` → paired!
9. All subsequent messages include HMAC authentication using session key

**Desktop ↔ Mobile Web (Implemented):**
1. Mobile connects via WebSocket (QR code URL)
2. Server generates 6-digit PIN + nonce, sends `auth:challenge` event
3. Desktop shows PIN to user via dialog
4. User enters PIN on mobile browser
5. Mobile sends PIN directly (fallback for HTTP — Web Crypto unavailable)
6. Server verifies PIN match → generates session token
7. Server sends `auth:success` with session token
8. Mobile saves token to `localStorage` key `cp_session_token`
9. On reconnect: token sent via WebSocket query param `?token=...`
10. Server validates token → auto-authenticates (no PIN re-entry)

### Key Management (Current)

- Session keys derived via HKDF-SHA256 (PIN + nonce as input)
- Session keys stored in-memory only (lost on app restart)
- Session tokens stored in server-side Set (in-memory)
- Mobile tokens cached in browser localStorage

### Key Management (Planned — Phase 5)

- Desktop keypair via X25519 ECDH for forward secrecy
- AES-256-GCM encryption on all TCP messages
- Persistent key storage:
  - macOS: Keychain
  - Linux: libsecret / encrypted file
  - Windows (v2): DPAPI / Windows Credential Store
- Self-signed TLS for HTTPS web server
- Session token expiry + revocation

---

## 8. Platform-Specific Considerations

### Desktop Platforms (v1: macOS & Linux)

#### macOS
- Local Network permission (macOS 11+)
- App Sandbox: `com.apple.security.network.server` entitlement
- Menu bar icon untuk quick access
- Clipboard: `NSPasteboard` + polling (`changeCount`)
- Distribusi: .dmg package (`scripts/build-dmg.sh`) dengan code signing
- Notarization required untuk distribusi publik

#### Linux
- mDNS: `avahi-daemon` harus terinstall
- Clipboard: X11 (`xclip`/`xsel`) dan Wayland (`wl-clipboard`)
- System tray: `StatusNotifierItem` / `AppIndicator`
- Distribusi: .deb package (`scripts/build-deb.sh`), future: AppImage, Flatpak

#### Windows (v2 - Future)
- Firewall: prompt untuk allow incoming TCP + HTTP connection
- System tray icon untuk background operation
- Clipboard listener via Win32 API (`AddClipboardFormatListener`)
- Startup: optional autostart via registry

### Mobile Browser Considerations

#### Browser Clipboard API
- `navigator.clipboard.writeText()` — membutuhkan user gesture (tap)
- `navigator.clipboard.readText()` — membutuhkan user gesture + permission
- Beberapa browser (Firefox mobile) memiliki policy lebih ketat
- Fallback: `document.execCommand('copy')` untuk browser lama

#### Browser Compatibility Target
| Browser | Minimum Version |
|---------|----------------|
| Chrome Android | 66+ |
| Safari iOS | 13.4+ |
| Firefox Android | 63+ |
| Samsung Internet | 12+ |

#### PWA Support (Optional)
- `manifest.json` untuk "Add to Homescreen" experience
- Service worker untuk offline shell (tapi butuh koneksi ke desktop untuk fungsi)
- Membuat experience terasa seperti native app

---

## 9. Web Client UI Design

### Mobile-First Layout

```
┌─────────────────────────┐
│  CopyPaste        ≡     │  ← Header + menu
├─────────────────────────┤
│                         │
│  ┌───────────────────┐  │
│  │  📋 Clipboard     │  │  ← Tab active
│  │  📁 Files  👥 Dev │  │
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │ Paste text here   │  │  ← Text input area
│  │ or tap to read    │  │
│  │ clipboard         │  │
│  │                   │  │
│  └───────────────────┘  │
│  [ Send to Desktop  📤] │  ← Action button
│                         │
│  ── History ──────────  │
│                         │
│  ┌───────────────────┐  │
│  │ "Hello world"     │  │
│  │ From: macOS        │  │  ← Clipboard history items
│  │ 2 min ago  [Copy] │  │     Tap "Copy" to copy
│  └───────────────────┘  │
│                         │
│  ┌───────────────────┐  │
│  │ "SELECT * FROM.." │  │
│  │ From: Linux       │  │
│  │ 5 min ago  [Copy] │  │
│  └───────────────────┘  │
│                         │
│  [ 📎 Send File     ]  │  ← File transfer button
│                         │
└─────────────────────────┘
```

---