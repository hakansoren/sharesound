#!/bin/bash
#
# Builds a macOS app icon (.icns) from a 1024x1024 PNG.
#
# Usage:  Scripts/make-icon.sh ~/Downloads/sharesound-logo.png
#
# The result is written to Assets/AppIcon.icns; build-app.sh embeds it into the
# app bundle automatically when it finds one there.

set -euo pipefail

SOURCE="${1:-}"
if [[ -z "$SOURCE" || ! -f "$SOURCE" ]]; then
    echo "Usage: Scripts/make-icon.sh <1024x1024.png>" >&2
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ASSETS_DIR="$PROJECT_ROOT/Assets"
WORK_DIR="$(mktemp -d)"
ICONSET="$WORK_DIR/AppIcon.iconset"

trap 'rm -rf "$WORK_DIR"' EXIT

WIDTH=$(sips -g pixelWidth "$SOURCE" | awk '/pixelWidth/ {print $2}')
HEIGHT=$(sips -g pixelHeight "$SOURCE" | awk '/pixelHeight/ {print $2}')
if [[ "$WIDTH" -lt 1024 || "$HEIGHT" -lt 1024 ]]; then
    echo "warning: source is ${WIDTH}x${HEIGHT}; 1024x1024 gives the best result." >&2
fi

mkdir -p "$ICONSET" "$ASSETS_DIR"

# The set of sizes macOS expects, each with its Retina counterpart.
render() {
    sips -z "$2" "$2" "$SOURCE" --out "$ICONSET/$1" >/dev/null
}

render icon_16x16.png        16
render icon_16x16@2x.png     32
render icon_32x32.png        32
render icon_32x32@2x.png     64
render icon_128x128.png      128
render icon_128x128@2x.png   256
render icon_256x256.png      256
render icon_256x256@2x.png   512
render icon_512x512.png      512
render icon_512x512@2x.png   1024

iconutil --convert icns "$ICONSET" --output "$ASSETS_DIR/AppIcon.icns"

echo "Done: $ASSETS_DIR/AppIcon.icns"
echo "Now run ./Scripts/build-app.sh to embed it."
