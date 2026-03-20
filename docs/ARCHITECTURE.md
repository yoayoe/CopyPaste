# CopyPaste - Architecture Document

## 1. Overview

**CopyPaste** adalah open-source, self-hosted, cross-platform clipboard sharing dan file transfer tool yang bekerja melalui local network (P2P). Copy di satu device, paste di device lain — tanpa cloud, tanpa server, tanpa internet.

### Arsitektur Hybrid

CopyPaste menggunakan **arsitektur hybrid** dengan dua tipe client:

| Tipe | Platform | Teknologi | Kapabilitas | Status |
|------|----------|-----------|-------------|--------|
| **Desktop App** | macOS, Linux | Flutter | Full-featured: auto clipboard sync, background service, file transfer, mDNS discovery, **embedded web server** | **v1 (Current Focus)** |
| **Web Client** | Android, iOS (any mobile browser) | HTML/CSS/JS (SPA) | Manual clipboard (browser limitation), file transfer, **no install required** | **v1 (Current Focus)** |
| **Desktop App** | Windows | Flutter | Same as macOS/Linux | **v2 (Future)** |
| **Mobile App** | Android, iOS | Flutter | Full-featured native mobile app dengan auto clipboard sync | **v3 (Future)** |

Mobile device cukup **scan QR code** dari desktop app → buka browser → langsung pakai.

### Roadmap

| Versi | Scope | Deskripsi |
|-------|-------|-----------|
| **v1** | macOS + Linux + Web Client | Desktop app untuk macOS & Linux dengan embedded web server. Mobile akses via browser. |
| **v2** | + Windows | Tambah Windows desktop support. |
| **v3** | + Mobile Native App | Flutter mobile app (Android/iOS) untuk full-featured experience di mobile. |

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
│  │   (macOS)          │  mDNS       │   (Linux)          │      │
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
│  │  - Binary protocol (custom frame)                       │  │
│  │  - Auto clipboard sync                                  │  │
│  │  - Chunked file transfer                                │  │
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

**QR Code Connection Flow:**
```
Desktop App                              Mobile Phone
    │                                        │
    │  1. Generate QR code containing:       │
    │     http://<local-ip>:<port>?token=xyz │
    │     (tampil di desktop screen)         │
    │                                        │
    │                          2. Scan QR    │
    │                          3. Open URL   │
    │                             in browser │
    │                                        │
    │  4. Serve Web SPA     ◄────────────────│  GET /
    │  ────────────────────►                 │
    │                                        │
    │  5. WebSocket connect ◄════════════════│  WS /ws?token=xyz
    │  ═════════════════════►                │
    │                                        │
    │  6. Validate token                     │
    │  7. Add to connected devices           │
    │                                        │
    │  ◄──── Real-time sync active ────►     │
    │                                        │
```

**Token Security:**
- QR code berisi one-time token yang expire setelah 5 menit atau setelah digunakan
- Setelah connect pertama, server issue session token (disimpan di browser localStorage)
- Session token valid selama device masih di jaringan yang sama

---

### 3.4 Protocol Layer

Dua format protocol berbeda untuk dua channel komunikasi:

#### 3.4.1 Binary Protocol (Desktop ↔ Desktop via TCP)

```
┌─────────────────────────────────────────────────┐
│           Binary Message Frame (TCP)            │
│                                                 │
│  ┌──────────┬──────────┬───────────────────┐    │
│  │  Header  │  Meta    │     Payload       │    │
│  │  8 bytes │  N bytes │     M bytes       │    │
│  └──────────┴──────────┴───────────────────┘    │
│                                                 │
│  Header:                                        │
│    - magic (2 bytes): 0xCP                      │
│    - version (1 byte): protocol version         │
│    - type (1 byte): message type                │
│    - meta_length (4 bytes): ukuran metadata     │
│                                                 │
│  Meta (JSON):                                   │
│    - filename, mime_type, size, checksum, dll    │
│                                                 │
│  Payload:                                       │
│    - raw bytes (text content / file bytes)       │
└─────────────────────────────────────────────────┘
```

**Message Types (TCP):**

| Type Code | Nama | Deskripsi |
|-----------|------|-----------|
| `0x01` | `TEXT` | Clipboard text content |
| `0x02` | `IMAGE` | Clipboard image |
| `0x03` | `FILE` | File transfer (single file) |
| `0x04` | `FILES` | Multiple files transfer |
| `0x05` | `PING` | Heartbeat / connectivity check |
| `0x06` | `PONG` | Response to PING |
| `0x07` | `ACK` | Transfer acknowledgement |
| `0x08` | `REJECT` | Transfer ditolak |

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

### 3.5 Encryption Layer

```
┌──────────────────────────────────────────────────────────────┐
│                    Encryption Layer                          │
│                                                              │
│  Desktop ↔ Desktop (TCP):                                   │
│  ┌──────────┐   PIN/QR Code   ┌──────────┐                  │
│  │ Desktop A│ ◄──────────────► │ Desktop B│                  │
│  │          │  Key Exchange    │          │                  │
│  │          │  (X25519 ECDH)   │          │                  │
│  └──────────┘                  └──────────┘                  │
│       │                             │                        │
│       ▼                             ▼                        │
│  AES-256-GCM encrypt ────────► AES-256-GCM decrypt          │
│                                                              │
│  Desktop ↔ Mobile (WebSocket):                              │
│  ┌──────────┐   QR Code       ┌──────────┐                  │
│  │ Desktop  │ ──────────────► │  Mobile  │                  │
│  │          │  URL + token    │  Browser │                  │
│  │          │                 │          │                  │
│  │  HTTPS   │ ◄═════════════► │  HTTPS   │                  │
│  │  (TLS)   │  WebSocket WSS  │  (TLS)   │                  │
│  └──────────┘                  └──────────┘                  │
│                                                              │
│  Mobile connection dilindungi oleh:                          │
│  - Self-signed TLS certificate (HTTPS)                      │
│  - One-time token dalam QR code                             │
│  - Session-based authentication                              │
└──────────────────────────────────────────────────────────────┘
```

**Desktop ↔ Desktop:**
- **Key Exchange**: X25519 ECDH
- **Symmetric Encryption**: AES-256-GCM
- **Pairing Flow**:
  1. Device A generate keypair, tampilkan PIN 6 digit
  2. Device B input PIN → exchange public keys via TCP
  3. Derive shared secret → simpan lokal
- **Per-message**: Random nonce/IV unik

**Desktop ↔ Mobile:**
- **Transport Security**: Self-signed TLS (HTTPS + WSS)
  - Desktop generate self-signed certificate saat pertama kali run
  - Browser akan tampilkan warning → user accept sekali
  - Alternatif: HTTP biasa (acceptable karena local network only)
- **Authentication**: One-time QR token + session token
- **Data in transit**: Dilindungi oleh TLS layer

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
| macOS    | `NSPasteboard` + polling (`changeCount`) | v1 |
| Linux    | `X11/Wayland clipboard` + monitoring | v1 |
| Windows  | `Win32 Clipboard API` + `AddClipboardFormatListener` | v2 (Future) |

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

## 4. Data Flow

### 4.1 Desktop ↔ Desktop: Clipboard Auto-Sync

```
Desktop A                                     Desktop B
   │                                              │
   │  1. User copies text                         │
   │  ClipboardMonitor detects change             │
   │                                              │
   │  2. Encrypt payload (AES-256-GCM)           │
   │                                              │
   │  3. TCP connect to Desktop B                 │
   │  ════════════════════════════════════►        │
   │                                              │
   │  4. Send [Header][Meta][Encrypted Payload]   │
   │  ──────────────────────────────────────►     │
   │                                              │
   │                     5. Decrypt payload       │
   │                     6. Write to clipboard    │
   │                     7. Notify web clients    │
   │                     ◄──────────────────      │
   │                                              │
   │  8. Receive ACK                              │
   │  ◄──────────────────────────────────────     │
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
│   │   │   ├── discovery_service.dart         # mDNS advertise & browse
│   │   │   └── device_resolver.dart           # Resolve device IP/port
│   │   ├── network/
│   │   │   ├── tcp_server.dart                # TCP server (desktop ↔ desktop)
│   │   │   ├── tcp_client.dart                # TCP client (desktop ↔ desktop)
│   │   │   └── connection_manager.dart        # Manage active connections
│   │   ├── protocol/
│   │   │   ├── message.dart                   # Binary message frame
│   │   │   ├── header.dart                    # Header parsing/building
│   │   │   ├── serializer.dart                # Serialize/deserialize
│   │   │   └── message_type.dart              # Message type enum
│   │   ├── encryption/
│   │   │   ├── key_exchange.dart              # X25519 ECDH
│   │   │   ├── cipher.dart                    # AES-256-GCM
│   │   │   └── key_store.dart                 # Persist paired keys
│   │   └── web_server/
│   │       ├── http_server.dart               # Embedded HTTP server
│   │       ├── websocket_handler.dart         # WebSocket connection handler
│   │       ├── routes/
│   │       │   ├── static_routes.dart         # Serve web SPA files
│   │       │   ├── upload_route.dart          # POST /api/upload
│   │       │   ├── download_route.dart        # GET /api/download/:id
│   │       │   └── status_route.dart          # GET /api/status
│   │       └── session_manager.dart           # Token & session management
│   │
│   ├── services/                              # Business logic
│   │   ├── clipboard_service.dart             # Monitor & manage clipboard
│   │   ├── transfer_service.dart              # Orchestrate send/receive
│   │   ├── file_service.dart                  # File pick, save, chunking
│   │   ├── pairing_service.dart               # Desktop pairing flow
│   │   ├── qr_service.dart                    # QR code generation for mobile
│   │   ├── notification_service.dart          # Desktop notifications
│   │   └── settings_service.dart              # App preferences
│   │
│   ├── models/                                # Data models
│   │   ├── device.dart                        # Discovered device info
│   │   ├── paired_device.dart                 # Paired desktop + shared key
│   │   ├── web_client.dart                    # Connected mobile browser
│   │   ├── clipboard_item.dart                # Clipboard entry
│   │   ├── transfer_task.dart                 # Active transfer state
│   │   └── app_settings.dart                  # User preferences
│   │
│   ├── providers/                             # State management (Riverpod)
│   │   ├── device_provider.dart               # Desktops + mobiles
│   │   ├── clipboard_provider.dart            # Clipboard history & state
│   │   ├── transfer_provider.dart             # Transfer progress & queue
│   │   └── settings_provider.dart             # App settings
│   │
│   ├── screens/                               # Desktop UI screens
│   │   ├── home/
│   │   │   ├── home_screen.dart               # Main: devices + clipboard
│   │   │   └── widgets/
│   │   │       ├── device_list.dart
│   │   │       ├── device_tile.dart
│   │   │       └── qr_code_panel.dart         # Show QR for mobile
│   │   ├── clipboard/
│   │   │   ├── clipboard_screen.dart
│   │   │   └── widgets/
│   │   │       └── clipboard_item_tile.dart
│   │   ├── transfer/
│   │   │   ├── transfer_screen.dart
│   │   │   └── widgets/
│   │   │       └── transfer_progress.dart
│   │   ├── pairing/
│   │   │   └── pairing_screen.dart            # Desktop ↔ Desktop pairing
│   │   └── settings/
│   │       └── settings_screen.dart
│   │
│   └── utils/
│       ├── constants.dart
│       ├── logger.dart
│       └── network_utils.dart                 # Get local IP, etc.
│
├── web_client/                                # Mobile Web SPA (standalone)
│   ├── index.html                             # Single HTML entry
│   ├── css/
│   │   └── style.css                          # Responsive mobile-first CSS
│   ├── js/
│   │   ├── app.js                             # Main app logic
│   │   ├── websocket.js                       # WebSocket connection manager
│   │   ├── clipboard.js                       # Clipboard read/write
│   │   ├── transfer.js                        # File upload/download
│   │   └── ui.js                              # DOM manipulation & rendering
│   └── assets/
│       ├── icons/                             # PWA icons
│       └── manifest.json                      # PWA manifest (add to homescreen)
│
├── assets/                                    # Flutter desktop assets
│   ├── icons/
│   └── images/
│
├── test/                                      # Tests
│   ├── core/
│   ├── services/
│   └── web_client/                            # Web client tests
│
├── docs/
│   └── ARCHITECTURE.md                        # This file
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
| `nsd` | mDNS/DNS-SD service discovery |
| `flutter_riverpod` | State management |
| `cryptography` | X25519, AES-256-GCM |
| `file_picker` | Pilih file untuk transfer |
| `path_provider` | Lokasi save file |
| `qr_flutter` | Generate QR code untuk mobile connection |
| `shared_preferences` | Persisted settings |
| `uuid` | Generate unique IDs |
| `freezed` | Immutable data classes |
| `json_serializable` | JSON serialization |
| `local_notifier` | Desktop notifications |
| `system_tray` | System tray / menu bar |
| `window_manager` | Window control (minimize to tray) |
| `shelf` | HTTP server framework (atau dart:io langsung) |
| `shelf_web_socket` | WebSocket support untuk shelf |

### Web Client (Mobile SPA)

| Teknologi | Detail |
|-----------|--------|
| Vanilla JavaScript | Tanpa framework — fast load, zero build step |
| HTML5 | Semantic HTML, responsive |
| CSS3 | Mobile-first, minimal, dark/light theme |
| Clipboard API | `navigator.clipboard.readText()` / `writeText()` |
| WebSocket API | Native browser WebSocket |
| File API | `<input type="file">` + `fetch()` upload |
| PWA | `manifest.json` + service worker (optional, untuk add-to-homescreen) |

**Total web client target size: < 50KB** (tanpa framework, tanpa build tool).

---

## 7. Security Model

### Threat Model (Local Network)

| Threat | Mitigasi |
|--------|----------|
| Eavesdropping (sniffing LAN) | Desktop↔Desktop: AES-256-GCM. Desktop↔Mobile: TLS (HTTPS) |
| Man-in-the-Middle | Desktop pairing: PIN verification. Mobile: QR code token |
| Unauthorized device | Desktop: explicit pairing. Mobile: one-time QR token + session |
| Replay attack | Unique nonce per message (TCP), session token expiry (Web) |
| Clipboard data leakage | Data hanya lokal, auto-expire history, no cloud |
| Rogue web client | Token-based auth, session invalidation, configurable auto-expire |

### Authentication Flow

**Desktop ↔ Desktop:**
- Explicit pairing via 6-digit PIN
- X25519 key exchange → persistent shared key
- Mutual authentication setiap connection

**Desktop ↔ Mobile (Web):**
- QR code berisi: `https://<ip>:<port>?token=<one-time-token>`
- Token expire setelah 5 menit atau first use
- Setelah connect: issue session token → localStorage
- Session valid selama configurable duration (default: 24 jam)
- Desktop UI bisa revoke session kapan saja

### Key Management

- Desktop keypair di-generate saat pertama kali run
- Private key disimpan di OS secure storage:
  - macOS: Keychain
  - Linux: libsecret / encrypted file
  - Windows (v2): DPAPI / Windows Credential Store
- Self-signed TLS cert untuk HTTPS web server
- Session tokens: random 256-bit, stored in-memory + hashed di disk

---

## 8. Platform-Specific Considerations

### Desktop Platforms (v1: macOS & Linux)

#### macOS
- Local Network permission (macOS 11+)
- App Sandbox: `com.apple.security.network.server` entitlement
- Menu bar icon untuk quick access
- Clipboard: `NSPasteboard` + polling (`changeCount`)
- Notarization required untuk distribusi

#### Linux
- mDNS: `avahi-daemon` harus terinstall
- Clipboard: X11 (`xclip`/`xsel`) dan Wayland (`wl-clipboard`)
- System tray: `StatusNotifierItem` / `AppIndicator`
- Distribusi: AppImage, Flatpak, atau .deb

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