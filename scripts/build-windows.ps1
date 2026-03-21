# Build CopyPaste for Windows
# Usage: powershell -ExecutionPolicy Bypass -File scripts\build-windows.ps1
#
# Prerequisites:
#   - Flutter SDK (3.41.0+)
#   - Visual Studio 2022 with "Desktop development with C++" workload
#   - ImageMagick (optional, for icon conversion)

$ErrorActionPreference = "Stop"

$APP_DISPLAY_NAME = "CopyPaste"
$APP_VERSION = "0.3.0"

$SCRIPT_DIR = Split-Path -Parent $MyInvocation.MyCommand.Path
$PROJECT_DIR = Split-Path -Parent $SCRIPT_DIR
$BUILD_DIR = Join-Path $PROJECT_DIR "build"
$RELEASE_DIR = Join-Path $BUILD_DIR "windows\x64\runner\Release"
$WINDOWS_DIR = Join-Path $PROJECT_DIR "windows"
$ICON_SRC = Join-Path $PROJECT_DIR "assets\icons\app_icon.png"
$ICON_DST = Join-Path $PROJECT_DIR "windows\runner\resources\app_icon.ico"
$ZIP_NAME = $APP_DISPLAY_NAME + "_" + $APP_VERSION + "_Windows.zip"
$OUTPUT_ZIP = Join-Path $BUILD_DIR $ZIP_NAME

Write-Host "=== Building CopyPaste for Windows ===" -ForegroundColor Cyan
Write-Host "Version: $APP_VERSION"
Write-Host "Project: $PROJECT_DIR"
Write-Host ""

# --- Step 1: Check prerequisites ---
Write-Host "[1/6] Checking prerequisites..." -ForegroundColor Yellow

$flutterCmd = Get-Command flutter -ErrorAction SilentlyContinue
if (-not $flutterCmd) {
    Write-Host "  ERROR: Flutter not found in PATH" -ForegroundColor Red
    exit 1
}
$flutterVer = flutter --version 2>&1 | Select-Object -First 1
Write-Host "  Flutter: $flutterVer"

# --- Step 2: Generate Windows platform files if needed ---
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

# --- Step 3: Convert app icon ---
Write-Host ""
Write-Host "[3/6] Setting app icon..." -ForegroundColor Yellow

$iconConverted = $false

if (Test-Path $ICON_SRC) {
    # Try ImageMagick
    $magickCmd = Get-Command magick -ErrorAction SilentlyContinue
    if ($magickCmd) {
        Write-Host "  Converting icon with ImageMagick..."
        & magick convert $ICON_SRC -define icon:auto-resize=256,128,64,48,32,16 $ICON_DST
        $iconConverted = $true
        Write-Host "  Icon converted: $ICON_DST"
    }

    # Try Python Pillow as fallback
    if (-not $iconConverted) {
        # Find real Python (not Windows Store alias stub)
        $pyExe = $null
        foreach ($name in @("py", "python3", "python")) {
            $found = Get-Command $name -ErrorAction SilentlyContinue
            if ($found -and $found.Source -notmatch "WindowsApps") {
                $pyExe = $found.Source
                break
            }
        }
        if ($pyExe) {
            Write-Host "  Trying Python Pillow ($pyExe)..."
            $pyCode = "from PIL import Image; img = Image.open(r'$ICON_SRC'); img.save(r'$ICON_DST', format='ICO', sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)]); print('OK')"
            $oldPref = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            $pyResult = & $pyExe -c $pyCode 2>&1
            $ErrorActionPreference = $oldPref
            if ("$pyResult" -match "OK") {
                $iconConverted = $true
                Write-Host "  Icon converted: $ICON_DST"
            }
        }
    }

    if (-not $iconConverted) {
        Write-Host "  WARNING: Cannot convert icon. Install ImageMagick or Python+Pillow" -ForegroundColor DarkYellow
        Write-Host "  Install: winget install ImageMagick.ImageMagick" -ForegroundColor DarkGray
        Write-Host "  Or:      pip install Pillow" -ForegroundColor DarkGray
        Write-Host "  Using default Flutter icon."
    }
} else {
    Write-Host "  WARNING: Source icon not found at $ICON_SRC" -ForegroundColor DarkYellow
}

# --- Step 4: Get dependencies ---
Write-Host ""
Write-Host "[4/6] Getting dependencies..." -ForegroundColor Yellow
flutter pub get
Write-Host "  Done."

# --- Step 5: Build release ---
Write-Host ""
Write-Host "[5/6] Building Windows release..." -ForegroundColor Yellow
flutter build windows --release

if (-not (Test-Path $RELEASE_DIR)) {
    Write-Host "  ERROR: Build failed, release directory not found" -ForegroundColor Red
    exit 1
}
Write-Host "  Build complete: $RELEASE_DIR"

# --- Step 6: Package as ZIP ---
Write-Host ""
Write-Host "[6/6] Packaging..." -ForegroundColor Yellow

if (Test-Path $OUTPUT_ZIP) {
    Remove-Item $OUTPUT_ZIP -Force
}

Compress-Archive -Path (Join-Path $RELEASE_DIR "*") -DestinationPath $OUTPUT_ZIP
Write-Host "  Package: $OUTPUT_ZIP"

# --- Done ---
$zipSize = [math]::Round((Get-Item $OUTPUT_ZIP).Length / 1MB, 1)
Write-Host ""
Write-Host "=== Done! ===" -ForegroundColor Green
Write-Host "ZIP:  $OUTPUT_ZIP"
Write-Host "Size: $zipSize MB"
Write-Host ""
Write-Host "To run: extract ZIP and run copypaste.exe"
