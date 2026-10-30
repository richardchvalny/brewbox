#!/usr/bin/env bash
# Builds a release binary and wraps it in a minimal .app bundle.
#
#   UNIVERSAL=1      build for both Apple silicon and Intel (default: this Mac only)
#   SIGN_IDENTITY=…  codesign identity (default: "-", an ad-hoc signature)
set -euo pipefail

cd "$(dirname "$0")/.."

UNIVERSAL="${UNIVERSAL:-0}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
APP="build/Brewbox.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$UNIVERSAL" == 1 ]]; then
    BINARIES=()
    for ARCH in arm64 x86_64; do
        swift build -c release --arch "$ARCH"
        BINARIES+=("$(swift build -c release --arch "$ARCH" --show-bin-path)/Brewbox")
    done
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Brewbox"
else
    swift build -c release
    cp "$(swift build -c release --show-bin-path)/Brewbox" "$APP/Contents/MacOS/"
fi

cp Support/Info.plist "$APP/Contents/"
cp Support/AppIcon.icns "$APP/Contents/Resources/"

# The marketing version lives in Support/Info.plist; the build number is the
# git commit count, so each build of a new commit gets a higher one.
if git rev-parse --git-dir >/dev/null 2>&1; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(git rev-list --count HEAD)" "$APP/Contents/Info.plist"
fi

if [[ "$SIGN_IDENTITY" == "-" ]]; then
    # Ad-hoc signature: enough for notifications and login items on this Mac.
    codesign --force --sign - "$APP"
else
    # Developer ID with hardened runtime and a secure timestamp, as notarization requires.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
fi

echo "Built $APP"
