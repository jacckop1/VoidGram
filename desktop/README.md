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
- **Settings ▸ VoidGram ▸ "VoidGram: frame and name"** (sponsors and the owner): choose a frame,
  its size and the name style, with a preview made of the avatar. The choice goes to the badge server,
  signed in with Mini App data Telegram gives for `@AyuZayavka_bot`.

Not ported: granted gifts and NFTs on profiles, bubble skins, the gold bubble frame.

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
jobs; each needs about 2 GB of memory. The binary is `~/.cache/voidgram-desktop/build/bin/Telegram`.

## Changing the patches

The work tree is `~/.cache/voidgram-desktop/src` (a clone of the tag in `VERSION`). Edit it, compile
one file with `ninja -C ~/.cache/voidgram-desktop/build <object>.o`, and export with
`git add -N Telegram/SourceFiles/voidgram && git diff --binary > desktop/patches/0001-voidgram.patch`.
The build script resets the tree to the tag and applies every patch, so a second run is safe.
