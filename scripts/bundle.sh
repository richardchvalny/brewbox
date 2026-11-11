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

# Some Command Line Tools releases ship an SDK whose SwiftUI turns @State into a
# macro but leave out the SwiftUIMacros plugin, so nothing using @State compiles.
# Unless SDKROOT is set, check the default SDK with a tiny @State view and fall
# back to the newest installed SDK that can build it.
sdk_builds_swiftui() {
    xcrun swiftc -typecheck -target "$(uname -m)-apple-macos14.0" -sdk "$1" "$PROBE" >/dev/null 2>&1
}

if [[ -z "${SDKROOT:-}" ]]; then
    PROBE="$(mktemp -d)/Probe.swift"
    printf 'import SwiftUI\nstruct Probe: View { @State var n = 0; var body: some View { Text("\\(n)") } }\n' > "$PROBE"
    DEFAULT_SDK="$(xcrun --show-sdk-path)"
    if ! sdk_builds_swiftui "$DEFAULT_SDK"; then
        for SDK in $(ls -d "$(dirname "$DEFAULT_SDK")"/MacOSX[0-9]*.sdk 2>/dev/null | sort -rV); do
            if sdk_builds_swiftui "$SDK"; then
                echo "warning: $(basename "$DEFAULT_SDK") can't build SwiftUI @State here, using $(basename "$SDK")" >&2
                export SDKROOT="$SDK"
                break
            fi
        done
        [[ -n "${SDKROOT:-}" ]] || echo "warning: no installed SDK passed the SwiftUI check, building with the default" >&2
    fi
    rm -rf "$(dirname "$PROBE")"
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

if [[ "$UNIVERSAL" == 1 ]]; then
    # Newer SwiftPM builds every --arch into the same bin path, so copy each
    # binary aside before the next build overwrites it.
    BINARIES=()
    for ARCH in arm64 x86_64; do
        swift build -c release --arch "$ARCH"
        cp "$(swift build -c release --arch "$ARCH" --show-bin-path)/Brewbox" "build/Brewbox-$ARCH"
        BINARIES+=("build/Brewbox-$ARCH")
    done
    lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/Brewbox"
    rm -f "${BINARIES[@]}"
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
