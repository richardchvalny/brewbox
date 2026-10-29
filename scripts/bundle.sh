#!/usr/bin/env bash
# Builds a release binary and wraps it in a minimal .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Homebrew Toolbox.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/HomebrewToolbox" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"

# Ad-hoc signature: enough for notifications and login items on this Mac.
codesign --force --sign - "$APP"

echo "Built $APP"
