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
fpm -t deb -p dist/voidgram-desktop-x86_64.deb "${common[@]}"
fpm -t rpm -p dist/voidgram-desktop-x86_64.rpm "${common[@]}"
ls -la dist
