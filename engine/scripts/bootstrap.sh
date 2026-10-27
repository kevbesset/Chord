#!/usr/bin/env bash
# Checks the build prerequisites, then fetches ungoogled-chromium-macos at the
# version pinned in engine/UPSTREAM. Does not build: that takes hours, run it yourself.
#
#   engine/scripts/bootstrap.sh
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TAG="$(tr -d '[:space:]' < "$ENGINE_DIR/UPSTREAM")"
VENDOR="$ENGINE_DIR/vendor/ungoogled-chromium-macos"
REPO="https://github.com/ungoogled-software/ungoogled-chromium-macos.git"
MIN_FREE_GB=120

missing=0
ok()   { printf '  ✓ %s\n' "$1"; }
fail() { printf '  ✗ %s — %s\n' "$1" "$2"; missing=1; }
need() { if command -v "$1" >/dev/null 2>&1; then ok "$1"; else fail "$1" "$2"; fi; }

echo "Chord engine — ungoogled-chromium-macos $TAG"
echo
echo "Prerequisites:"
[ "$(uname -s)" = "Darwin" ] && ok "macOS" || fail "macOS" "Chromium for Mac builds on a Mac"
[ "$(uname -m)" = "arm64" ] && ok "Apple Silicon" || echo "  · Intel processor: the build will take longer"
need xcodebuild "install Xcode, then open it once"
need brew       "install Homebrew: https://brew.sh"
need ninja      "brew install ninja"
need node       "brew install node"
need gsha256sum "brew install coreutils"
need go         "brew install go"
need esbuild    "brew install esbuild"
need tsc        "brew install typescript"
need perl       "comes with macOS"

if command -v python3 >/dev/null 2>&1; then
  if python3 -c 'import sys; sys.exit(0 if sys.version_info < (3, 14) else 1)'; then
    ok "python3 $(python3 -c 'import platform; print(platform.python_version())')"
  else
    fail "python3" "depot_tools needs Python 3.13 or older: brew install python@3.13"
  fi
  if python3 -c 'import socks, httplib2' >/dev/null 2>&1; then
    ok "PySocks, httplib2"
  else
    fail "PySocks, httplib2" "pip3 install PySocks httplib2 (add --break-system-packages if needed)"
  fi
else
  fail "python3" "brew install python@3.13"
fi

free_gb=$(df -g "$ENGINE_DIR" | awk 'NR==2 {print $4}')
if [ "${free_gb:-0}" -ge "$MIN_FREE_GB" ]; then
  ok "disk space: ${free_gb} GB free"
else
  fail "disk space" "${free_gb:-?} GB free, allow at least ${MIN_FREE_GB} GB"
fi

echo
if [ "$missing" -ne 0 ]; then
  echo "Some prerequisites are missing (see above). Also remember:"
  echo "  xcodebuild -downloadComponent MetalToolchain"
  echo "  brew install readline && brew unlink binutils"
  exit 1
fi

if [ ! -d "$VENDOR/.git" ]; then
  echo "Cloning ungoogled-chromium-macos…"
  mkdir -p "$(dirname "$VENDOR")"
  git clone --recurse-submodules "$REPO" "$VENDOR"
fi

echo "Version $TAG…"
git -C "$VENDOR" fetch --tags --quiet
git -C "$VENDOR" checkout --quiet --recurse-submodules "$TAG"

cat <<EOF

Ready. Next step, the reference build (several hours):

  cd "$VENDOR"
  ./build.sh

The .dmg lands in build/. If downloading the sources fails, delete
build/downloads_cache; if the build fails later, delete build/src.
EOF
