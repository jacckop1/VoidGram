#!/usr/bin/env bash
# Installs VoidGram Desktop for the current user: the program, its icons and an entry in the
# application menu with the window name "VoidGram". Run it from the unpacked release:
#   tar --zstd -xf voidgram-desktop-linux-x86_64.tar.zst -C voidgram && cd voidgram && ./install.sh
# `./install.sh --uninstall` takes everything back out. Works on Arch and Arch-based systems
# (Manjaro, EndeavourOS, CachyOS, Garuda, ...) and on any other Linux with the same libraries.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
app_id="com.voidgram.desktop"
apps="$prefix/share/applications"

refresh() {
  command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$prefix/share/icons/hicolor" 2>/dev/null || true
  command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
}

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$prefix/bin/VoidGram" "$apps/$app_id.desktop" "$prefix/share/dbus-1/services/$app_id.service" \
    "$prefix/share/metainfo/$app_id.metainfo.xml"
  find "$prefix/share/icons" -name "$app_id.*" -delete 2>/dev/null || true
  refresh
  echo "VoidGram removed. Your chats and settings stay in ~/.local/share/AyuGramDesktop."
  exit 0
fi

if [ ! -x "$here/bin/VoidGram" ]; then
  echo "bin/VoidGram is not next to this script: unpack the release first." >&2
  exit 1
fi

mkdir -p "$prefix"
cp -a "$here/bin" "$here/share" "$prefix/"

# The menu entry points at the installed program by its full path, so it starts from any launcher
# whether or not ~/.local/bin is on PATH. StartupWMClass is the window's app id: the shell groups the
# window under this entry and shows its name and icon.
desktop="$apps/$app_id.desktop"
sed -i \
  -e "s|^TryExec=.*|TryExec=$prefix/bin/VoidGram|" \
  -e "s|^Exec=env DESKTOPINTEGRATION=1 VoidGram|Exec=env DESKTOPINTEGRATION=1 $prefix/bin/VoidGram|" \
  -e "s|^Exec=VoidGram -quit|Exec=$prefix/bin/VoidGram -quit|" \
  "$desktop"
if [ -f "$prefix/share/dbus-1/services/$app_id.service" ]; then
  sed -i "s|^Exec=.*|Exec=$prefix/bin/VoidGram|" "$prefix/share/dbus-1/services/$app_id.service"
fi
refresh

echo "VoidGram is installed: look for it in the application menu, or run $prefix/bin/VoidGram"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "(add $prefix/bin to PATH to start it as just 'VoidGram')";; esac
if [ -f "$here/CHANGELOG.md" ]; then
  echo
  cat "$here/CHANGELOG.md"
fi
