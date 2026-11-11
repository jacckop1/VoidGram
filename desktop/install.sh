#!/usr/bin/env bash
# Installs VoidGram Desktop on any Linux with one command; it finds out the distribution itself:
#   curl -fsSL https://raw.githubusercontent.com/neosay-dev/VoidGram/main/desktop/install.sh | bash
#
#   Arch, Manjaro, EndeavourOS, CachyOS, Garuda, Artix  -> the build made on Arch, into ~/.local
#   Debian, Ubuntu, Mint, Pop!_OS, Zorin, elementary... -> the .deb, through apt (needs sudo)
#   Fedora, Nobara, RHEL, Rocky, AlmaLinux, CentOS      -> the .rpm, through dnf (needs sudo)
#   openSUSE, SLES                                      -> the .rpm, through zypper (needs sudo)
#   anything else (Void, Gentoo, Solus, ...)            -> the generic build, into ~/.local
#
# The same command updates an installed copy. Options:
#   --uninstall   removes VoidGram (package or ~/.local copy); chats and settings stay
#   --local       skips the package manager: the build for this distribution into ~/.local
#   --distro ID   installs as for another distribution (arch, debian, fedora, suse, generic)
# Run from an unpacked release archive (./install.sh), it installs that very build into ~/.local.
set -euo pipefail

repo="neosay-dev/VoidGram"
here="$PWD"
[ -n "${BASH_SOURCE[0]:-}" ] && here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
prefix="${PREFIX:-$HOME/.local}"
app_id="com.voidgram.desktop"
apps="$prefix/share/applications"

uninstall=0
local_only=0
family=""
while [ $# -gt 0 ]; do
  case "$1" in
    --uninstall) uninstall=1;;
    --local) local_only=1;;
    --distro) shift; family="${1:-}";;
    -h|--help) sed -n '2,17p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "Unknown option: $1" >&2; exit 1;;
  esac
  shift
done

say() { printf '\033[1m%s\033[0m\n' "$*"; }
fail() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null || fail "$1 is needed. $2"; }
as_root() { if [ "$(id -u)" -eq 0 ]; then "$@"; else need sudo "Install sudo or run as root."; sudo "$@"; fi; }

# The distribution family, from /etc/os-release (ID first, then ID_LIKE).
detect_family() {
  local ids=""
  if [ -r /etc/os-release ]; then
    ids="$(. /etc/os-release; printf '%s %s' "${ID:-}" "${ID_LIKE:-}" | tr '[:upper:]' '[:lower:]')"
  fi
  [ -f /etc/arch-release ] && ids="arch $ids"
  for id in $ids; do
    case "$id" in
      arch|archarm|manjaro*|endeavouros|cachyos|garuda|artix|arcolinux|rebornos|parabola) echo arch; return;;
      debian|ubuntu|linuxmint|pop|elementary|zorin|kali|raspbian|neon|deepin|mx|devuan|pureos|tuxedo) echo debian; return;;
      fedora|nobara|ultramarine|rhel|centos|rocky|almalinux|ol|amzn) echo fedora; return;;
      opensuse*|suse|sles|sled) echo suse; return;;
    esac
  done
  echo generic
}
[ -n "$family" ] || family="$(detect_family)"
case "$family" in arch|debian|fedora|suse|generic) ;; *) fail "Unknown --distro $family (arch, debian, fedora, suse, generic).";; esac
[ "$(uname -m)" = "x86_64" ] || fail "VoidGram Desktop is built for x86_64 only; this machine is $(uname -m)."
if ldd --version 2>&1 | grep -qi musl; then fail "This system uses musl (Alpine and the like); VoidGram needs glibc."; fi

refresh() {
  command -v update-desktop-database >/dev/null && update-desktop-database "$apps" 2>/dev/null || true
  command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t -f "$prefix/share/icons/hicolor" 2>/dev/null || true
  command -v kbuildsycoca6 >/dev/null && kbuildsycoca6 >/dev/null 2>&1 || true
}

remove_local() {
  for dir in $(printf '%s' "${XDG_DATA_DIRS:-}" | tr ':' ' '); do
    case "$dir" in "$HOME"/*) rm -f "$dir/applications/$app_id.desktop"; find "$dir/icons" -name "$app_id.*" -delete 2>/dev/null || true;; esac
  done
  rm -f "$prefix/bin/VoidGram" "$apps/$app_id.desktop" "$prefix/share/dbus-1/services/$app_id.service" \
    "$prefix/share/metainfo/$app_id.metainfo.xml"
  find "$prefix/share/icons" -name "$app_id.*" -delete 2>/dev/null || true
  refresh
}

if [ "$uninstall" = 1 ]; then
  if command -v dpkg-query >/dev/null && dpkg-query -W -f='${Status}' voidgram 2>/dev/null | grep -q "ok installed"; then
    say "Removing the voidgram package (apt)..."
    as_root apt-get remove -y voidgram
  elif command -v rpm >/dev/null && rpm -q voidgram >/dev/null 2>&1; then
    say "Removing the voidgram package..."
    if command -v dnf >/dev/null; then as_root dnf remove -y voidgram
    elif command -v zypper >/dev/null; then as_root zypper --non-interactive remove voidgram
    else as_root rpm -e voidgram; fi
  fi
  remove_local
  echo "VoidGram removed. Your chats and settings stay in ~/.local/share/AyuGramDesktop."
  exit 0
fi

# --- Downloading ---------------------------------------------------------------------------------

tmp=""
cleanup() { [ -n "$tmp" ] && rm -rf "$tmp"; }
trap cleanup EXIT

release_tag=""
# Finds the newest release that carries `asset` and sets release_tag.
find_release() {
  local asset="$1" json
  need curl "Install curl with your package manager."
  need python3 "Install python3 with your package manager."
  json="$(curl -fsSL "https://api.github.com/repos/$repo/releases?per_page=50")" || fail "GitHub is unreachable."
  local found
  found="$(printf '%s' "$json" | ASSET="$asset" python3 -c 'import json,os,sys
for r in json.load(sys.stdin):
    if r["draft"]:
        continue
    if any(a["name"] == os.environ["ASSET"] for a in r.get("assets", [])):
        print(r["tag_name"])
        break')"
  [ -n "$found" ] || fail "No release with $asset yet."
  release_tag="$found"
}

download() {
  local asset="$1" target="$2"
  say "Downloading VoidGram ($release_tag, $asset)..."
  curl -fSL --progress-bar "https://github.com/$repo/releases/download/$release_tag/$asset" -o "$target"
}

# --- Installing a package ------------------------------------------------------------------------

install_package() {
  local asset file
  case "$family" in
    debian) asset="voidgram-desktop-x86_64.deb";;
    *) asset="voidgram-desktop-x86_64.rpm";;
  esac
  find_release "$asset"
  tmp="$(mktemp -d)"
  chmod 755 "$tmp"
  file="$tmp/$asset"
  download "$asset" "$file"
  chmod 644 "$file"
  case "$family" in
    debian)
      need apt-get "This looks like Debian or Ubuntu, but apt-get is missing."
      say "Installing with apt (sudo password may be asked)..."
      as_root apt-get install -y "$file";;
    fedora)
      if command -v dnf >/dev/null; then
        say "Installing with dnf (sudo password may be asked)..."
        as_root dnf install -y "$file"
      else
        need yum "Neither dnf nor yum is installed."
        as_root yum install -y "$file"
      fi;;
    suse)
      need zypper "This looks like openSUSE, but zypper is missing."
      say "Installing with zypper (sudo password may be asked)..."
      as_root zypper --non-interactive install --allow-unsigned-rpm "$file";;
  esac
  # A copy from an earlier ~/.local install would shadow the package in the menu.
  [ -x "$prefix/bin/VoidGram" ] && remove_local
  echo "VoidGram is installed: look for it in the application menu, or run VoidGram"
}

# --- Installing into ~/.local --------------------------------------------------------------------

install_local() {
  local src="$here"
  if [ ! -x "$src/bin/VoidGram" ]; then
    local asset="voidgram-desktop-linux-generic-x86_64.tar.zst"
    [ "$family" = "arch" ] && asset="voidgram-desktop-linux-x86_64.tar.zst"
    need tar "Install tar with your package manager."
    need zstd "Install zstd with your package manager (for example: sudo pacman -S zstd)."
    find_release "$asset"
    tmp="$(mktemp -d)"
    download "$asset" "$tmp/voidgram.tar.zst"
    mkdir -p "$tmp/unpacked"
    tar --zstd -xf "$tmp/voidgram.tar.zst" -C "$tmp/unpacked"
    src="$tmp/unpacked"
  fi
  [ -x "$src/bin/VoidGram" ] || fail "The archive has no bin/VoidGram."

  mkdir -p "$prefix"
  cp -a "$src/share" "$prefix/"
  # Replaced by a rename, so it also works while VoidGram is running.
  mkdir -p "$prefix/bin"
  cp -a "$src/bin/VoidGram" "$prefix/bin/VoidGram.new"
  mv -f "$prefix/bin/VoidGram.new" "$prefix/bin/VoidGram"

  # The menu entry points at the installed program by its full path, so it starts from any launcher
  # whether or not ~/.local/bin is on PATH. StartupWMClass is the window's app id: the shell groups
  # the window under this entry and shows its name and icon.
  local desktop="$apps/$app_id.desktop"
  sed -i \
    -e "s|^TryExec=.*|TryExec=$prefix/bin/VoidGram|" \
    -e "s|^Exec=env DESKTOPINTEGRATION=1 VoidGram|Exec=env DESKTOPINTEGRATION=1 $prefix/bin/VoidGram|" \
    -e "s|^Exec=VoidGram -quit|Exec=$prefix/bin/VoidGram -quit|" \
    -e "/^DBusActivatable=/d" \
    "$desktop"
  # Launchers that read only XDG_DATA_DIRS (Hyprland setups: hyprlauncher, walker, fuzzel, ...) do
  # not look in ~/.local/share, so the entry is linked into every user-owned folder that list names.
  local dirs dir
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
  if [ "$family" = "arch" ]; then
    echo "Built on current Arch: if it fails with a missing library (libssl.so...), run: sudo pacman -Syu"
  fi
}

case "$family" in arch) label="Arch family";; debian) label="Debian / Ubuntu family";; fedora) label="Fedora / RHEL family";; suse) label="openSUSE";; *) label="other Linux (generic build)";; esac
say "Distribution: $label"

if [ -x "$here/bin/VoidGram" ] || [ "$local_only" = 1 ] || [ "$family" = "arch" ] || [ "$family" = "generic" ]; then
  install_local
else
  install_package
fi

if [ -n "$release_tag" ]; then
  echo "What's new: https://github.com/$repo/releases/tag/$release_tag"
fi
