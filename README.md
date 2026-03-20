# CopyPaste

Open-source, self-hosted clipboard sharing and file transfer tool across devices over local network (P2P). No cloud, no server, no internet required.

**Copy on one device, paste on another.**

## How It Works

```
Desktop (Flutter App)              Mobile (Browser)
┌─────────────────┐               ┌──────────────┐
│  Auto clipboard  │  WebSocket   │  Scan QR     │
│  monitoring      │◄════════════►│  Open browser │
│  TCP P2P sync    │  HTTP        │  Copy/paste  │
│  Web server      │──────────────│  File upload  │
└─────────────────┘               └──────────────┘
```

- **Desktop ↔ Desktop**: Auto clipboard sync via TCP (P2P)
- **Desktop ↔ Mobile**: Manual clipboard via browser (WebSocket)
- Mobile access via QR code scan — no app install needed

## Supported Platforms

| Platform | Type | Status |
|----------|------|--------|
| Linux | Desktop app (Flutter) | v1 - Active |
| macOS | Desktop app (Flutter) | v1 - In Progress |
| Android | Web client (Browser) | v1 - Active |
| iOS | Web client (Browser) | v1 - Active |
| Windows | Desktop app (Flutter) | v2 - Planned |

## Prerequisites

### Linux

```bash
# Flutter SDK
# Download from https://docs.flutter.dev/get-started/install/linux/desktop
# Or extract manually:
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
# Flutter SDK
# Download from https://docs.flutter.dev/get-started/install/macos/desktop
# Or via Homebrew:
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

### 4. Connect from mobile

1. Make sure your phone and computer are on the **same WiFi network**
2. The app will show a URL in the top bar (e.g. `http://192.168.1.100:8080`)
3. Click the **QR code icon** in the app bar
4. **Scan the QR code** with your phone camera
5. The web client opens in your mobile browser — start copy/pasting!

## Usage

### Clipboard Sync (Desktop → Mobile)

1. Copy any text on your desktop (Ctrl+C / Cmd+C)
2. The text automatically appears in the mobile browser's clipboard history
3. Tap **"Copy"** on the mobile to copy it to your phone's clipboard

### Clipboard Sync (Mobile → Desktop)

1. Paste text into the text area on the mobile web client
2. Tap **"Send to Desktop"**
3. The text is written to your desktop's clipboard — ready to paste

### Multiple Devices

Multiple phones/tablets can connect simultaneously. Each device appears in the desktop app's device list with its device name.

## Build for Release

### Linux

```bash
flutter build linux --release

# Output: build/linux/x64/release/bundle/
# Run: ./build/linux/x64/release/bundle/copypaste
```

### macOS

```bash
flutter build macos --release

# Output: build/macos/Build/Products/Release/copypaste.app
```

## Project Structure

```
copy-paste/
├── lib/                    # Flutter desktop app (Dart)
│   ├── main.dart           # App entry point
│   ├── core/               # Networking, protocol, discovery, web server
│   ├── services/           # Clipboard, transfer, app orchestration
│   ├── models/             # Data models
│   ├── providers/          # Riverpod state management
│   ├── screens/            # UI screens & widgets
│   └── utils/              # Constants, logger, network utils
├── web_client/             # Mobile web SPA (HTML/CSS/JS)
│   ├── index.html
│   ├── css/style.css
│   └── js/                 # WebSocket, clipboard, transfer, UI logic
├── docs/                   # Architecture & development docs
│   ├── ARCHITECTURE.md
│   └── DEVELOPMENT-PHASES.md
├── linux/                  # Linux platform files
├── macos/                  # macOS platform files
├── pubspec.yaml            # Flutter dependencies
└── LICENSE                 # MIT License
```

## Architecture

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full architecture documentation.

**Key design decisions:**
- **Hybrid architecture**: Desktop app (Flutter) + Mobile web client (vanilla JS)
- **P2P local network**: No cloud relay, all communication stays on LAN
- **Desktop as hub**: Each desktop runs an embedded HTTP + WebSocket server
- **Mobile via browser**: Scan QR code, no app install needed
- **Privacy first**: Data never leaves your local network

## Development

See [docs/DEVELOPMENT-PHASES.md](docs/DEVELOPMENT-PHASES.md) for development progress and roadmap.

### Tech Stack

| Component | Technology |
|-----------|-----------|
| Desktop app | Flutter 3.41+ (Dart) |
| State management | Riverpod |
| Desktop ↔ Desktop | TCP socket + custom binary protocol |
| Desktop ↔ Mobile | HTTP + WebSocket (JSON) |
| Device discovery | mDNS/DNS-SD via `nsd` (macOS), avahi (Linux - planned) |
| Web client | Vanilla HTML/CSS/JS (< 50KB, no framework) |
| Encryption | AES-256-GCM + X25519 (planned) |

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

### Flutter snap issues (Linux)

Don't use `snap install flutter`. The snap version has AppArmor confinement issues that prevent building. Use the manual SDK install instead.

### mDNS not working on Linux

The `nsd` Flutter plugin does not support Linux desktop. Desktop-to-desktop discovery on Linux is not yet available. Use the web client (QR code) to connect mobile devices.

## License

MIT License — see [LICENSE](LICENSE)
