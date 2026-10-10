#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/swift-module-cache outputs
STAGING="$(mktemp -d "$(pwd)/work/app-build.XXXXXX")"
APP="$STAGING/简笔白板.app"
DEST="$(pwd)/outputs/简笔白板.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
test -f assets/AppIcon.icns || bash native/build-icon.sh
xcrun swiftc native/main.swift native/StyleControls.swift \
  -whole-module-optimization -c -o work/SimpleBoard.o -module-name SimpleBoard \
  -framework AppKit -target arm64-apple-macosx13.0 -O -g \
  -module-cache-path "$(pwd)/work/swift-module-cache"
xcrun swiftc work/SimpleBoard.o -o work/SimpleBoard \
  -framework AppKit -target arm64-apple-macosx13.0 -g
cp work/SimpleBoard "$APP/Contents/MacOS/SimpleBoard"
xcrun strip -S "$APP/Contents/MacOS/SimpleBoard"
cp native/Info.plist "$APP/Contents/Info.plist"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE"
codesign --force --sign - "$APP"
codesign --verify --deep --strict "$APP"
ditto -c -k --norsrc --keepParent "$APP" "$(pwd)/outputs/简笔白板-macOS.zip"
# Keep the previous local output recoverable; never merge stale bundle files.
if [ -e "$DEST" ]; then mv "$DEST" "$STAGING/previous.app"; fi
ditto --norsrc "$APP" "$DEST"
echo "Built: $DEST"
