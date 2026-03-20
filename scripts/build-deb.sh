#!/bin/bash
set -e

# ─────────────────────────────────────────────
# Build CopyPaste .deb package for Linux
# Usage: ./scripts/build-deb.sh
# ─────────────────────────────────────────────

APP_NAME="copypaste"
APP_DISPLAY_NAME="CopyPaste"
APP_VERSION="0.2.0"
APP_DESCRIPTION="Open-source clipboard sharing and file transfer over local network"
APP_ID="com.copypaste.copypaste"
MAINTAINER="CopyPaste Team <copypaste@localhost>"
ARCH="amd64"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
BUNDLE_DIR="$BUILD_DIR/linux/x64/release/bundle"
DEB_DIR="$BUILD_DIR/${APP_NAME}_${APP_VERSION}_${ARCH}"

echo "=== Building CopyPaste .deb package ==="
echo "Version: $APP_VERSION"
echo "Project: $PROJECT_DIR"

# Step 1: Build Flutter release
echo ""
echo "[1/4] Building Flutter Linux release..."
cd "$PROJECT_DIR"
flutter build linux --release

if [ ! -f "$BUNDLE_DIR/$APP_NAME" ]; then
    echo "ERROR: Build failed — binary not found at $BUNDLE_DIR/$APP_NAME"
    exit 1
fi
echo "  Build complete."

# Step 2: Create .deb directory structure
echo ""
echo "[2/4] Creating .deb package structure..."
rm -rf "$DEB_DIR"

# Directories
mkdir -p "$DEB_DIR/DEBIAN"
mkdir -p "$DEB_DIR/usr/lib/$APP_NAME"
mkdir -p "$DEB_DIR/usr/bin"
mkdir -p "$DEB_DIR/usr/share/applications"
mkdir -p "$DEB_DIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$DEB_DIR/usr/share/doc/$APP_NAME"

# Step 3: Copy files
echo ""
echo "[3/4] Copying files..."

# Copy the entire bundle
cp -r "$BUNDLE_DIR/"* "$DEB_DIR/usr/lib/$APP_NAME/"

# Create symlink in /usr/bin
cat > "$DEB_DIR/usr/bin/$APP_NAME" << 'LAUNCHER'
#!/bin/bash
INSTALL_DIR="/usr/lib/copypaste"
export LD_LIBRARY_PATH="$INSTALL_DIR/lib:$LD_LIBRARY_PATH"
exec "$INSTALL_DIR/copypaste" "$@"
LAUNCHER
chmod +x "$DEB_DIR/usr/bin/$APP_NAME"

# Create .desktop file
cat > "$DEB_DIR/usr/share/applications/$APP_ID.desktop" << EOF
[Desktop Entry]
Type=Application
Name=$APP_DISPLAY_NAME
Comment=$APP_DESCRIPTION
Exec=$APP_NAME
Icon=$APP_NAME
Terminal=false
Categories=Utility;Network;
Keywords=clipboard;copy;paste;transfer;sync;
StartupNotify=true
EOF

# Create a simple SVG icon (placeholder — replace with actual icon later)
cat > "$DEB_DIR/usr/share/icons/hicolor/256x256/apps/$APP_NAME.svg" << 'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256" width="256" height="256">
  <rect width="256" height="256" rx="48" fill="#2563eb"/>
  <text x="128" y="160" font-family="Arial,sans-serif" font-size="120" font-weight="bold"
        fill="white" text-anchor="middle">CP</text>
</svg>
SVG

# Create copyright doc
cat > "$DEB_DIR/usr/share/doc/$APP_NAME/copyright" << EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: $APP_DISPLAY_NAME
License: MIT

Copyright (c) 2024 CopyPaste Contributors
Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files, to deal in the Software
without restriction, including without limitation the rights to use, copy,
modify, merge, publish, distribute, sublicense, and/or sell copies of the
Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.
EOF

# Step 4: Create DEBIAN control files
echo ""
echo "[4/4] Creating DEBIAN control files..."

# Calculate installed size (in KB)
INSTALLED_SIZE=$(du -sk "$DEB_DIR" | cut -f1)

cat > "$DEB_DIR/DEBIAN/control" << EOF
Package: $APP_NAME
Version: $APP_VERSION
Section: utils
Priority: optional
Architecture: $ARCH
Installed-Size: $INSTALLED_SIZE
Depends: libgtk-3-0, libnotify4
Maintainer: $MAINTAINER
Description: $APP_DESCRIPTION
 CopyPaste is an open-source, self-hosted clipboard sharing and file
 transfer tool across devices over local network (P2P).
 Copy on one device, paste on another.
 No cloud, no server, no internet required.
Homepage: https://github.com/your-username/copy-paste
EOF

# Post-install script
cat > "$DEB_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e
# Update desktop database
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database -q /usr/share/applications || true
fi
# Update icon cache
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
EOF
chmod 755 "$DEB_DIR/DEBIAN/postinst"

# Post-remove script
cat > "$DEB_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e
if command -v update-desktop-database &>/dev/null; then
    update-desktop-database -q /usr/share/applications || true
fi
if command -v gtk-update-icon-cache &>/dev/null; then
    gtk-update-icon-cache -q /usr/share/icons/hicolor || true
fi
EOF
chmod 755 "$DEB_DIR/DEBIAN/postrm"

# Build the .deb
echo ""
echo "=== Building .deb package ==="
DEB_FILE="$BUILD_DIR/${APP_NAME}_${APP_VERSION}_${ARCH}.deb"
dpkg-deb --build --root-owner-group "$DEB_DIR" "$DEB_FILE"

# Show result
echo ""
echo "=== Done! ==="
echo "Package: $DEB_FILE"
echo "Size: $(du -h "$DEB_FILE" | cut -f1)"
echo ""
echo "Install with:"
echo "  sudo dpkg -i $DEB_FILE"
echo ""
echo "Remove with:"
echo "  sudo apt remove $APP_NAME"
