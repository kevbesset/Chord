#!/usr/bin/env bash
# Builds Chord on Chromium: ChordUI with Xcode, then Chromium with //chord, then puts
# ChordUI inside the app. Run engine/scripts/prepare.sh once before.
#
#   engine/scripts/build.sh              # out/Chord/Chord.app, for development
#   engine/scripts/build.sh --release    # out/Release/Chord.app, what Chord ships
#   engine/scripts/build.sh --gen        # also regenerate the GN build files
#
# Development settings (chord.gn): no LTO, no PGO, no symbols. Release (chord-release.gn
# on top): an official build with link-time optimization. The first build of each takes
# a few hours, the next ones only rebuild what changed. The app is then signed
# (sign.sh).
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REPO_DIR="$(cd "$ENGINE_DIR/.." && pwd)"
ROOT="$ENGINE_DIR/vendor/ungoogled-chromium-macos"
SRC="$ROOT/build/src"
RELEASE=false
GEN=false
for arg in "$@"; do
  case "$arg" in
    --release) RELEASE=true ;;
    --gen) GEN=true ;;
  esac
done
OUT="$SRC/out/Chord"
$RELEASE && OUT="$SRC/out/Release"
export PATH="/opt/homebrew/opt/python@3.13/libexec/bin:$PATH"
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

[ -f "$SRC/.chord-prepared" ] || { echo "Run engine/scripts/prepare.sh first"; exit 1; }

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

# Chord's logo where Chromium's own pages show Chromium's (settings, extensions, about):
# engine/branding/src mirrors the source tree. Only changed files are copied, so that
# the resources are not rebuilt each time.
rsync -rc "$ENGINE_DIR/branding/src/" "$SRC/"

if [ ! -f "$OUT/args.gn" ] || $GEN; then
  mkdir -p "$OUT/sdk"
  ln -sfn "$SDKROOT" "$OUT/sdk/MacOSX26.5.sdk"
  # Chord's arguments: chord.gn, and for a release chord-release.gn over it.
  chord_args="$(cat "$ENGINE_DIR/chord.gn")"
  if $RELEASE; then
    release_keys="$(grep -oE '^[a-z_0-9]+' "$ENGINE_DIR/chord-release.gn" | sort -u)"
    chord_args="$(grep -vE "^($(echo $release_keys | tr ' ' '|'))[[:space:]]*=" <<< "$chord_args"; cat "$ENGINE_DIR/chord-release.gn")"
  fi
  # ungoogled-chromium's arguments, minus those Chord sets (GN refuses to assign an
  # argument twice), then Chord's.
  ours="$(grep -oE '^[a-z_0-9]+' <<< "$chord_args" | sort -u)"
  {
    cat "$ROOT/ungoogled-chromium/flags.gn" "$ROOT/flags.macos.gn" \
      | grep -vE "^($(echo $ours | tr ' ' '|'))[[:space:]]*="
    echo 'target_cpu = "arm64"'
    echo "$chord_args"
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
for framework in ChordUI Sparkle; do
  rm -rf "$FRAMEWORKS/$framework.framework"
  [ -d "$REPO_DIR/app/build/release/$framework.framework" ] && \
    cp -R "$REPO_DIR/app/build/release/$framework.framework" "$FRAMEWORKS/"
done
"$ENGINE_DIR/scripts/sign.sh" "$APP"
echo "Ready: $APP"
