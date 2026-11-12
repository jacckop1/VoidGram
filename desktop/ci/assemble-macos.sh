#!/usr/bin/env bash
# Makes one universal VoidGram.app out of the two halves a build produced (half/x86_64 and half/arm64, each
# with mac-<arch>.tar and app-name). Run from the repository root; the app is left in ./<name>.app and its
# name is printed on the last line.
#
# - A Mach-O file that is thin in both halves with different architectures is lipo'd together.
# - One that is already universal, or has the same architecture in both halves, stays as the arm64 half has it.
# - Files only the Intel half has stay too: the Swift runtime libraries are copied into Frameworks only for
#   the Intel build (they are what macOS 10.13 needs; Apple Silicon and newer systems use the system's).
set -euo pipefail

app="$(cat half/arm64/app-name)"
for arch in x86_64 arm64; do
  rm -rf "unpack/$arch" && mkdir -p "unpack/$arch"
  tar -xf "half/$arch/mac-$arch.tar" -C "unpack/$arch" 2>/dev/null
done
rm -rf "$app"
cp -R "unpack/arm64/$app" "$app"

# What only the Intel half has.
while IFS= read -r -d '' file; do
  rel="${file#unpack/x86_64/$app/}"
  if [ ! -e "$app/$rel" ] && [ ! -L "$app/$rel" ]; then
    mkdir -p "$(dirname "$app/$rel")"
    cp -a "$file" "$app/$rel"
    echo "from the Intel half only: $rel" >&2
  fi
done < <(find "unpack/x86_64/$app" \( -type f -o -type l \) -print0)

# Thin files that differ in architecture become universal.
while IFS= read -r -d '' file; do
  rel="${file#unpack/arm64/$app/}"
  archs="$(lipo -archs "$file" 2>/dev/null)" || continue
  [ "$archs" = "arm64" ] || continue # universal already, or not a plain arm64 file
  other="unpack/x86_64/$app/$rel"
  [ -f "$other" ] || { echo "$rel is only in the arm64 half" >&2; exit 1; }
  other_archs="$(lipo -archs "$other" 2>/dev/null)" || { echo "$rel: the Intel half's copy is not a Mach-O file" >&2; exit 1; }
  case "$other_archs" in
    *x86_64*) lipo -create "$file" "$other" -output "$app/$rel" ;;
    *) echo "$rel: the Intel half has $other_archs, kept as is" >&2 ;;
  esac
done < <(find "unpack/arm64/$app" -type f -perm +111 -print0)

# The app's own program and every dylib except the Swift runtime must now hold both architectures.
bad=0
while IFS= read -r -d '' file; do
  archs="$(lipo -archs "$file" 2>/dev/null)" || continue
  case "$(basename "$file")" in libswift*.dylib) continue ;; esac
  case "$archs" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) echo "$file is not universal: $archs" >&2; bad=1 ;;
  esac
done < <(find "$app" -type f -perm +111 -print0)
[ "$bad" = 0 ] || exit 1
lipo -info "$app/Contents/MacOS/"* >&2
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$app/Contents/Info.plist" 2>/dev/null >&2 || true
echo "$app"
