# CopyPaste

Open-source, self-hosted clipboard sharing and file transfer tool across devices over local network (P2P). No cloud, no server, no internet required.

**Copy on one device, paste on another.**

## How It Works

```
Desktop A (Flutter)    TCP (P2P)    Desktop B (Flutter)
┌─────────────────┐  ◄══════════►  ┌─────────────────┐
│  Auto clipboard  │   PIN-based    │  Auto clipboard  │
│  monitoring      │   pairing +    │  monitoring      │
│  TCP P2P sync    │   HMAC auth    │  TCP P2P sync    │
│  Web server      │               │  Web server      │
└────────┬────────┘               └────────┬────────┘
         │ HTTP + WebSocket                 │
         │ PIN auth                         │
         ▼                                  ▼
┌──────────────┐                   ┌──────────────┐
│  Mobile A    │                   │  Mobile B    │
│  (Browser)   │                   │  (Browser)   │
│  Scan QR     │                   │  Scan QR     │
│  Copy/paste  │                   │  Copy/paste  │
│  File upload │                   │  File upload │
└──────────────┘                   └──────────────┘
```

- **Desktop ↔ Desktop**: Auto clipboard sync via TCP with PIN-based pairing & HMAC authentication
- **Desktop ↔ Mobile**: Manual clipboard via browser (WebSocket) with PIN verification
- **File Transfer**: Desktop↔Desktop (chunked TCP), Mobile↔Desktop (HTTP upload/download)
- Mobile access via QR code scan — no app install needed

## Features

- **Clipboard Sync** — Auto-sync clipboard between desktops, manual sync with mobile browsers
- **File Transfer** — Send files between any connected devices with SHA-256 checksum verification
- **PIN-based Security** — 6-digit PIN pairing with HMAC-SHA256 authentication and HKDF session keys
- **Session Caching** — Mobile web clients stay authenticated across refreshes (token in localStorage)
- **Device Discovery** — QR code for mobile, manual IP connection for desktops
- **Clipboard History** — Last 50 items synced across all connected devices
- **Dark/Light Theme** — Web client follows system preference
- **Zero Install Mobile** — Scan QR code, open browser, start using

## Supported Platforms

| Platform | Type | Status |
|----------|------|--------|
| Linux | Desktop app (Flutter) | v1 - Active |
| macOS | Desktop app (Flutter) | v1 - Active |
| Android | Web client (Browser) | v1 - Active |
| iOS | Web client (Browser) | v1 - Active |
| Windows | Desktop app (Flutter) | v2 - Planned |

## Prerequisites

### Linux

```bash
# Flutter SDK
# Download from https://docs.flutter.dev/get-started/install/linux/desktop
cd ~
curl -LO https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.41.5-stable.tar.xz
tar xf flutter_linux_3.41.5-stable.tar.xz
echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc

# System dependencies
sudo apt install -y cmake ninja-build pkg-config libgtk-3-dev libnotify-dev clang lld
```

> **Note:** Flutter via `snap` is NOT recommended due to AppArmor confinement issues. Use manual install.

### macOS

```bash
# Flutter SDK (via Homebrew)
brew install flutter

# Xcode command line tools
xcode-select --install
```

## Getting Started

### 1. Clone the repository

```bash
git clone https://github.com/your-username/copy-paste.git
cd copy-paste
```

### 2. Install dependencies

```bash
flutter pub get
```

### 3. Run in debug mode

```bash
# Linux
flutter run -d linux

# macOS
flutter run -d macos
```

### 4. Connect mobile device

1. Make sure your phone and computer are on the **same WiFi network**
2. The app shows a URL in the top bar (e.g. `http://192.168.1.100:8080`)
3. Click the **QR code icon** in the app bar
4. **Scan the QR code** with your phone camera
5. Enter the **6-digit PIN** shown on the desktop app
6. Start copying and transferring files!

### 5. Connect another desktop

1. On Desktop B, click **"Connect to Desktop"** button
2. Enter Desktop A's **IP address** and **TCP port** (shown in app bar)
3. A **6-digit PIN** appears on Desktop A — enter it on Desktop B
4. Once paired, clipboards sync automatically between both desktops

## Usage

### Clipboard Sync (Desktop ↔ Desktop)

1. Pair two desktops using IP + PIN (one-time setup)
2. Copy any text on either desktop — it auto-syncs to the other
3. All paired desktops stay in sync via persistent TCP connections

### Clipboard Sync (Desktop ↔ Mobile)

1. Copy text on desktop → appears in mobile browser's clipboard history → tap **"Copy"**
2. Paste text in mobile web client → tap **"Send to Desktop"** → written to desktop clipboard

### File Transfer

**Desktop → Desktop:**
1. Go to the **Files** tab
2. Tap the **+** button to pick a file
3. File is sent to all paired desktops (chunked, with SHA-256 verification)

**Mobile → Desktop:**
1. Tap **"Send File"** in the web client
2. Pick a file → uploaded via HTTP multipart
3. File appears on the desktop

**Desktop → Mobile:**
1. Files received on desktop are available for mobile download
2. Tap **"Download"** in the web client

### Multiple Devices

Multiple phones/tablets can connect simultaneously. Multiple desktops can be paired. Each device appears in the device list with its name and connection status.

## Build for Release

### Linux

```bash
# Build Flutter release
flutter build linux --release

# Or build .deb package
chmod +x scripts/build-deb.sh
./scripts/build-deb.sh

# Install .deb
sudo dpkg -i build/copypaste_0.1.0_amd64.deb
```

### macOS

```bash
# Build Flutter release
flutter build macos --release

# Or build .dmg package (must run on macOS)
chmod +x scripts/build-dmg.sh
./scripts/build-dmg.sh

# Output: build/CopyPaste_0.1.0.dmg
```

## Project Structure

```
copy-paste/
├── lib/                          # Flutter desktop app (Dart)
│   ├── main.dart                 # App entry point
│   ├── core/
│   │   ├── discovery/            # mDNS discovery (macOS)
│   │   ├── network/
│   │   │   ├── tcp_server.dart   # TCP server for incoming connections
│   │   │   ├── tcp_client.dart   # TCP client for outgoing connections
│   │   │   └── peer_connection.dart  # Persistent TCP connection with message framing
│   │   ├── protocol/
│   │   │   ├── header.dart       # 12-byte binary header (v2)
│   │   │   ├── message.dart      # Message serialization/deserialization
│   │   │   └── message_type.dart # Message type enum (text, file, pairing, etc.)
│   │   └── web_server/
│   │       └── http_server.dart  # Embedded HTTP + WebSocket server with PIN auth
│   ├── models/
│   │   ├── device.dart           # Device info + pairing state
│   │   ├── clipboard_item.dart   # Clipboard entry
│   │   └── transfer_task.dart    # File transfer state
│   ├── providers/                # Riverpod state management
│   │   ├── device_provider.dart
│   │   ├── clipboard_provider.dart
│   │   ├── transfer_provider.dart
│   │   └── web_client_provider.dart
│   ├── screens/home/
│   │   ├── home_screen.dart      # Main screen (3 tabs: Devices, Clipboard, Files)
│   │   └── widgets/
│   │       ├── device_list.dart  # Device list with connect button
│   │       ├── device_tile.dart  # Device tile with pairing state indicator
│   │       ├── clipboard_history.dart
│   │       ├── transfer_list.dart    # File transfer progress list
│   │       ├── connect_dialog.dart   # IP + port input dialog
│   │       ├── pin_dialog.dart       # PIN display/input dialogs
│   │       └── qr_code_panel.dart
│   ├── services/
│   │   ├── app_service.dart          # Main orchestrator
│   │   ├── clipboard_service.dart    # Clipboard monitoring (500ms polling)
│   │   ├── pairing_service.dart      # PIN-based pairing + HMAC + HKDF
│   │   └── file_transfer_service.dart # Chunked file transfer (64KB)
│   └── utils/
│       ├── constants.dart        # Protocol version, ports, timeouts
│       ├── logger.dart
│       ├── network_utils.dart    # Local IP detection
│       └── mime_parser.dart      # Multipart form-data parser
├── web_client/                   # Mobile web SPA (HTML/CSS/JS)
│   ├── index.html                # Single page entry + PIN overlay
│   ├── css/style.css             # Responsive mobile-first CSS
│   ├── js/
│   │   ├── app.js                # Main logic + auth event handling
│   │   ├── auth.js               # PIN verification + session token caching
│   │   ├── websocket.js          # WebSocket with auto-reconnect + token
│   │   ├── clipboard.js          # Clipboard read/write
│   │   ├── transfer.js           # File upload/download via HTTP
│   │   └── ui.js                 # DOM manipulation + PIN overlay
│   └── assets/manifest.json      # PWA manifest
├── scripts/
│   ├── build-deb.sh              # Linux .deb package builder
│   └── build-dmg.sh              # macOS .dmg package builder
├── docs/
│   ├── ARCHITECTURE.md           # Full architecture documentation
│   └── DEVELOPMENT-PHASES.md     # Development roadmap & progress
├── pubspec.yaml                  # Flutter dependencies
└── LICENSE                       # MIT License
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full architecture documentation.

**Key design decisions:**
- **Hybrid architecture**: Desktop app (Flutter) + Mobile web client (vanilla JS)
- **P2P local network**: No cloud relay, all communication stays on LAN
- **Desktop as hub**: Each desktop runs an embedded HTTP + WebSocket server
- **Mobile via browser**: Scan QR code, enter PIN, no app install needed
- **Privacy first**: Data never leaves your local network

## Development

See [docs/DEVELOPMENT-PHASES.md](docs/DEVELOPMENT-PHASES.md) for development progress and roadmap.

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Desktop app | Flutter 3.41+ (Dart) |
| State management | Riverpod |
| Desktop ↔ Desktop | TCP socket + binary protocol v2 (12-byte header) |
| Desktop ↔ Mobile | HTTP + WebSocket (JSON) |
| Security (Desktop) | PIN-based pairing + HMAC-SHA256 + HKDF session keys |
| Security (Mobile) | 6-digit PIN verification + session token caching |
| File transfer | Chunked TCP (64KB) + HTTP multipart + SHA-256 checksum |
| Device discovery | mDNS/DNS-SD via `nsd` (macOS), manual IP (Linux) |
| Web client | Vanilla HTML/CSS/JS (< 50KB, no framework) |
| Packaging | .deb (Linux), .dmg (macOS) |

### Running Tests

```bash
flutter test
```

## Troubleshooting

### Mobile can't connect

- Ensure phone and computer are on the **same WiFi/LAN**
- Check if a firewall is blocking the port (default: 8080-8099)
- On Linux: `sudo ufw allow 8080:8099/tcp`
- Try accessing the URL directly in the mobile browser

### PIN verify not working on mobile

- The web client falls back to direct PIN verification on HTTP (non-HTTPS) connections
- This is expected — Web Crypto API (`crypto.subtle`) is only available on HTTPS/localhost
- PIN still works securely over local network

### Desktop-to-desktop connection fails

- Ensure both desktops are on the same network
- Check the TCP port shown in the app bar of the target desktop
- Make sure firewall allows the TCP port (default: dynamic)
- Use manual IP connection as alternative to mDNS

### Flutter snap issues (Linux)

Don't use `snap install flutter`. The snap version has AppArmor confinement issues. Use manual SDK install.

### mDNS not working on Linux

The `nsd` Flutter plugin does not support Linux desktop. Use **manual IP connection** to pair desktops on Linux. Mobile devices connect via QR code regardless.

## License

MIT License — see [LICENSE](LICENSE)
