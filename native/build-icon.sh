#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/swift-module-cache
xcrun swiftc assets/DrawIcon.swift -framework AppKit \
  -module-cache-path "$(pwd)/work/swift-module-cache" -o work/DrawIcon
work/DrawIcon
