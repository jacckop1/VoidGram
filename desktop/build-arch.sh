#!/usr/bin/env bash
# Builds VoidGram Desktop (a patched AyuGram Desktop) on Arch Linux.
#
#   TDESKTOP_API_ID=... TDESKTOP_API_HASH=... desktop/build-arch.sh
#
# Your own api id and hash come from https://my.telegram.org. JOBS (default 4) limits the compile
# jobs: Telegram Desktop needs about 2 GB of memory for each.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="${WORK_DIR:-$HOME/.cache/voidgram-desktop}"
version="$(cat "$here/VERSION")"
jobs="${JOBS:-4}"
build_type="${BUILD_TYPE:-Release}"
: "${TDESKTOP_API_ID:?set TDESKTOP_API_ID (my.telegram.org)}"
: "${TDESKTOP_API_HASH:?set TDESKTOP_API_HASH (my.telegram.org)}"

# TDLib's end-to-end part, at the commit AyuGram's own Arch package uses.
tdlib_commit=bc9c263e2bfee06aaab41e82db51a103376030bc

mkdir -p "$work"
if [ ! -d "$work/src/.git" ]; then
  git clone --depth 1 --branch "$version" --recurse-submodules --shallow-submodules -j8 \
    https://github.com/AyuGram/AyuGramDesktop.git "$work/src"
fi
cd "$work/src"
# A clean tree every time, so a second run does not apply the patches on top of the first run's.
git checkout -q -f -B voidgram "$version"
git reset -q --hard "$version"
git clean -qfd -e build
for patch in "$here"/patches/*.patch; do
  git apply --index "$patch"
done
git diff --cached --check

td="$work/td-$tdlib_commit"
if [ ! -d "$td/install" ]; then
  mkdir -p "$td"
  curl -fsSL "https://github.com/tdlib/td/archive/$tdlib_commit.tar.gz" | tar -xz -C "$td" --strip-components=1
  cmake -B "$td/build" -S "$td" -DCMAKE_BUILD_TYPE="$build_type" -DCMAKE_INSTALL_PREFIX="$td/install" -Wno-dev -DTD_E2E_ONLY=ON
  cmake --build "$td/build" -j "$jobs"
  cmake --install "$td/build"
fi

launcher=()
if command -v ccache >/dev/null; then
  launcher=(-DCMAKE_C_COMPILER_LAUNCHER=ccache -DCMAKE_CXX_COMPILER_LAUNCHER=ccache)
fi
cmake -B "$work/build" -S "$work/src" -G Ninja \
  "${launcher[@]}" \
  -DCMAKE_BUILD_TYPE="$build_type" \
  -DCMAKE_INSTALL_PREFIX="$work/install" \
  -DTDESKTOP_API_ID="$TDESKTOP_API_ID" \
  -DTDESKTOP_API_HASH="$TDESKTOP_API_HASH" \
  -DDESKTOP_APP_DISABLE_AUTOUPDATE=True \
  -Dtde2e_DIR="$td/install/lib/cmake/tde2e"
cmake --build "$work/build" -j "$jobs"
cmake --install "$work/build"
echo "Built: $work/build/bin/Telegram, installed under $work/install"
