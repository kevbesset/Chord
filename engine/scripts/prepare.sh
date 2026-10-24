#!/usr/bin/env bash
# Fetches the Chromium sources pinned by ungoogled-chromium-macos, applies its patches
# and fetches its toolchains: the first half of its build.sh, without the official
# build (LTO, PGO) that takes most of a day. Run engine/scripts/bootstrap.sh first.
#
#   engine/scripts/prepare.sh
#
# Done once: the sources stay in engine/vendor/ungoogled-chromium-macos/build/src.
set -euxo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ROOT="$ENGINE_DIR/vendor/ungoogled-chromium-macos"
MAIN="$ROOT/ungoogled-chromium"
SRC="$ROOT/build/src"
DONE="$SRC/.chord-prepared"
ARCH="${1:-arm64}"

# depot_tools wants Python 3.13 or older; Homebrew's comes first if installed.
export PATH="/opt/homebrew/opt/python@3.13/libexec/bin:$PATH"
# Chromium's bundled linker cannot read the macOS 27 SDK (Xcode 27): use 26.5, the SDK
# Chromium 155 is built with, from the Command Line Tools.
export SDKROOT="${SDKROOT:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk}"

if [ -f "$DONE" ]; then
  echo "Sources déjà prêtes : $SRC"
  exit 0
fi

# Each step leaves a marker, so that a failed run resumes where it stopped.
step() { [ -f "$SRC/.chord-step-$1" ]; }
done_step() { touch "$SRC/.chord-step-$1"; }

mkdir -p "$ROOT/build/download_cache"
if ! step sources; then
  # The source archive: much lighter than a git checkout of Chromium.
  "$ROOT/retrieve_and_unpack_resource.py" -d -g "$ARCH"
  python3 "$MAIN/utils/prune_binaries.py" "$SRC" "$MAIN/pruning.list"
  python3 "$MAIN/utils/patches.py" apply "$SRC" "$MAIN/patches" "$ROOT/patches"
  python3 "$MAIN/utils/domain_substitution.py" apply -r "$MAIN/domain_regex.list" -f "$MAIN/domain_substitution.list" "$SRC"
  done_step sources
fi

if ! step toolchains; then
  mkdir -p "$SRC/third_party/llvm-build/Release+Asserts" "$SRC/third_party/rust-toolchain/bin"
  "$ROOT/retrieve_and_unpack_resource.py" -p "$ARCH"
  done_step toolchains
fi

cd "$SRC"
esbuild_version="$(/opt/homebrew/bin/esbuild --version)"
esbuild_module="$ROOT/build/esbuild-node/node_modules/esbuild"
if [[ ! -f "$esbuild_module/package.json" ]] || \
   [[ "$(node -p 'require(process.argv[1]).version' "$esbuild_module/package.json")" != "$esbuild_version" ]]; then
  npm install --prefix "$ROOT/build/esbuild-node" --no-save --package-lock=false --no-bin-links \
    --ignore-scripts --omit=optional --no-audit --no-fund "esbuild@$esbuild_version"
fi
rm -rf third_party/devtools-frontend/src/node_modules/esbuild
ln -s "$esbuild_module" third_party/devtools-frontend/src/node_modules/esbuild

mkdir -p out
[ -x out/gn ] || ./tools/gn/bootstrap/bootstrap.py -o out/gn --skip-generate-buildfiles
./tools/rust/build_bindgen.py --skip-test

touch "$DONE"
echo "Sources prêtes : $SRC"
