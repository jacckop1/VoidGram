#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
work="${WORK_DIR:-$HOME/.cache/voidgram-desktop-macos}"
phase="${1:-all}"
build_type="${BUILD_TYPE:-Release}"
jobs="${JOBS:-3}"
version="$(cat "$here/VERSION")"

case "$phase" in
  prepare|libraries|build|package|all) ;;
  *) echo "Usage: $0 [prepare|libraries|build|package|all]" >&2; exit 1 ;;
esac
if [ "$(uname -s)" != Darwin ]; then
  echo "This build needs macOS and full Xcode." >&2
  exit 1
fi
case "$build_type" in Debug|Release) ;; *) echo "BUILD_TYPE must be Debug or Release." >&2; exit 1 ;; esac
if [ "$phase" = build ] || [ "$phase" = all ]; then
  : "${TDESKTOP_API_ID:?set TDESKTOP_API_ID (my.telegram.org)}"
  : "${TDESKTOP_API_HASH:?set TDESKTOP_API_HASH (my.telegram.org)}"
fi
mkdir -p "$work"
work="$(cd "$work" && pwd)"
src="$work/src"

prepare() {
  local source_key
  source_key="$(cat "$here/VERSION" "$here"/patches/*.patch | shasum -a 256 | awk '{print $1}')"
  if [ -e "$src" ]; then
    if [ ! -f "$src/.git/voidgram-source-key" ] || [ "$(cat "$src/.git/voidgram-source-key")" != "$source_key" ]; then
      echo "Source at $src belongs to a different patch set. Choose a new WORK_DIR or move that source aside." >&2
      exit 1
    fi
    git -C "$src" diff --quiet || { echo "Source has local edits: $src" >&2; exit 1; }
    return
  fi
  git clone --depth 1 --branch "$version" https://github.com/AyuGram/AyuGramDesktop.git "$src"
  git -C "$src" submodule update --init --depth 1
  for patch in "$here"/patches/*.patch; do
    git -C "$src" apply --index "$patch"
  done
  git -C "$src" diff --cached --check
  printf '%s\n' "$source_key" > "$src/.git/voidgram-source-key"
}

libraries() {
  test -f "$src/.git/voidgram-source-key"
  bash "$src/Telegram/build/prepare/mac.sh" silent
}

build() {
  test -f "$src/.git/voidgram-source-key"
  (
    cd "$src/Telegram"
    env -u QT bash configure.sh \
      -DTDESKTOP_API_ID="$TDESKTOP_API_ID" \
      -DTDESKTOP_API_HASH="$TDESKTOP_API_HASH" \
      -DCMAKE_CONFIGURATION_TYPES="$build_type" \
      -DDESKTOP_APP_DISABLE_AUTOUPDATE=ON \
      -DDESKTOP_APP_DISABLE_CRASH_REPORTS=ON \
      -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  )
  cmake --build "$src/out" --config "$build_type" --target Telegram --parallel "$jobs" -- CODE_SIGNING_ALLOWED=NO
}

package() {
  APP_PATH="$src/out/$build_type/VoidGram.app" \
    DIST_DIR="${DIST_DIR:-$work/dist}" bash "$here/ci/package-macos.sh"
}

if [ "$phase" = all ]; then
  prepare
  libraries
  build
  package
else
  prepare
  if [ "$phase" != prepare ]; then
    "$phase"
  fi
fi
