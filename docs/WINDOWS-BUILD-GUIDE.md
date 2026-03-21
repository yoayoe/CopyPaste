# Windows Build Guide — CopyPaste

Panduan setup environment development dan build CopyPaste di Windows.

---

## Prerequisites

### 1. Install Flutter SDK

Download Flutter SDK dari https://docs.flutter.dev/get-started/install/windows/desktop

**Minimum version:**
- Flutter: **3.41.0**
- Dart: **3.8.0**

```powershell
# Setelah install, verifikasi:
flutter --version
dart --version
```

### 2. Install Visual Studio

Flutter Windows membutuhkan **Visual Studio 2022** (bukan VS Code) dengan workload:

- **"Desktop development with C++"**
  - Termasuk: MSVC v143, Windows 10/11 SDK, CMake tools

Download: https://visualstudio.microsoft.com/downloads/
Pilih **Community Edition** (gratis).

Saat install, centang:
- [x] Desktop development with C++
- [x] Windows 10 SDK (atau Windows 11 SDK)
- [x] C++ CMake tools for Windows

### 3. Install Git

Download: https://git-scm.com/download/win

### 4. Verifikasi Environment

```powershell
flutter doctor
```

Pastikan output menunjukkan:
```
[✓] Flutter (Channel stable, 3.41.x)
[✓] Windows Version (Windows 10/11)
[✓] Visual Studio - develop Windows apps (Visual Studio Community 2022)
```

---

## Setup Project

### 1. Clone Repository

```powershell
git clone <repo-url> copypaste
cd copypaste
```

### 2. Generate Windows Platform Files

Project saat ini belum punya directory `windows/`. Generate dulu:

```powershell
flutter create --platforms windows .
```

Ini akan membuat directory `windows/` dengan semua file CMake, runner, dll.

### 3. Install Dependencies

```powershell
flutter pub get
```

### 4. Generate Code (Freezed/JSON Serializable)

```powershell
dart run build_runner build --delete-conflicting-outputs
```

---

## Build & Run

### Development (Debug)

```powershell
flutter run -d windows
```

### Release Build

```powershell
flutter build windows --release
```

Output: `build\windows\x64\runner\Release\copypaste.exe`

---

## Catatan Platform-Specific

### Dependencies yang Support Windows

| Package | Windows Support | Catatan |
|---------|----------------|---------|
| `flutter_riverpod` | OK | Pure Dart |
| `cryptography` | OK | Pure Dart |
| `shelf` / `shelf_web_socket` | OK | Pure Dart |
| `file_picker` | OK | Native Windows file dialog |
| `path_provider` | OK | AppData, Temp, dll |
| `flutter_secure_storage` | OK | Menggunakan Windows DPAPI |
| `shared_preferences` | OK | Windows registry |
| `window_manager` | OK | Native Win32 window management |
| `local_notifier` | OK | Windows toast notifications |
| `qr_flutter` | OK | Pure Dart rendering |
| `uuid` | OK | Pure Dart |
| `nsd` | **TIDAK SUPPORT** | mDNS discovery — fallback ke manual IP connection |

### Yang Perlu Diperhatikan

1. **mDNS Discovery (`nsd`)** — Tidak support Windows. App sudah punya fallback manual IP connection, jadi tetap bisa konek antar device.

2. **Clipboard Monitoring** — Saat ini menggunakan polling 500ms (platform-agnostic). Untuk performa lebih baik di Windows, bisa upgrade ke Win32 `AddClipboardFormatListener` di masa depan.

3. **Firewall** — Windows Firewall akan muncul prompt saat app pertama kali listen di TCP/HTTP port. User perlu klik "Allow access".

4. **Secure Storage** — `flutter_secure_storage` di Windows menggunakan DPAPI (Data Protection API). Tidak perlu konfigurasi tambahan.

5. **File Paths** — App menggunakan `path_provider` untuk mendapat directory yang benar:
   - `getApplicationSupportDirectory()` → `%APPDATA%\com.copypaste\copypaste\`
   - `getTemporaryDirectory()` → `%TEMP%\`

---

## Packaging (Distribusi)

### Option 1: MSIX Package

```powershell
# Install msix package
flutter pub add --dev msix

# Build MSIX
dart run msix:create
```

Tambahkan konfigurasi di `pubspec.yaml`:
```yaml
msix_config:
  display_name: CopyPaste
  publisher_display_name: CopyPaste
  identity_name: com.copypaste.copypaste
  msix_version: 0.3.0.0
  capabilities: internetClient, internetClientServer, privateNetworkClientServer
```

### Option 2: Inno Setup (.exe Installer)

1. Download Inno Setup: https://jrsoftware.org/isdl.php
2. Buat script `.iss` yang point ke `build\windows\x64\runner\Release\`
3. Compile menjadi `.exe` installer

### Option 3: Portable (ZIP)

```powershell
# Build release
flutter build windows --release

# ZIP the output
Compress-Archive -Path "build\windows\x64\runner\Release\*" -DestinationPath "CopyPaste_Windows.zip"
```

---

## Troubleshooting

### `flutter doctor` — Visual Studio not found
Pastikan workload "Desktop development with C++" terinstall. Buka Visual Studio Installer → Modify → centang workload tersebut.

### Build error: CMake
```powershell
# Pastikan CMake ada di PATH
cmake --version

# Jika tidak ada, install via Visual Studio Installer
# atau download dari https://cmake.org/download/
```

### Firewall blocking connections
Saat pertama run, Windows Firewall akan tanya. Pilih:
- [x] Private networks
- [x] Public networks (jika ingin akses dari device lain di network lain)

### `nsd` plugin error
Plugin `nsd` tidak support Windows. Jika build error terkait `nsd`, pastikan `flutter create --platforms windows .` sudah dijalankan dan plugin fallback sudah dihandle di code (sudah ada — app skip mDNS di non-macOS).
