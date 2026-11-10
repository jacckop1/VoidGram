# VoidGram Desktop

VoidGram for Linux is AyuGram Desktop (`VERSION`) with the patches in `patches/`. It reads the same
badge server as the iPhone app and checks the same Ed25519 signature on the registry.

## What it does

- **Badges** the owner gave, in the profile, next to names and in the chat list (AyuGram's own
  badge mechanism, fed from the signed registry; timed daily badges stop when they run out).
- **Avatar frames** (animated PNG) around the avatar in the profile, at the size the sponsor chose.
- **Name styles** (font, colour, glow) in the profile, in message authors' names and in the chat list.
- **Profile details the owner gave**: a number shown instead of the real one, extra usernames, a TON
  balance, a line under the name, and a rating that replaces Telegram's.
- **Glowing names** (a faint light in the name's colour) in messages, the chat list and the profile.
- **Glowing reactions**: a light behind each reaction in the colour of the reaction.
- **Unique gifts (NFTs)** the owner gave a profile, listed first among its gifts in the gifts tab
  (only shown where the profile's gifts tab is shown).
- **Bubble skins**: a sponsor's messages get the grey skin with the VoidGram mark; the owner's, a gold frame.
- **Name and logo**: the app is VoidGram everywhere you see it (window, tray, settings, icon).
- **Settings ▸ VoidGram ▸ "VoidGram: frame and name"** (sponsors and the owner): choose a frame,
  its size and the name style, with a preview made of the avatar. The choice goes to the badge server,
  signed in with Mini App data Telegram gives for `@AyuZayavka_bot`.

Not ported: the player, lyrics and the other phone-only features.

The data folder is still the one AyuGram Desktop uses (`~/.local/share/AyuGramDesktop`), so this client and
AyuGram Desktop share one login and settings. Run only one of them at a time.

## Build (Arch)

```sh
sudo pacman -S --needed base-devel cmake ninja git python gperf \
  abseil-cpp ada cmark-gfm ffmpeg glib2 glib2-devel gobject-introspection hunspell kcoreaddons \
  libavif libfido2 libheif libjpeg-turbo libjxl libpipewire libsrtp libtg_owt libvpx libxcb \
  libxcomposite libxdamage libxext libxfixes libxkbcommon libxrandr libxtst lz4 microsoft-gsl \
  minizip openal openh264 openssl opus pipewire qt6-base qt6-declarative qt6-imageformats \
  qt6-shadertools qt6-svg qt6-wayland range-v3 rnnoise tl-expected tlottie vulkan-headers xxhash zlib boost
TDESKTOP_API_ID=... TDESKTOP_API_HASH=... desktop/build-arch.sh
```

Your own api id and hash come from <https://my.telegram.org>. `JOBS` (default 4) limits the compile
jobs; each needs about 2 GB of memory. The binary is `~/.cache/voidgram-desktop/build/bin/VoidGram`.

## Changing the patches

The work tree is `~/.cache/voidgram-desktop/src` (a clone of the tag in `VERSION`). Edit it, compile
one file with `ninja -C ~/.cache/voidgram-desktop/build <object>.o`, and export with
`git add -N Telegram/SourceFiles/voidgram && git diff --binary > desktop/patches/0001-voidgram.patch`.
The build script resets the tree to the tag and applies every patch, so a second run is safe.

## Install and release

Unpack a build and run `./install.sh`: it copies the program and icons to `~/.local`, adds
"VoidGram" to the application menu (window class `com.voidgram.desktop`) and prints the list of
changes. `./install.sh --uninstall` removes it again.

A release is made by tagging a tested commit `desktop-vX.Y.Z` and pushing the tag: the workflow
builds, then publishes the archive, `install.sh` and notes made by `desktop/changelog.sh` (one
line per commit that touched `desktop/` since the previous `desktop-v*` tag).

## Windows

`.github/workflows/desktop-windows.yml` ("Run workflow") builds the same patched AyuGram Desktop for
Windows x64 and keeps `VoidGram.exe` in `voidgram-desktop-windows-x64.zip`. A cold run builds Qt,
ffmpeg and WebRTC from source and takes hours; the libraries are cached, so a run that hits the
time limit saves them and the next run goes on from there. Fill `release_tag` to attach the zip to a
release.

## Debian, Ubuntu, Fedora and the rest

`.github/workflows/desktop-linux.yml` ("Run workflow") builds one generic Linux binary in AyuGram's
Docker environment (Rocky Linux 8) and packs it as `voidgram-desktop-linux-generic-x86_64.tar.zst`
(for `install.sh`), `voidgram-desktop-x86_64.deb` and `voidgram-desktop-x86_64.rpm`:

```
sudo apt install ./voidgram-desktop-x86_64.deb     # Debian, Ubuntu, Mint, ...
sudo dnf install ./voidgram-desktop-x86_64.rpm     # Fedora, RHEL, openSUSE (zypper), ...
```

Qt, FFmpeg and WebRTC build in parallel jobs and are cached; the last job builds the client.
