#!/usr/bin/env bash
# Publishes the package made by package.sh as a GitHub release, with the appcast
# Sparkle reads: every Chord then finds the update within a day.
#
#   engine/scripts/release.sh                 # asks before publishing
#   engine/scripts/release.sh --notes <file>  # release notes (else GitHub writes them)
#
# The appcast lists this release only, signed with the private key in the keychain
# (sparkle-tool.sh generate_keys). Each release carries its own appcast.xml, and the
# feed points at the latest release's.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
REPOSITORY="kevbesset/Chord"
VERSION="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"
TAG="v$VERSION"
DMG="$REPO_DIR/dist/Chord-$VERSION.dmg"
APPCAST="$REPO_DIR/dist/appcast.xml"
NOTES=()
[ "${1:-}" = "--notes" ] && NOTES=(--notes-file "${2:?notes file}") || NOTES=(--generate-notes)

[ -f "$DMG" ] || { echo "No $DMG: run engine/scripts/package.sh first"; exit 1; }
if gh release view "$TAG" --repo "$REPOSITORY" >/dev/null 2>&1; then
  echo "Version $VERSION is already published: change VERSION."
  exit 1
fi
# The release is tagged on the commit the package was made from, which GitHub must have.
COMMIT="$(git -C "$REPO_DIR" rev-parse HEAD)"
git -C "$REPO_DIR" branch -r --contains "$COMMIT" | grep -q . || {
  echo "Commit $COMMIT is not pushed yet."
  exit 1
}

# The build number and minimum macOS, as package.sh wrote them into the app.
MOUNT="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT" "$DMG" >/dev/null
INFO="$MOUNT/Chord.app/Contents/Info.plist"
BUILD="$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO")"
MINIMUM="$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO")"
hdiutil detach "$MOUNT" >/dev/null

# sparkle:edSignature="…" length="…"
SIGNATURE="$("$ENGINE_DIR/scripts/sparkle-tool.sh" sign_update "$DMG")"
cat > "$APPCAST" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Chord</title>
    <item>
      <title>Chord $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$MINIMUM</sparkle:minimumSystemVersion>
      <sparkle:releaseNotesLink>https://github.com/$REPOSITORY/releases/tag/$TAG</sparkle:releaseNotesLink>
      <enclosure url="https://github.com/$REPOSITORY/releases/download/$TAG/$(basename "$DMG")" type="application/octet-stream" $SIGNATURE/>
    </item>
  </channel>
</rss>
XML

echo "Chord $VERSION ($BUILD): $(basename "$DMG"), $(du -h "$DMG" | cut -f1), commit ${COMMIT:0:7}"
read -r -p "Publish on github.com/$REPOSITORY? [y/N] " answer
[ "$answer" = "y" ] || { echo "Nothing published."; exit 0; }
gh release create "$TAG" "$DMG" "$APPCAST" --repo "$REPOSITORY" --target "$COMMIT" \
  --title "Chord $VERSION" "${NOTES[@]}"
