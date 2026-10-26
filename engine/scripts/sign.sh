#!/usr/bin/env bash
# Signs Chord.app from the inside out, as ungoogled-chromium's sign_and_package_app.sh
# does: helpers, libraries, frameworks, then the app with its entitlements and the
# hardened runtime.
#
#   engine/scripts/sign.sh <Chord.app>           # every part (after a Chromium build)
#   engine/scripts/sign.sh <Chord.app> --quick   # ChordUI, Sparkle and the app (run.sh)
#
# The identity: $CHORD_SIGN_IDENTITY, else a "Developer ID Application" certificate
# (needed to notarize), else an "Apple Development" one, else ad hoc. A certificate
# keeps Chord's signature the same from build to build: the keychain lets Chord in
# without asking again, and Chord uses the real keychain. Ad hoc, Chord keeps its key
# in Chromium's mock keychain.
set -euo pipefail

APP="${1:?Chemin de Chord.app}"
QUICK="${2:-}"
ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENTITLEMENTS="$ENGINE_DIR/vendor/ungoogled-chromium-macos/entitlements"

identity() {
  if [ -n "${CHORD_SIGN_IDENTITY:-}" ]; then
    echo "$CHORD_SIGN_IDENTITY"
    return
  fi
  local identities
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  for kind in "Developer ID Application" "Apple Development"; do
    local found
    found="$(grep -o "\"$kind: [^\"]*\"" <<< "$identities" | head -1 | tr -d '"')"
    if [ -n "$found" ]; then
      echo "$found"
      return
    fi
  done
  echo "-"
}

ID="$(identity)"
TIMESTAMP="--timestamp=none"
# Notarization wants a secure timestamp, from Apple's server.
[[ "$ID" == "Developer ID Application:"* ]] && TIMESTAMP="--timestamp"

sign() {
  if [ "$ID" = "-" ]; then
    # The hardened runtime validates libraries by team ID, which ad hoc code has none
    # of: Chord could not load its own framework. Ad hoc, no runtime options, as the
    # linker signs.
    local args=() skip=false
    for arg in "$@"; do
      if $skip; then skip=false; continue; fi
      [ "$arg" = "--options" ] && { skip=true; continue; }
      args+=("$arg")
    done
    codesign --sign - --force "${args[@]}"
  else
    codesign --sign "$ID" --force "$TIMESTAMP" "$@"
  fi
}

FRAMEWORKS="$APP/Contents/Frameworks"
CHROMIUM="$FRAMEWORKS/Chord Framework.framework"
HELPERS="$CHROMIUM/Helpers"

if [ "$QUICK" != "--quick" ]; then
  # Extended attributes would break the signature (and ask for network access).
  xattr -cr "$APP"
  sign --identifier app.chord.Chord.crashpad_handler --options restrict,library,runtime,kill \
    "$HELPERS/chrome_crashpad_handler"
  for helper in "$HELPERS"/*.app; do
    case "$helper" in
      *Renderer*) sign --options restrict,kill,runtime --entitlements "$ENTITLEMENTS/helper-renderer-entitlements.plist" "$helper" ;;
      *GPU*) sign --options restrict,kill,runtime --entitlements "$ENTITLEMENTS/helper-gpu-entitlements.plist" "$helper" ;;
      # The generic helper also loads Google's Widevine module (protected videos),
      # signed by another team: it may load libraries signed by others.
      */"Chord Helper.app") sign --options restrict,kill,runtime --entitlements "$ENTITLEMENTS/helper-plugin-entitlements.plist" "$helper" ;;
      *) sign --options restrict,library,runtime,kill "$helper" ;;
    esac
  done
  for tool in app_mode_loader web_app_shortcut_copier; do
    [ -e "$HELPERS/$tool" ] && sign --identifier "app.chord.Chord.$tool" --options restrict,library,runtime,kill "$HELPERS/$tool"
  done
  for dylib in "$CHROMIUM/Libraries"/*.dylib; do
    [ -e "$dylib" ] && sign --identifier "$(basename "$dylib" .dylib)" "$dylib"
  done
  sign "$CHROMIUM"
fi

# Sparkle, inside out: its updater and XPC services first.
SPARKLE="$FRAMEWORKS/Sparkle.framework"
if [ -d "$SPARKLE" ]; then
  for part in "$SPARKLE"/Versions/B/XPCServices/*.xpc "$SPARKLE/Versions/B/Autoupdate" "$SPARKLE/Versions/B/Updater.app"; do
    [ -e "$part" ] && sign --options runtime "$part"
  done
  sign --options runtime "$SPARKLE"
fi
[ -d "$FRAMEWORKS/ChordUI.framework" ] && sign "$FRAMEWORKS/ChordUI.framework"

sign --options restrict,library,runtime,kill --entitlements "$ENTITLEMENTS/app-entitlements.plist" "$APP"
codesign --verify --deep --strict "$APP"
echo "Signé : $([ "$ID" = "-" ] && echo "ad hoc" || echo "$ID")"
