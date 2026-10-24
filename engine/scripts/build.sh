#!/usr/bin/env bash
# Builds Chord on Chromium: ChordUI with Xcode, then Chromium with //chord, then puts
# ChordUI inside the app. Run engine/scripts/prepare.sh once before.
#
#   engine/scripts/build.sh            # out/Chord/Chord.app
#   engine/scripts/build.sh --gen      # also regenerate the GN build files
#
# Development settings: no LTO, no PGO, no symbols. The first build takes a few hours,
# the next ones only rebuild what changed.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
ROOT="$ENGINE_DIR/vendor/ungoogled-chromium-macos"
SRC="$ROOT/build/src"
OUT="$SRC/out/Chord"
export PATH="/opt/homebrew/opt/python@3.13/libexec/bin:$PATH"
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

[ -f "$SRC/.chord-prepared" ] || { echo "Lancer d'abord engine/scripts/prepare.sh"; exit 1; }

# //chord lives in this repository; Chromium sees it at src/chord.
ln -sfn "$ENGINE_DIR/chord" "$SRC/chord"

# Chord's patches, in the order of patches/series, applied once each (each leaves a
# marker in the source tree).
while read -r name; do
  [ -n "$name" ] || continue
  patch="$ENGINE_DIR/patches/$name"
  marker="$SRC/.chord-patch-$name"
  if [ ! -f "$marker" ]; then
    echo "Patch $(basename "$patch")"
    patch -d "$SRC" -p1 --forward < "$patch"
    touch "$marker"
  fi
done < "$ENGINE_DIR/patches/series"

if [ ! -f "$OUT/args.gn" ] || [ "${1:-}" = "--gen" ]; then
  mkdir -p "$OUT/sdk"
  ln -sfn "$SDKROOT" "$OUT/sdk/MacOSX26.5.sdk"
  # ungoogled-chromium's arguments, minus those chord.gn sets (GN refuses to assign
  # an argument twice), then chord.gn's.
  ours="$(grep -oE '^[a-z_0-9]+' "$ENGINE_DIR/chord.gn" | sort -u)"
  {
    cat "$ROOT/ungoogled-chromium/flags.gn" "$ROOT/flags.macos.gn" \
      | grep -vE "^($(echo $ours | tr ' ' '|'))[[:space:]]*="
    echo 'target_cpu = "arm64"'
    cat "$ENGINE_DIR/chord.gn"
  } > "$OUT/args.gn"
  (cd "$SRC" && ./out/gn gen "$OUT")
fi

# ChordUI.framework, loaded by //chord at run time.
(cd "$REPO_DIR/app" && xcodegen generate >/dev/null && \
  xcodebuild -project Chord.xcodeproj -target ChordUI -configuration Release \
    CONFIGURATION_BUILD_DIR="$REPO_DIR/app/build/release" build | grep -E "error:|BUILD" || true)

caffeinate -i ninja -C "$OUT" chrome

APP="$OUT/Chord.app"
FRAMEWORKS="$APP/Contents/Frameworks"
rm -rf "$FRAMEWORKS/ChordUI.framework"
cp -R "$REPO_DIR/app/build/release/ChordUI.framework" "$FRAMEWORKS/"
codesign --force --sign - "$FRAMEWORKS/ChordUI.framework" >/dev/null 2>&1 || true
echo "Prêt : $APP"
