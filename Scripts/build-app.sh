#!/bin/bash
#
# Builds the ShareSound.app bundle.
#
# SwiftPM does not produce an .app on its own; this script places the compiled
# executable into a standard app bundle, writes Info.plist and signs it. Without
# a signature macOS quarantines the app on every launch.
#
# Usage:
#   ./Scripts/build-app.sh                 # release bundle, universal, ad-hoc signature
#   ./Scripts/build-app.sh debug           # debug bundle, host architecture only
#   UNIVERSAL=0 ./Scripts/build-app.sh     # host architecture only
#   CODESIGN_IDENTITY="Developer ID Application: ..." ./Scripts/build-app.sh
#
# Assets/AppIcon.icns is embedded when present (see Scripts/make-icon.sh).

set -euo pipefail

CONFIGURATION="${1:-release}"
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/dist/ShareSound.app"
CONTENTS="$APP_BUNDLE/Contents"
ICON_SOURCE="$PROJECT_ROOT/Assets/AppIcon.icns"

VERSION="$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "1.0.0")"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
MINIMUM_MACOS="26.0"
IDENTITY="${CODESIGN_IDENTITY:--}"

# Release builds ship a universal binary so the app runs natively on Apple
# Silicon and on the Intel Macs that can still run macOS 26. Debug builds stay
# single-architecture, since nothing is gained by doubling the build time.
BUILD_ARGS=(-c "$CONFIGURATION" --package-path "$PROJECT_ROOT")
ARCH_NOTE="host architecture"
if [[ "$CONFIGURATION" == "release" && "${UNIVERSAL:-1}" == "1" ]]; then
    BUILD_ARGS+=(--arch arm64 --arch x86_64)
    ARCH_NOTE="universal (arm64 + x86_64)"
fi

echo "-> Building ($CONFIGURATION, version $VERSION, $ARCH_NOTE)..."
swift build "${BUILD_ARGS[@]}"

# Ask SwiftPM where it actually put the products; the path differs between
# single-architecture and universal builds.
BUILD_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"

echo "-> Assembling bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BUILD_DIR/ShareSound" "$CONTENTS/MacOS/ShareSound"

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>ShareSound</string>
    <key>CFBundleDisplayName</key>
    <string>ShareSound</string>
    <key>CFBundleIdentifier</key>
    <string>com.sharesound.app</string>
    <key>CFBundleExecutable</key>
    <string>ShareSound</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_MACOS</string>
    <!-- Absent from the Dock and app switcher: it lives in the menu bar only. -->
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>ShareSound</string>
</dict>
</plist>
PLIST

# The resource bundle SwiftPM produces (it holds the menu bar logo) is moved into
# the app's Resources folder, where Bundle.module finds it.
RESOURCE_BUNDLE="$BUILD_DIR/ShareSound_ShareSound.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$CONTENTS/Resources/"
    echo "-> Resource bundle embedded."
else
    echo "warning: resource bundle not found: $RESOURCE_BUNDLE" >&2
fi

if [[ -f "$ICON_SOURCE" ]]; then
    cp "$ICON_SOURCE" "$CONTENTS/Resources/AppIcon.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS/Info.plist" >/dev/null
    echo "-> Icon embedded."
else
    echo "-> No icon at Assets/AppIcon.icns; continuing with the default."
fi

if [[ "$IDENTITY" == "-" ]]; then
    echo "-> Signing (ad-hoc)..."
else
    echo "-> Signing ($IDENTITY)..."
fi
codesign --force --options runtime --sign "$IDENTITY" "$APP_BUNDLE" 2>/dev/null \
    || codesign --force --sign "$IDENTITY" "$APP_BUNDLE"

echo "-> Verifying..."
codesign --verify --strict "$APP_BUNDLE"
lipo -info "$CONTENTS/MacOS/ShareSound" | sed 's/^/   /'

echo "Done: $APP_BUNDLE  (v$VERSION)"
echo "  Install:  cp -R \"$APP_BUNDLE\" /Applications/"
