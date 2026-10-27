#!/usr/bin/env bash
# Makes the Chord that is shared: a copy of Chord.app with Chord's version and its
# update feed, signed, notarized when it can be, in a disk image (dist/Chord-<v>.dmg).
#
#   engine/scripts/package.sh            # from out/Release (build.sh --release)
#   engine/scripts/package.sh --dev      # from out/Chord, to try the packaging quickly
#
# The version is in VERSION; the build number counts the commits, so each package is
# newer than the last for Sparkle. Notarization needs a "Developer ID Application"
# certificate and notarytool credentials saved once:
#   xcrun notarytool store-credentials chord-notary --apple-id … --team-id …
# Without them the image is signed but not notarized: macOS asks, on other Macs, to
# open Chord from System Settings › Privacy & Security the first time.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
SRC="$ENGINE_DIR/vendor/ungoogled-chromium-macos/build/src"
OUT="$SRC/out/Release"
[ "${1:-}" = "--dev" ] && OUT="$SRC/out/Chord"
[ -d "$OUT/Chord.app" ] || { echo "No Chord.app in $OUT: run engine/scripts/build.sh --release first"; exit 1; }

VERSION="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"
BUILD="$(git -C "$REPO_DIR" rev-list --count HEAD)"
# Updates: the appcast of the latest GitHub release, signed with the private key
# sparkle-tool.sh generate_keys left in the keychain.
FEED="https://github.com/kevbesset/Chord/releases/latest/download/appcast.xml"
PUBLIC_KEY="9a/1hLnT8TfuXx/kzX5BWj1zhzY7voL4bsVu9SU9N3M="
NOTARY_PROFILE="${CHORD_NOTARY_PROFILE:-chord-notary}"

DIST="$REPO_DIR/dist"
STAGE="$DIST/stage"
APP="$STAGE/Chord.app"
DMG="$DIST/Chord-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
ditto "$OUT/Chord.app" "$APP"

plist() {
  /usr/libexec/PlistBuddy -c "Delete :$1" "$APP/Contents/Info.plist" 2>/dev/null || true
  /usr/libexec/PlistBuddy -c "Add :$1 $2 $3" "$APP/Contents/Info.plist"
}
plist CFBundleShortVersionString string "$VERSION"
plist CFBundleVersion string "$BUILD"
# ChordUI needs macOS 14.
plist LSMinimumSystemVersion string 14.0
plist SUFeedURL string "$FEED"
plist SUPublicEDKey string "$PUBLIC_KEY"
# Like Arc: checks on its own, downloads in the background, installs at the next launch.
plist SUEnableAutomaticChecks bool true
plist SUAutomaticallyUpdate bool true

"$ENGINE_DIR/scripts/sign.sh" "$APP"
IDENTITY="$(codesign -dvv "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1)"

# The disk image: Chord and a link to Applications, to drag it into. APFS, as
# Chromium's pkg-dmg (HFS+) leaves Finder information on every file, which breaks the
# signature of the copies.
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname Chord -srcfolder "$STAGE" -fs APFS -format ULFO -ov "$DMG"
rm -rf "$STAGE"

if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then
  codesign --sign "$IDENTITY" --timestamp "$DMG"
  if xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
    # Notarizing the image covers the app inside it; the ticket is stapled to the
    # image, and Gatekeeper finds the app's online.
    xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG"
    NOTARIZED="notarized"
  else
    NOTARIZED="not notarized (no notarytool credentials \"$NOTARY_PROFILE\")"
  fi
elif [ -n "$IDENTITY" ]; then
  codesign --sign "$IDENTITY" --timestamp=none "$DMG"
  NOTARIZED="not notarized (needs a Developer ID Application certificate)"
else
  NOTARIZED="not notarized (signed ad hoc)"
fi

echo "Chord $VERSION ($BUILD), $NOTARIZED: $DMG"
