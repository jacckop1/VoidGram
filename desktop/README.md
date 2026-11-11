# VoidGram Desktop

VoidGram for Windows, Linux and macOS is AyuGram Desktop (`VERSION`) with the patches in `patches/`. It reads the same
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

On Linux, the data folder is still the one AyuGram Desktop uses (`~/.local/share/AyuGramDesktop`), so this client and
AyuGram Desktop share one login and settings. Run only one of them at a time. On macOS, VoidGram uses
`~/Library/Application Support/VoidGram Desktop/` and a separate bundle identifier, `com.voidgram.desktop`;
it does not automatically copy an existing AyuGram account.

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

One command installs on any Linux; `desktop/install.sh` reads `/etc/os-release` and picks the
build: the Arch archive into `~/.local` on the Arch family, the `.deb` through apt on Debian and
Ubuntu, the `.rpm` through dnf or zypper on Fedora, RHEL and openSUSE, and the generic archive into
`~/.local` anywhere else (`--local` skips the package manager, `--distro ID` overrides the guess):

    curl -fsSL https://raw.githubusercontent.com/neosay-dev/VoidGram/main/desktop/install.sh | bash

Or unpack a build and run `./install.sh`: it copies the program and icons to `~/.local`, adds
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

## macOS (Intel and Apple Silicon)

The macOS port uses the same `VERSION` and patches as Windows and Linux. Its extra patch,
`patches/0002-macos.patch`, changes the native application menu and title preview, assigns the
VoidGram bundle identifier, and generates all twelve macOS `.icns` resources from the patched
VoidGram PNGs. The default Finder icon and alternate Dock icons therefore use the same artwork
as the other desktop versions. This does not add the phone-only features listed above.

### GitHub Actions

Pushing changes to the macOS build scripts, desktop patches or `VERSION` starts
**VoidGram Desktop (macOS)** automatically. You can also run it manually in Actions
(`.github/workflows/desktop-macos.yml`) once the workflow is on the default branch. It uses the
[GitHub macOS 26 image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
with Xcode and needs the existing `TELEGRAM_API_ID` and `TELEGRAM_API_HASH` repository secrets.
No Apple developer certificate is required for this development package.

The workflow builds a universal application containing `x86_64` and `arm64`, verifies its bundle
identity, icon, architecture slices and ad hoc signature, then uploads:

- `voidgram-desktop-macos-universal.dmg`, with an Applications shortcut;
- `voidgram-desktop-macos-universal.zip`, preserving the application bundle and permissions;
- `SHA256SUMS-macos.txt`.

Leave `release_tag` empty for artifacts only, or provide an existing release tag to attach these
files to that release. Dependency preparation has a time limit and saves its progress before
the client build. If preparation times out, check that the cache was saved, then rerun. A compile
error needs fixing; rerunning does not fix it.

These packages use an ad hoc signature. They are not signed with Developer ID or notarized, so
macOS may require approval in **System Settings → Privacy & Security → Open Anyway**. Distribution
with normal Gatekeeper acceptance still requires Developer ID signing and Apple notarization.

### Local build on a Mac

Install full Xcode, select its developer directory and install the build tools:

```sh
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
brew install git automake libtool cmake wget pkg-config gnu-tar ninja nasm meson
TDESKTOP_API_ID=... TDESKTOP_API_HASH=... bash desktop/build-macos.sh
```

Use your own API credentials from <https://my.telegram.org>. The default working directory is
`~/.cache/voidgram-desktop-macos`, separate from the Linux source and build. Libraries are built
for both architectures; allow at least the upstream estimate of 55 GB of free disk space and
several hours for the first run. `JOBS` defaults to 3. `BUILD_TYPE=Debug` selects a Debug build;
the default is Release. A new patch set requires a fresh `WORK_DIR`, or moving the old `src`
directory aside; the script refuses to overwrite a different patch set or unstaged source edits.

Individual phases can be resumed with `prepare`, `libraries`, `build` or `package`:

```sh
bash desktop/build-macos.sh prepare
bash desktop/build-macos.sh libraries
TDESKTOP_API_ID=... TDESKTOP_API_HASH=... bash desktop/build-macos.sh build
bash desktop/build-macos.sh package
```

The app is at `~/.cache/voidgram-desktop-macos/src/out/Release/VoidGram.app`, and packages are in
`~/.cache/voidgram-desktop-macos/dist`. `DIST_DIR` overrides the package directory. Packaging copies
the built app before applying an ad hoc signature, preserving the original build output.

### Validation status

The macOS patch was checked against the pinned AyuGram v7.2.9 source together with the existing
desktop patch. Shell/YAML checks and simulated packaging checks run on Linux; compiling, launching,
calls, notifications, Dock icon switching and installation still need verification on a Mac.
