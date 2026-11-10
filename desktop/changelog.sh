#!/usr/bin/env bash
# Prints the release notes for a desktop release: how to install, what is new and what the client
# has. "What is new" is desktop/release-notes/<tag>.md when it exists, and the commits that touched
# desktop/ since the previous desktop release (tag desktop-v*) are listed under it. Usage:
#   desktop/changelog.sh <new tag>
set -euo pipefail

new="${1:?usage: changelog.sh <new tag>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
previous="$(git tag --list 'desktop-v*' --merged "$new" --sort=-v:refname | grep -vx "$new" | head -n 1 || true)"
range="${previous:+$previous..}${new}"

cat <<TEXT
## VoidGram Desktop ${new#desktop-}

### Установка / Install (Arch Linux, Manjaro, EndeavourOS, CachyOS, Garuda)

**RU:** сборка сделана на актуальном Arch, поэтому сначала обнови систему, иначе будет ошибка вроде \`libssl.so.4: cannot open shared object file\`.
**EN:** the build is made on current Arch, so update the system first, or you get an error like \`libssl.so.4: cannot open shared object file\`.

\`\`\`
sudo pacman -Syu
\`\`\`

**RU:** установка одной командой: скачивает этот релиз, ставит в \`~/.local\`, добавляет VoidGram в меню приложений и в лаунчеры, в том числе Hyprland. Та же команда обновляет установленную версию.
**EN:** one-command install: downloads this release, installs it to \`~/.local\` and adds VoidGram to the application menu and launchers, Hyprland included. The same command updates an installed copy.

\`\`\`
curl -fsSL https://raw.githubusercontent.com/neosay-dev/VoidGram/main/desktop/install.sh | bash
\`\`\`

**RU:** удаление / **EN:** uninstall:

\`\`\`
curl -fsSL https://raw.githubusercontent.com/neosay-dev/VoidGram/main/desktop/install.sh | bash -s -- --uninstall
\`\`\`

**RU:** закрой VoidGram перед обновлением. Данные лежат в \`~/.local/share/AyuGramDesktop\` и общие с AyuGram Desktop: не запускай оба клиента одновременно.
**EN:** close VoidGram before updating. Data lives in \`~/.local/share/AyuGramDesktop\`, shared with AyuGram Desktop: do not run both at once.

### Что нового / What's new

#### Русский
TEXT
for lang in "" ".en"; do
  file="$here/release-notes/$new$lang.md"
  if [ -n "$lang" ]; then printf '\n#### English\n'; fi
  if [ -f "$file" ]; then cat "$file"; else echo "(без описания / no notes)"; fi
done
echo
if [ -n "$previous" ]; then
  echo "### Все изменения / All changes since ${previous#desktop-}"
else
  echo "### Все изменения / All changes"
fi
echo
git log --no-merges --reverse --format='%s' "$range" -- desktop \
  | grep -v '^Release ' | sed -E 's/^Desktop: ?//' | awk 'NF && !seen[$0]++ { print "- " toupper(substr($0,1,1)) substr($0,2) }'
echo
echo "### Что есть в клиенте / What the client has"
echo
echo "#### Русский"
cat "$here/FEATURES.md"
echo
echo "#### English"
cat "$here/FEATURES.en.md"
