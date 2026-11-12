#!/usr/bin/env bash
# Makes one universal VoidGram.app out of the two halves a build produced (half/x86_64 and half/arm64,
# each with mac-<arch>.tar and app-name). A Mach-O file that is thin in both halves is lipo'd together; one that
# is already universal (the Swift runtime copied from Xcode) is kept as it is. Run from the repository root;
# the app is left in ./<name>.app and its name is printed on the last line.
set -euo pipefail

app="$(cat half/arm64/app-name)"
for arch in x86_64 arm64; do
  rm -rf "unpack/$arch" && mkdir -p "unpack/$arch"
  tar -xf "half/$arch/mac-$arch.tar" -C "unpack/$arch"
done
rm -rf "$app"
cp -R "unpack/arm64/$app" "$app"

while IFS= read -r -d '' file; do
  rel="${file#unpack/arm64/$app/}"
  info="$(lipo -info "$file" 2>/dev/null)" || continue
  case "$info" in
    *"Non-fat file"*) ;;
    *) continue ;; # already universal
  esac
  other="unpack/x86_64/$app/$rel"
  [ -f "$other" ] || { echo "$rel is only in the arm64 bundle" >&2; exit 1; }
  lipo -create "$file" "$other" -output "$app/$rel"
done < <(find "unpack/arm64/$app" -type f -perm +111 -print0)

# Everything executable must now hold both architectures.
while IFS= read -r -d '' file; do
  info="$(lipo -info "$file" 2>/dev/null)" || continue
  case "$info" in
    *x86_64*arm64*|*arm64*x86_64*) ;;
    *) echo "$file is not universal: $info" >&2; exit 1 ;;
  esac
done < <(find "$app" -type f -perm +111 -print0)
lipo -info "$app/Contents/MacOS/"*
/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$app/Contents/Info.plist" 2>/dev/null || true
echo "$app"
