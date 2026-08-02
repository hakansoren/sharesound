#!/bin/bash
#
# Packages ShareSound.app into a distributable disk image.
#
# Usage:
#   ./Scripts/build-dmg.sh            # builds the app first, then the .dmg
#   SKIP_BUILD=1 ./Scripts/build-dmg.sh
#
# The image contains the app next to an Applications symlink, so installing is
# a drag from one side of the window to the other.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$PROJECT_ROOT/dist/ShareSound.app"
VERSION="$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "1.0.0")"
DMG_PATH="$PROJECT_ROOT/dist/ShareSound-$VERSION.dmg"
VOLUME_NAME="ShareSound $VERSION"

if [[ "${SKIP_BUILD:-0}" != "1" ]]; then
    "$PROJECT_ROOT/Scripts/build-app.sh"
fi

if [[ ! -d "$APP_BUNDLE" ]]; then
    echo "error: $APP_BUNDLE not found. Run Scripts/build-app.sh first." >&2
    exit 1
fi

STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT

echo "-> Staging disk image contents..."
cp -R "$APP_BUNDLE" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# A short read-me travels with the image because the app is ad-hoc signed:
# without a Developer ID, Gatekeeper needs the user to open it once by hand.
cat > "$STAGING/Read Me.txt" <<'NOTE'
ShareSound

Install
  Drag ShareSound onto Applications.

First launch
  ShareSound is signed ad-hoc rather than with an Apple Developer ID, so macOS
  will not open it on a double-click the first time. Right-click (or Control-
  click) the app in Applications, choose Open, then confirm. This is only
  needed once.

Using it
  ShareSound has no Dock icon. Look for its logo in the menu bar, at the top
  right of the screen. Tick two output devices and press Start Sharing.

Requires macOS 26 or later.
https://github.com/hakansoren/sharesound
NOTE

echo "-> Building disk image..."
rm -f "$DMG_PATH"
hdiutil create \
    -volname "$VOLUME_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -quiet \
    "$DMG_PATH"

echo "-> Verifying..."
hdiutil verify -quiet "$DMG_PATH"

SIZE="$(du -h "$DMG_PATH" | cut -f1 | tr -d ' ')"
echo "Done: $DMG_PATH ($SIZE)"
lipo -info "$APP_BUNDLE/Contents/MacOS/ShareSound" | sed 's/^/   /'
