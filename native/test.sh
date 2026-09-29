#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p work/swift-module-cache
xcrun swiftc native/main.swift native/RegressionTests.swift -D REGRESSION_TESTS \
  -framework AppKit -target arm64-apple-macosx13.0 -O -g \
  -module-cache-path "$(pwd)/work/swift-module-cache" -o work/SimpleBoardRegressionTests
work/SimpleBoardRegressionTests
