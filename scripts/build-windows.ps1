# ─────────────────────────────────────────────
# Build CopyPaste for Windows
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
#
# Prerequisites:
#   - Flutter SDK (3.41.0+)
#   - Visual Studio 2022 with "Desktop development with C++" workload
#   - ImageMagick (optional — for icon conversion)
# ─────────────────────────────────────────────

$ErrorActionPreference = "Stop"

$APP_NAME = "copypaste"
$APP_DISPLAY_NAME = "CopyPaste"
$APP_VERSION = "0.3.0"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR
$BUILD_DIR = Join-Path $PROJECT_DIR "build"
$RELEASE_DIR = Join-Path $BUILD_DIR "windows\x64\runner\Release"
$WINDOWS_DIR = Join-Path $PROJECT_DIR "windows"
$ICON_SRC = Join-Path $PROJECT_DIR "assets\icons\app_icon.png"
$ICON_DST = Join-Path $PROJECT_DIR "windows\runner\resources\app_icon.ico"
$OUTPUT_ZIP = Join-Path $BUILD_DIR "${APP_DISPLAY_NAME}_${APP_VERSION}_Windows.zip"

Write-Host "=== Building CopyPaste for Windows ===" -ForegroundColor Cyan
Write-Host "Version: $APP_VERSION"
Write-Host "Project: $PROJECT_DIR"
Write-Host ""

# ─── Step 1: Check prerequisites ───
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Yellow

# Check Flutter
try {
    $flutterVersion = flutter --version 2>&1 | Select-Object -First 1
    Write-Host "  Flutter: $flutterVersion"
} catch {
    Write-Host "  ERROR: Flutter not found. Install from https://docs.flutter.dev/get-started/install/windows" -ForegroundColor Red
    exit 1
}

# Check Visual Studio
$vsWhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (Test-Path $vsWhere) {
    $vsPath = & $vsWhere -latest -property installationPath 2>$null
    if ($vsPath) {
        Write-Host "  Visual Studio: $vsPath"
    } else {
        Write-Host "  WARNING: Visual Studio not found" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "  WARNING: Cannot verify Visual Studio installation" -ForegroundColor DarkYellow
}

# ─── Step 2: Generate Windows platform files if needed ───
Write-Host ""
Write-Host "[2/6] Checking Windows platform files..." -ForegroundColor Yellow
Set-Location $PROJECT_DIR

if (-not (Test-Path $WINDOWS_DIR)) {
    Write-Host "  Generating Windows platform files..."
    flutter create --platforms windows .
    Write-Host "  Generated."
} else {
    Write-Host "  Windows platform files already exist."
}

# ─── Step 3: Convert app icon ───
Write-Host ""
Write-Host "[3/6] Setting app icon..." -ForegroundColor Yellow

if (Test-Path $ICON_SRC) {
    $iconConverted = $false

    # Try ImageMagick (magick command)
    try {
        $magickPath = Get-Command magick -ErrorAction SilentlyContinue
        if ($magickPath) {
            Write-Host "  Converting icon with ImageMagick..."
            & magick convert $ICON_SRC -define icon:auto-resize=256,128,64,48,32,16 $ICON_DST
            $iconConverted = $true
            Write-Host "  Icon converted: $ICON_DST"
        }
    } catch {}

    # Try Python Pillow as fallback
    if (-not $iconConverted) {
        try {
            $pythonPath = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonPath) {
                $pythonPath = Get-Command python3 -ErrorAction SilentlyContinue
            }
            if ($pythonPath) {
                Write-Host "  Converting icon with Python Pillow..."
                $pyScript = @"
from PIL import Image
img = Image.open(r'$ICON_SRC')
sizes = [(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)]
img.save(r'$ICON_DST', format='ICO', sizes=sizes)
print('OK')
"@
                $result = $pyScript | python 2>&1
                if ($result -match "OK") {
                    $iconConverted = $true
                    Write-Host "  Icon converted: $ICON_DST"
                }
            }
        } catch {}
    }

    if (-not $iconConverted) {
        Write-Host "  WARNING: Cannot convert icon (install ImageMagick or Python+Pillow)" -ForegroundColor DarkYellow
        Write-Host "  Using default Flutter icon."
        Write-Host ""
        Write-Host "  To install ImageMagick: winget install ImageMagick.ImageMagick" -ForegroundColor DarkGray
        Write-Host "  To install Pillow:      pip install Pillow" -ForegroundColor DarkGray
    }
} else {
    Write-Host "  WARNING: Source icon not found at $ICON_SRC" -ForegroundColor DarkYellow
}

# ─── Step 4: Get dependencies ───
Write-Host ""
Write-Host "[4/6] Getting dependencies..." -ForegroundColor Yellow
flutter pub get
Write-Host "  Done."

# ─── Step 5: Build release ───
Write-Host ""
Write-Host "[5/6] Building Windows release..." -ForegroundColor Yellow
flutter build windows --release

if (-not (Test-Path $RELEASE_DIR)) {
    Write-Host "  ERROR: Build failed — release directory not found" -ForegroundColor Red
    exit 1
}
Write-Host "  Build complete: $RELEASE_DIR"

# ─── Step 6: Package as ZIP ───
Write-Host ""
Write-Host "[6/6] Packaging..." -ForegroundColor Yellow

if (Test-Path $OUTPUT_ZIP) {
    Remove-Item $OUTPUT_ZIP -Force
}

Compress-Archive -Path "$RELEASE_DIR\*" -DestinationPath $OUTPUT_ZIP
Write-Host "  Package: $OUTPUT_ZIP"

# ─── Done ───
$zipSize = (Get-Item $OUTPUT_ZIP).Length / 1MB
Write-Host ""
Write-Host "=== Done! ===" -ForegroundColor Green
Write-Host "ZIP:  $OUTPUT_ZIP"
Write-Host "Size: $([math]::Round($zipSize, 1)) MB"
Write-Host ""
Write-Host "To run:"
Write-Host "  1. Extract ZIP"
Write-Host "  2. Run copypaste.exe"
