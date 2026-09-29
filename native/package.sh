#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash native/build.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' native/Info.plist)"
STAGING="$(mktemp -d "$(pwd)/work/source-package.XXXXXX")"
SOURCE="$STAGING/SimpleBoard"
mkdir -p "$SOURCE"
# Explicit allowlist: no git history, hosting data, caches, logs or credentials.
cp README.md CHANGELOG.md .gitignore "$SOURCE/"
ditto --norsrc native "$SOURCE/native"
ditto --norsrc assets "$SOURCE/assets"
ditto --norsrc docs "$SOURCE/docs"
if [ -f LICENSE ]; then
  cp LICENSE "$SOURCE/LICENSE"
else
  echo "NOTICE: License is not selected. Do not publish as open source yet."
fi
ditto -c -k --norsrc --keepParent "$SOURCE" "outputs/SimpleBoard-v$VERSION-source.zip"
cp "outputs/简笔白板-macOS.zip" "outputs/SimpleBoard-v$VERSION-macOS-arm64.zip"
cp "outputs/SimpleBoard-v$VERSION-source.zip" "outputs/简笔白板-源码.zip"
# Stable relative names allow verification after downloading elsewhere.
(cd outputs && shasum -a 256 "SimpleBoard-v$VERSION-macOS-arm64.zip" \
  "SimpleBoard-v$VERSION-source.zip" > "SimpleBoard-v$VERSION-SHA256SUMS.txt")
echo "Packaged SimpleBoard $VERSION into outputs/"
