#!/usr/bin/env bash
# The everyday loop for the interface: rebuilds ChordUI only, puts it in Chord.app and
# relaunches Chord. A few seconds, no Chromium build: ChordUI is loaded at run time.
# engine/scripts/build.sh must have built Chord.app once (and again after changes to
# //chord or the patches).
#
# Without a Chromium build, ChordUI goes into a copy of the latest Chord release,
# downloaded once into app/build/prebuilt (CONTRIBUTING.md). That copy has its own data
# folder and never updates itself; it works as long as ChordUI needs nothing newer from
# //chord than the release has.
#
#   engine/scripts/run.sh                         # rebuild ChordUI, relaunch Chord
#   engine/scripts/run.sh --no-build              # relaunch only
#   engine/scripts/run.sh --framework <path>      # install that ChordUI build, relaunch
#                                                 # (what Xcode's Chord scheme does)
#   engine/scripts/run.sh --update-prebuilt       # download the latest release again
#                                                 # (without a Chromium build)
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
APP="$ENGINE_DIR/vendor/ungoogled-chromium-macos/build/src/out/Chord/Chord.app"
FRAMEWORK="$REPO_DIR/app/build/debug/ChordUI.framework"
PREBUILT_DIR="$REPO_DIR/app/build/prebuilt"
BUILD=true
INSTALL=true
UPDATE_PREBUILT=false

case "${1:-}" in
  --no-build) BUILD=false; INSTALL=false ;;
  --framework) BUILD=false; FRAMEWORK="${2:?chemin de ChordUI.framework}" ;;
  --update-prebuilt) UPDATE_PREBUILT=true ;;
esac

PREBUILT=false
if [ ! -d "$APP" ]; then
  PREBUILT=true
  APP="$PREBUILT_DIR/Chord.app"
fi

# The latest release's Chord.app, without its updates (Sparkle starts only with a feed).
fetch_prebuilt() {
  local url tag
  tmp="$(mktemp -d)"
  trap 'hdiutil detach -quiet "$tmp/mount" 2>/dev/null || true; rm -rf "$tmp"' EXIT
  curl -fsSL https://api.github.com/repos/kevbesset/Chord/releases/latest > "$tmp/release.json"
  tag="$(python3 -c 'import json, sys; print(json.load(sys.stdin)["tag_name"])' < "$tmp/release.json")"
  url="$(python3 -c 'import json, sys; print(next(a["browser_download_url"] for a in json.load(sys.stdin)["assets"] if a["name"].endswith(".dmg")))' < "$tmp/release.json")"
  echo "No Chromium build here: downloading Chord $tag to put ChordUI in (once)…"
  curl -fL --progress-bar -o "$tmp/Chord.dmg" "$url"
  hdiutil attach -quiet -nobrowse -readonly -mountpoint "$tmp/mount" "$tmp/Chord.dmg"
  rm -rf "$APP"
  mkdir -p "$PREBUILT_DIR"
  ditto "$tmp/mount/Chord.app" "$APP"
  /usr/libexec/PlistBuddy -c "Delete :SUFeedURL" "$APP/Contents/Info.plist" 2>/dev/null || true
  echo "${tag#v}" > "$PREBUILT_DIR/VERSION"
}

if $PREBUILT; then
  if $UPDATE_PREBUILT || [ ! -d "$APP" ]; then
    fetch_prebuilt
    INSTALL=true
    [ -d "$FRAMEWORK" ] || BUILD=true
  fi
  release="$(cat "$PREBUILT_DIR/VERSION" 2>/dev/null || echo "?")"
  source="$(tr -d '[:space:]' < "$REPO_DIR/VERSION")"
  if [ "$release" != "$source" ]; then
    echo "Note: ChordUI is $source, the Chord it goes into is release $release." \
      "If it crashes on launch, see CONTRIBUTING.md."
  fi
elif $UPDATE_PREBUILT; then
  echo "There is a Chromium build: run.sh uses it, not a release."
fi

if $BUILD; then
  (cd "$REPO_DIR/app" && xcodegen generate >/dev/null && \
    xcodebuild -project Chord.xcodeproj -target ChordUI -configuration Debug \
      CONFIGURATION_BUILD_DIR="$(dirname "$FRAMEWORK")" build | grep -E "error:|BUILD")
fi

# Quit Chord properly, so that it saves its session. The release copy shares its
# identity with the Chord the contributor browses with: only that copy is quit.
if $PREBUILT; then
  if pkill -TERM -f "^$APP/Contents/MacOS/Chord" 2>/dev/null; then
    for _ in $(seq 1 50); do pgrep -f "^$APP/Contents/MacOS/Chord" >/dev/null || break; sleep 0.2; done
  fi
elif pgrep -x Chord >/dev/null; then
  osascript -e 'tell application id "app.chord.Chord" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do pgrep -x Chord >/dev/null || break; sleep 0.2; done
fi

if $INSTALL; then
  rm -rf "$APP/Contents/Frameworks/ChordUI.framework"
  cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
  # Sparkle (updates) comes with ChordUI.
  SPARKLE="$(dirname "$FRAMEWORK")/Sparkle.framework"
  if [ -d "$SPARKLE" ]; then
    rm -rf "$APP/Contents/Frameworks/Sparkle.framework"
    cp -R "$SPARKLE" "$APP/Contents/Frameworks/"
  fi
  # The release's Chromium is signed by Kevin: only ad hoc does the copy accept a
  # ChordUI signed by someone else.
  if $PREBUILT; then
    CHORD_SIGN_IDENTITY=- "$ENGINE_DIR/scripts/sign.sh" "$APP" --quick >/dev/null
  elif ! codesign --verify "$APP/Contents/Frameworks/Chord Framework.framework" 2>/dev/null; then
    # Chromium was rebuilt without build.sh (ninja alone), which signs it at the end:
    # macOS would refuse to launch Chord. Everything is signed again.
    "$ENGINE_DIR/scripts/sign.sh" "$APP" >/dev/null
  else
    "$ENGINE_DIR/scripts/sign.sh" "$APP" --quick >/dev/null
  fi
fi

if $PREBUILT; then
  # Its own data folder, apart from the Chord used day to day.
  open -n "$APP" --args --user-data-dir="$PREBUILT_DIR/data"
else
  open "$APP"
fi
