#!/usr/bin/env bash
# The everyday loop for the interface: rebuilds ChordUI only, puts it in Chord.app and
# relaunches Chord. A few seconds, no Chromium build: ChordUI is loaded at run time.
# engine/scripts/build.sh must have built Chord.app once (and again after changes to
# //chord or the patches).
#
#   engine/scripts/run.sh                         # rebuild ChordUI, relaunch Chord
#   engine/scripts/run.sh --no-build              # relaunch only
#   engine/scripts/run.sh --framework <path>      # install that ChordUI build, relaunch
#                                                 # (what Xcode's Chord scheme does)
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
APP="$ENGINE_DIR/vendor/ungoogled-chromium-macos/build/src/out/Chord/Chord.app"
FRAMEWORK="$REPO_DIR/app/build/debug/ChordUI.framework"
BUILD=true
INSTALL=true

case "${1:-}" in
  --no-build) BUILD=false; INSTALL=false ;;
  --framework) BUILD=false; FRAMEWORK="${2:?chemin de ChordUI.framework}" ;;
esac

[ -d "$APP" ] || { echo "Construire d'abord Chord : engine/scripts/build.sh"; exit 1; }

if $BUILD; then
  (cd "$REPO_DIR/app" && xcodegen generate >/dev/null && \
    xcodebuild -project Chord.xcodeproj -target ChordUI -configuration Debug \
      CONFIGURATION_BUILD_DIR="$(dirname "$FRAMEWORK")" build | grep -E "error:|BUILD")
fi

# Quit Chord properly, so that it saves its session.
if pgrep -x Chord >/dev/null; then
  osascript -e 'tell application id "app.chord.Chord" to quit' >/dev/null 2>&1 || true
  for _ in $(seq 1 50); do pgrep -x Chord >/dev/null || break; sleep 0.2; done
fi

if $INSTALL; then
  rm -rf "$APP/Contents/Frameworks/ChordUI.framework"
  cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"
  codesign --force --sign - "$APP/Contents/Frameworks/ChordUI.framework" >/dev/null 2>&1 || true
fi

open "$APP"
