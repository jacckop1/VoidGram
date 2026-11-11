#!/usr/bin/env bash
# Packs the generic Linux build into dist/: a tarball for desktop/install.sh, a .deb (Debian, Ubuntu
# and relatives) and an .rpm (Fedora, openSUSE, RHEL and relatives). Run from the repository root
# after ./src/out/Release/VoidGram is built.
set -euo pipefail

src="$PWD/src"
bin="$src/out/Release/VoidGram"
test -x "$bin" || { echo "no $bin" >&2; exit 1; }
version="$(cat desktop/VERSION)"
version="${version#v}"
release="voidgram${GITHUB_RUN_NUMBER:-1}"
app_id="com.voidgram.desktop"
rm -rf dist root
mkdir -p dist root/usr/bin root/usr/share/applications root/usr/share/metainfo

strip --strip-unneeded -o root/usr/bin/VoidGram "$bin"
cp "$src/lib/xdg/$app_id.desktop" root/usr/share/applications/
sed -i '/^DBusActivatable=/d' root/usr/share/applications/$app_id.desktop
cp "$src/lib/xdg/$app_id.metainfo.xml" root/usr/share/metainfo/ 2>/dev/null || true
for size in 16 32 48 64 128 256 512; do
  mkdir -p root/usr/share/icons/hicolor/${size}x${size}/apps
  cp "$src/Telegram/Resources/art/icon${size}.png" root/usr/share/icons/hicolor/${size}x${size}/apps/$app_id.png
done

# The tarball has the layout desktop/install.sh installs from: bin/ and share/ at the top.
mkdir -p tarball/bin tarball/share
cp root/usr/bin/VoidGram tarball/bin/
cp -a root/usr/share/. tarball/share/
cp desktop/install.sh tarball/install.sh
chmod +x tarball/install.sh
tar --zstd -cf dist/voidgram-desktop-linux-generic-x86_64.tar.zst -C tarball .

description="VoidGram Desktop, a Telegram client with ghost mode, saved history and sponsor looks."
common=(-s dir -C root --name voidgram --version "$version" --iteration "$release" --architecture x86_64
  --maintainer "VoidGram <https://github.com/neosay-dev/VoidGram>" --url "https://github.com/neosay-dev/VoidGram"
  --license GPL-3.0 --description "$description" usr)
# What the binary loads at run time besides glibc (readelf -d: NEEDED); the rest is built into it.
deb_deps=(-d libpango-1.0-0 -d libpangocairo-1.0-0 -d libpangoft2-1.0-0 -d libcairo2
  -d "libglib2.0-0t64 | libglib2.0-0" -d "libgtk-3-0t64 | libgtk-3-0" -d libfontconfig1 -d libfreetype6 -d libgl1 -d libegl1 -d libxkbcommon-x11-0)
rpm_deps=(-d pango -d cairo -d glib2 -d gtk3 -d fontconfig -d freetype -d mesa-libGL -d mesa-libEGL -d libxkbcommon-x11)
fpm -t deb -p dist/voidgram-desktop-x86_64.deb "${deb_deps[@]}" "${common[@]}"
fpm -t rpm -p dist/voidgram-desktop-x86_64.rpm "${rpm_deps[@]}" "${common[@]}"
ls -la dist
