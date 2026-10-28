#!/usr/bin/env bash
# Signs Chord.app from the inside out, as ungoogled-chromium's sign_and_package_app.sh
# does: helpers, libraries, frameworks, then the app with its entitlements and the
# hardened runtime.
#
#   engine/scripts/sign.sh <Chord.app>           # every part (after a Chromium build)
#   engine/scripts/sign.sh <Chord.app> --quick   # ChordUI, Sparkle and the app (run.sh)
#
# The identity: $CHORD_SIGN_IDENTITY, else an "Apple Development" certificate, else a
# "Developer ID Application" one, else ad hoc. Builds made here keep one identity, so
# --quick never mixes two teams in one app; package.sh passes the Developer ID (needed
# to notarize). A certificate keeps Chord's signature the same from build to build: the
# keychain lets Chord in without asking again, and Chord uses the real keychain. Ad
# hoc, Chord keeps its key in Chromium's mock keychain.
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
  for kind in "Apple Development" "Developer ID Application"; do
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

# Without ungoogled-chromium's checkout (a release copy, run.sh without a Chromium
# build), the app is signed ad hoc without hardened runtime, which needs no entitlements.
APP_ENTITLEMENTS=()
[ -f "$ENTITLEMENTS/app-entitlements.plist" ] && APP_ENTITLEMENTS=(--entitlements "$ENTITLEMENTS/app-entitlements.plist")

# Passkeys kept on this Mac (Touch ID) need the keychain group
# FK3PG5SKWL.app.chord.Chord.webauthn, which macOS grants only with a provisioning
# profile from Apple's developer site: engine/signing/DeveloperID.provisionprofile for
# the Developer ID, engine/signing/Development.provisionprofile for an Apple
# Development certificate (docs/RELEASING.md). Without one, the app keeps its usual
# entitlements: macOS would refuse to open an app claiming the group unprovisioned.
# The profile's own entitlements say what it allows (iCloud Keychain passkeys need
# Apple's approval, com.apple.developer.web-browser.public-key-credential).
PROFILE=""
case "$ID" in
  "Developer ID Application:"*) PROFILE="$ENGINE_DIR/signing/DeveloperID.provisionprofile" ;;
  "Apple Development:"*) PROFILE="$ENGINE_DIR/signing/Development.provisionprofile" ;;
esac
if [ -n "$PROFILE" ] && [ -f "$PROFILE" ] && [ ${#APP_ENTITLEMENTS[@]} -gt 0 ]; then
  WORK="$(mktemp -d)"
  security cms -D -i "$PROFILE" > "$WORK/profile.plist"
  /usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$WORK/profile.plist" > "$WORK/allowed.plist"
  cp "$ENTITLEMENTS/app-entitlements.plist" "$WORK/app.plist"
  allows() { /usr/libexec/PlistBuddy -c "Print :$1" "$WORK/allowed.plist" >/dev/null 2>&1; }
  # PlistBuddy, whose key paths use ":", since the keys have dots.
  claim() {
    /usr/libexec/PlistBuddy -c "Delete :$1" "$WORK/app.plist" >/dev/null 2>&1 || true
    /usr/libexec/PlistBuddy -c "Add :$1 $2 ${3:-}" "$WORK/app.plist"
  }
  team="$(/usr/libexec/PlistBuddy -c "Print :TeamIdentifier:0" "$WORK/profile.plist")"
  # The profile may allow a pattern (TEAM.*, Xcode's development profile): the app
  # names itself and its group.
  allows com.apple.application-identifier && claim com.apple.application-identifier string "$team.app.chord.Chord"
  allows com.apple.developer.team-identifier && claim com.apple.developer.team-identifier string "$team"
  if allows keychain-access-groups; then
    claim keychain-access-groups array
    /usr/libexec/PlistBuddy -c "Add :keychain-access-groups: string $team.app.chord.Chord.webauthn" "$WORK/app.plist"
  fi
  allows com.apple.developer.web-browser.public-key-credential && \
    claim com.apple.developer.web-browser.public-key-credential bool true
  cp "$PROFILE" "$APP/Contents/embedded.provisionprofile"
  APP_ENTITLEMENTS=(--entitlements "$WORK/app.plist")
  echo "Provisioning profile: $(basename "$PROFILE")"
fi
sign --options restrict,library,runtime,kill ${APP_ENTITLEMENTS[@]+"${APP_ENTITLEMENTS[@]}"} "$APP"
codesign --verify --deep --strict "$APP"
echo "Signed: $([ "$ID" = "-" ] && echo "ad hoc" || echo "$ID")"
