#!/usr/bin/env bash
# Compiles Chord's app icon (AppIcon.icon, made like Icon Composer's) into what the
# app bundle takes: Assets.car (macOS 26 and later, Liquid Glass) and app.icns.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$(mktemp -d)"
xcrun actool --compile "$OUT" --platform macosx --minimum-deployment-target 13.0 \
  --app-icon AppIcon --output-partial-info-plist "$OUT/partial.plist" "$HERE/AppIcon.icon" >/dev/null
DEST="$HERE/../src/chrome/app/theme/chromium/mac"
cp "$OUT/Assets.car" "$DEST/Assets.car"
cp "$OUT/AppIcon.icns" "$DEST/app.icns"
rm -rf "$OUT"
echo "Icône mise à jour dans $DEST"
