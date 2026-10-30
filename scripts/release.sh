#!/usr/bin/env bash
# Builds a universal build/Brewbox.dmg (to download from the website) and
# build/Brewbox.zip (for scripts/install.sh), ready to attach to a GitHub release.
#
#   SIGN_IDENTITY=…   codesign identity (default: the first "Developer ID Application"
#                     certificate in the keychain)
#   NOTARY_PROFILE=…  notarytool keychain profile (default: brewbox), saved once with
#                     xcrun notarytool store-credentials brewbox
#   UNSIGNED=1        ad-hoc signed and not notarized: free to make, but Gatekeeper asks
#                     people to allow the downloaded DMG in System Settings (the curl
#                     install isn't affected)
set -euo pipefail

cd "$(dirname "$0")/.."

UNSIGNED="${UNSIGNED:-0}"
NOTARY_PROFILE="${NOTARY_PROFILE:-brewbox}"
APP="build/Brewbox.app"
DMG="build/Brewbox.dmg"
ZIP="build/Brewbox.zip"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Support/Info.plist)"

if [[ "$UNSIGNED" == 1 ]]; then
    SIGN_IDENTITY="-"
else
    SIGN_IDENTITY="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
        | sed -n 's/.*"\(Developer ID Application: .*\)"/\1/p' | head -n 1)}"
    if [[ -z "$SIGN_IDENTITY" ]]; then
        echo "No \"Developer ID Application\" certificate in the keychain." >&2
        echo "Create one at developer.apple.com (Certificates, IDs & Profiles), or run" >&2
        echo "UNSIGNED=1 make release for a free, unnotarized build." >&2
        exit 1
    fi
fi

if [[ -n "$(git status --porcelain -- Sources Support Package.swift)" ]]; then
    echo "warning: uncommitted changes in Sources/Support go into this build" >&2
fi

UNIVERSAL=1 SIGN_IDENTITY="$SIGN_IDENTITY" ./scripts/bundle.sh
codesign --verify --strict --verbose=2 "$APP"

# Disk image with the app and an Applications shortcut to drag it onto.
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG" "$ZIP"
hdiutil create -volname "Brewbox" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

if [[ "$UNSIGNED" != 1 ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

    # Apple scans the image; stapling attaches the ticket so it opens offline too.
    # The ticket covers the app inside, so the app gets it as well before zipping.
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler staple "$APP"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
fi

ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "Built $DMG and $ZIP (version $VERSION, build $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$APP/Contents/Info.plist"))"
[[ "$UNSIGNED" == 1 ]] && echo "Not signed or notarized."
echo "sha256: $(shasum -a 256 "$DMG" | cut -d ' ' -f 1)  Brewbox.dmg"
echo "sha256: $(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)  Brewbox.zip"
echo
echo "Publish with:"
echo "  gh release create v$VERSION $DMG $ZIP --title \"Brewbox $VERSION\" --generate-notes"
