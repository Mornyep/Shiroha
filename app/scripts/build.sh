#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
DESTINATION=${VN_BUILD_OUTPUT:-"$PWD/build/Shiroha.zip"}
if [[ "$DESTINATION" != /* ]]; then DESTINATION="$PWD/$DESTINATION"; fi
STAGING=$(mktemp -d /private/tmp/VNLauncher-bundle.XXXXXX)
APP="$STAGING/白羽 Shiroha.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/VNLauncher "$APP/Contents/MacOS/VNLauncher"
BINARY="$APP/Contents/MacOS/VNLauncher"
# Only the distribution copy is stripped; the build cache retains debugging data.
xcrun strip -S "$BINARY"
# Xcode beta toolchains can embed their machine-local Swift runtime rpaths.
# Keep the system and loader paths; remove only these build-toolchain paths.
while IFS= read -r runtime_path; do
    case "$runtime_path" in
        *.xctoolchain/usr/lib/swift*/macosx)
            xcrun install_name_tool -delete_rpath "$runtime_path" "$BINARY"
            ;;
    esac
done < <(otool -l "$BINARY" | awk '/cmd LC_RPATH/ {rpath=1; next} rpath && /path / {sub(/^.*path /, ""); sub(/ \(offset .*$/, ""); print; rpath=0}')
if strings "$BINARY" | grep -E '/Users/|/private/(tmp|var/folders)/|/var/folders/' >/dev/null; then
    printf '%s\n' 'Distribution binary still contains local paths; refusing to package.' >&2
    exit 1
fi
bash scripts/make-icon.sh "$PWD/Artwork/AppIcon.png" "$APP/Contents/Resources/AppIcon.icns"
# Ship the software license and the separate artwork scope with every distribution.
cp ../LICENSE "$APP/Contents/Resources/LICENSE"
cp ../LICENSE-SCOPE.md "$APP/Contents/Resources/LICENSE-SCOPE.md"
cp Artwork/NOTICE.md "$APP/Contents/Resources/ARTWORK-NOTICE.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.VNLauncher</string>
<key>CFBundleName</key><string>Shiroha</string>
<key>CFBundleDisplayName</key><string>白羽 Shiroha</string>
<key>CFBundleExecutable</key><string>VNLauncher</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.14.0</string>
<key>CFBundleVersion</key><string>14</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Finder/FileProvider may attach FinderInfo to generated bundles in Documents.
# Remove only signing-incompatible metadata from this generated app, never quarantine.
xattr -dr com.apple.FinderInfo "$APP" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$APP" 2>/dev/null || true
codesign --force --sign - "$APP"
codesign --verify --strict "$APP"
mkdir -p "$(dirname "$DESTINATION")"
mkdir -p "$PWD/build"
ditto -c -k --norsrc --keepParent "$APP" "$DESTINATION"
printf '%s\n' "$APP" > "$PWD/build/verified-app-path.txt"
printf '%s\n' "$DESTINATION"
