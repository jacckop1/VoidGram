#!/usr/bin/env bash
# Clones AyuGram Desktop at desktop/VERSION into ./src, applies desktop/patches and writes the
# Dockerfile of its generic Linux build (Rocky Linux 8, so the binary runs on Debian, Ubuntu, Fedora,
# Arch and the rest). Run from the repository root.
set -euo pipefail

root="$PWD"
version="$(cat desktop/VERSION)"
git clone --depth 1 --branch "$version" https://github.com/AyuGram/AyuGramDesktop.git src
cd src
git submodule update --init --depth=1
# cppgir is the one nested submodule a Linux build compiles.
git -C cmake submodule update --init --recursive --depth=1
for patch in "$root"/desktop/patches/*.patch; do
  git apply --index "$patch"
done
git diff --cached --check
cd Telegram/build/docker/centos_env
# The template is the Dockerfile itself, so the output is captured before the file is overwritten.
generated="$(DEBUG= python3 gen_dockerfile.py)"
printf '%s\n' "$generated" > Dockerfile
test "$(wc -l < Dockerfile)" -gt 100
rm -rf __pycache__
