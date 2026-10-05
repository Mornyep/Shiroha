#!/bin/bash
set -euo pipefail
SOURCE=${1:?source PNG required}
DESTINATION=${2:?destination icns required}
WORK=$(mktemp -d /private/tmp/VNLauncher-icon.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$SOURCE" --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$SOURCE" --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$DESTINATION"
