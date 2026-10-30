#!/usr/bin/env bash
# Installs or updates Brewbox from the latest GitHub release:
#
#   curl -fsSL https://raw.githubusercontent.com/richardchvalny/brewbox/main/scripts/install.sh | bash
#
# curl doesn't quarantine what it downloads, so the app opens without a Gatekeeper prompt.
# BREWBOX_ZIP_URL and BREWBOX_INSTALL_DIR point it at another zip and folder (for testing
# a build before releasing it).
set -euo pipefail

ZIP_URL="${BREWBOX_ZIP_URL:-https://github.com/richardchvalny/brewbox/releases/latest/download/Brewbox.zip}"

fail() { echo "Error: $*" >&2; exit 1; }

[[ "$(uname -s)" == Darwin ]] || fail "Brewbox runs on macOS only."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d . -f 1)"
(( MACOS_MAJOR >= 14 )) || fail "Brewbox needs macOS 14 or later (this Mac has $(sw_vers -productVersion))."

# /Applications when we can write to it (admin accounts), ~/Applications otherwise.
if [[ -n "${BREWBOX_INSTALL_DIR:-}" ]]; then
    DEST="$BREWBOX_INSTALL_DIR"
    mkdir -p "$DEST"
elif [[ -w /Applications ]]; then
    DEST=/Applications
else
    DEST="$HOME/Applications"
    mkdir -p "$DEST"
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "Downloading Brewbox…"
curl -fL --progress-bar "$ZIP_URL" -o "$TMP/Brewbox.zip" || fail "Couldn't download $ZIP_URL"
ditto -x -k "$TMP/Brewbox.zip" "$TMP"
[[ -d "$TMP/Brewbox.app" ]] || fail "The download doesn't contain Brewbox.app."

if pgrep -xq Brewbox; then
    echo "Quitting the running Brewbox…"
    pkill -x Brewbox || true
    for _ in {1..20}; do pgrep -xq Brewbox || break; sleep 0.25; done
fi

rm -rf "$DEST/Brewbox.app"
mv "$TMP/Brewbox.app" "$DEST/"
xattr -dr com.apple.quarantine "$DEST/Brewbox.app" 2>/dev/null || true

VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$DEST/Brewbox.app/Contents/Info.plist")"
echo "Installed Brewbox $VERSION in $DEST. It lives in the menu bar."
open "$DEST/Brewbox.app"
