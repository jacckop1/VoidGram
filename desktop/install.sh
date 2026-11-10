#!/usr/bin/env bash
# Installs VoidGram Desktop for the current user: the program, its icons and an entry in the
# application menu with the window name "VoidGram". One command, no download by hand:
#   curl -fsSL https://raw.githubusercontent.com/neosay-dev/VoidGram/main/desktop/install.sh | bash
# It also runs from an unpacked release (./install.sh), then it installs that very build.
# `./install.sh --uninstall` takes everything back out. Works on Arch and Arch-based systems
# (Manjaro, EndeavourOS, CachyOS, Garuda, ...) and on any other Linux with the same libraries.
set -euo pipefail

repo="neosay-dev/VoidGram"
here="$PWD"
[ -n "${BASH_SOURCE[0]:-}" ] && here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
app_id="com.voidgram.desktop"
apps="$prefix/share/applications"

refresh() {
  command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$prefix/share/icons/hicolor" 2>/dev/null || true
  command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
}

if [ "${1:-}" = "--uninstall" ]; then
  for dir in $(printf '%s' "${XDG_DATA_DIRS:-}" | tr ':' ' '); do
    case "$dir" in "$HOME"/*) rm -f "$dir/applications/$app_id.desktop"; find "$dir/icons" -name "$app_id.*" -delete 2>/dev/null || true;; esac
  done
  rm -f "$prefix/bin/VoidGram" "$apps/$app_id.desktop" "$prefix/share/dbus-1/services/$app_id.service" \
    "$prefix/share/metainfo/$app_id.metainfo.xml"
  find "$prefix/share/icons" -name "$app_id.*" -delete 2>/dev/null || true
  refresh
  echo "VoidGram removed. Your chats and settings stay in ~/.local/share/AyuGramDesktop."
  exit 0
fi

notes=""
if [ ! -x "$here/bin/VoidGram" ]; then
  # Started on its own (curl ... | bash): fetch the newest desktop release and unpack it.
  for tool in curl tar zstd python3; do
    command -v "$tool" >/dev/null || { echo "$tool is needed: sudo pacman -S $tool" >&2; exit 1; }
  done
  json="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=50")"
  tag="$(printf '%s' "$json" | python3 -c 'import json,sys
for r in json.load(sys.stdin):
    if r["tag_name"].startswith("desktop-v") and not r["draft"]:
        print(r["tag_name"]); break')"
  [ -n "$tag" ] || { echo "No VoidGram Desktop release found yet." >&2; exit 1; }
  notes="$(printf '%s' "$json" | TAG="$tag" python3 -c 'import json,os,sys
for r in json.load(sys.stdin):
    if r["tag_name"] == os.environ["TAG"]:
        print(r.get("body") or "")')"
  here="$(mktemp -d)"
  trap 'rm -rf "$here"' EXIT
  echo "Downloading VoidGram ${tag#desktop-} (about 100 MB)..."
  curl -fSL --progress-bar "https://github.com/$repo/releases/download/$tag/voidgram-desktop-linux-x86_64.tar.zst" \
    | tar --zstd -xf - -C "$here"
fi

mkdir -p "$prefix"
cp -a "$here/share" "$prefix/"
# Replaced by a rename, so it also works while VoidGram is running.
mkdir -p "$prefix/bin"
cp -a "$here/bin/VoidGram" "$prefix/bin/VoidGram.new"
mv -f "$prefix/bin/VoidGram.new" "$prefix/bin/VoidGram"

# The menu entry points at the installed program by its full path, so it starts from any launcher
# whether or not ~/.local/bin is on PATH. StartupWMClass is the window's app id: the shell groups the
# window under this entry and shows its name and icon.
desktop="$apps/$app_id.desktop"
sed -i \
  -e "s|^TryExec=.*|TryExec=$prefix/bin/VoidGram|" \
  -e "s|^Exec=env DESKTOPINTEGRATION=1 VoidGram|Exec=env DESKTOPINTEGRATION=1 $prefix/bin/VoidGram|" \
  -e "s|^Exec=VoidGram -quit|Exec=$prefix/bin/VoidGram -quit|" \
  -e "/^DBusActivatable=/d" \
  "$desktop"
# Launchers that read only XDG_DATA_DIRS (Hyprland setups: hyprlauncher, walker, fuzzel, ...) do not
# look in ~/.local/share, so the entry is linked into every user-owned folder that list names.
IFS=: read -ra dirs <<< "${XDG_DATA_DIRS:-}"
for dir in "${dirs[@]}"; do
  case "$dir" in "$HOME"/*)
    mkdir -p "$dir/applications" "$dir/icons/hicolor" 2>/dev/null || continue
    ln -sf "$desktop" "$dir/applications/$app_id.desktop"
    cp -a "$prefix/share/icons/hicolor/." "$dir/icons/hicolor/" 2>/dev/null || true;;
  esac
done
if [ -f "$prefix/share/dbus-1/services/$app_id.service" ]; then
  sed -i "s|^Exec=.*|Exec=$prefix/bin/VoidGram|" "$prefix/share/dbus-1/services/$app_id.service"
fi
refresh

echo "VoidGram is installed: look for it in the application menu, or run $prefix/bin/VoidGram"
case ":$PATH:" in *":$prefix/bin:"*) ;; *) echo "(add $prefix/bin to PATH to start it as just 'VoidGram')";; esac
if [ -n "$notes" ]; then
  echo
  printf '%s\n' "$notes"
fi
