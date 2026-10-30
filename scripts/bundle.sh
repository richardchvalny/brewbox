#!/usr/bin/env bash
# Builds a release binary and wraps it in a minimal .app bundle.
set -euo pipefail

cd "$(dirname "$0")/.."

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Brewbox.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Brewbox" "$APP/Contents/MacOS/"
cp Support/Info.plist "$APP/Contents/"
cp Support/AppIcon.icns "$APP/Contents/Resources/"

# The marketing version lives in Support/Info.plist; the build number is the
# git commit count, so each build of a new commit gets a higher one.
if git rev-parse --git-dir >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
fi

# Ad-hoc signature: enough for notifications and login items on this Mac.
codesign --force --sign - "$APP"

echo "Built $APP"
