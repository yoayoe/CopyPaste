#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Build CopyPaste APK for Android
# Usage: ./scripts/build-apk.sh
#
# Prerequisites:
#   - Android SDK (set ANDROID_HOME or installed via sdkmanager)
#   - Java 17+ (set JAVA_HOME)
#   - Flutter SDK
# ─────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
APP_VERSION=$(grep '^version:' "$PROJECT_DIR/pubspec.yaml" | sed 's/version:[[:space:]]*//' | cut -d'+' -f1 | tr -d '[:space:]')
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="CopyPaste"

# ─── Auto-detect Java if not set ───
if [ -z "$JAVA_HOME" ]; then
  POSSIBLE_JAVA=(
    "$HOME/Development/jdks/jdk-21.0.11+10"
    "$HOME/.antigravity/extensions/redhat.java-1.51.0-linux-x64/jre/21.0.9-linux-x86_64"
    "/usr/lib/jvm/java-17-openjdk-amd64"
    "/usr/lib/jvm/java-11-openjdk-amd64"
  )
  for dir in "${POSSIBLE_JAVA[@]}"; do
    if [ -f "$dir/bin/jlink" ]; then
      export JAVA_HOME="$dir"
      break
    fi
  done
  if [ -z "$JAVA_HOME" ]; then
    for dir in "${POSSIBLE_JAVA[@]}"; do
      if [ -f "$dir/bin/java" ]; then
        export JAVA_HOME="$dir"
        break
      fi
    done
  fi
fi

if [ -z "$JAVA_HOME" ]; then
  echo "ERROR: JAVA_HOME not set and no Java found."
  exit 1
fi
export PATH="$JAVA_HOME/bin:$PATH"
echo "  Java: $(java -version 2>&1 | head -1)"

# ─── Auto-detect Android SDK if not set ───
if [ -z "$ANDROID_HOME" ]; then
  POSSIBLE_SDK=(
    "$HOME/Android"
    "/usr/local/lib/android/sdk"
    "/opt/android-sdk"
    "$HOME/Android/Sdk"
  )
  for dir in "${POSSIBLE_SDK[@]}"; do
    if [ -d "$dir/platforms" ]; then
      export ANDROID_HOME="$dir"
      break
    fi
  done
fi

if [ -z "$ANDROID_HOME" ]; then
  echo "ERROR: ANDROID_HOME not set and no Android SDK found."
  exit 1
fi
echo "  Android SDK: $ANDROID_HOME"

echo "=== Building $APP_NAME APK ==="
echo "Version: $APP_VERSION"
echo "Project: $PROJECT_DIR"
echo ""

# Step 1: Get dependencies
echo "[1/3] Getting dependencies..."
cd "$PROJECT_DIR"
flutter pub get
echo "  Done."
echo ""

# Step 2: Build APK
echo "[2/3] Building Android APK..."
flutter build apk --release
echo "  Done."
echo ""

# Step 3: Collect & rename artifact to match release version
echo "[3/3] Collecting artifacts..."
RAW_APK="$BUILD_DIR/app/outputs/flutter-apk/app-release.apk"
APK_FILE="$BUILD_DIR/${APP_NAME}_${APP_VERSION}_Android.apk"
if [ -f "$RAW_APK" ]; then
  cp "$RAW_APK" "$APK_FILE"
  APK_SIZE=$(du -h "$APK_FILE" | cut -f1)
  echo ""
  echo "======================================"
  echo "  Build complete!"
  echo "  APK: $APK_FILE"
  echo "  Size: $APK_SIZE"
  echo "======================================"
  echo ""
  echo "Install on device:"
  echo "  flutter install"
  echo ""
  echo "Or push manually:"
  echo "  adb install $APK_FILE"
else
  echo "ERROR: APK not found at $RAW_APK"
  ls -la "$BUILD_DIR/app/outputs/flutter-apk/" 2>/dev/null || true
  exit 1
fi
