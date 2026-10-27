#!/usr/bin/env bash
# Runs one of Sparkle's tools (generate_keys, sign_update…), from the Sparkle package
# Xcode resolved for ChordUI (app/project.yml).
#
#   engine/scripts/sparkle-tool.sh generate_keys     # once: Chord's update key pair
#   engine/scripts/sparkle-tool.sh generate_keys -p  # its public key (SUPublicEDKey)
set -euo pipefail

TOOL="${1:?Outil de Sparkle (generate_keys, sign_update…)}"
shift
found="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/artifacts/sparkle/Sparkle/bin/$TOOL" -type f 2>/dev/null | head -1)"
if [ -z "$found" ]; then
  REPO_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
  (cd "$REPO_DIR/app" && xcodegen generate >/dev/null && \
    xcodebuild -resolvePackageDependencies -project Chord.xcodeproj >/dev/null)
  found="$(find "$HOME/Library/Developer/Xcode/DerivedData" -path "*/artifacts/sparkle/Sparkle/bin/$TOOL" -type f 2>/dev/null | head -1)"
fi
[ -n "$found" ] || { echo "Sparkle tool not found: $TOOL" >&2; exit 1; }
exec "$found" "$@"
