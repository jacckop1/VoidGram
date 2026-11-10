#!/usr/bin/env bash
# Prints the release notes for a desktop release: how to install, what is new and what the client
# has. "What is new" is desktop/release-notes/<tag>.md when it exists, and the commits that touched
# desktop/ since the previous desktop release (tag desktop-v*) are listed under it. Usage:
#   desktop/changelog.sh <new tag>
set -euo pipefail

new="${1:?usage: changelog.sh <new tag>}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
previous="$(git tag --list 'desktop-v*' --sort=-v:refname | grep -vx "$new" | head -n 1 || true)"
range="${previous:+$previous..}${new}"

cat <<TEXT
## VoidGram Desktop ${new#desktop-}

### Установка (Arch Linux и производные: Manjaro, EndeavourOS, CachyOS, Garuda)

Сборка сделана на актуальном Arch, поэтому сначала обнови систему, иначе будет ошибка вроде \`libssl.so.4: cannot open shared object file\`:

\`\`\`
sudo pacman -Syu
\`\`\`

Установка одной командой (скачивает этот релиз, ставит в \`~/.local\`, добавляет VoidGram в меню приложений и в лаунчеры, в том числе Hyprland):

\`\`\`
curl -fsSL https://raw.githubusercontent.com/neosay-dev/VoidGram/main/desktop/install.sh | bash
\`\`\`

Та же команда обновляет уже установленную версию. Удаление: \`curl -fsSL https://raw.githubusercontent.com/neosay-dev/VoidGram/main/desktop/install.sh | bash -s -- --uninstall\`.
Закрой VoidGram перед обновлением. Данные лежат в \`~/.local/share/AyuGramDesktop\`, их делит AyuGram Desktop: не запускай оба клиента одновременно.

### Что нового
TEXT
if [ -f "$here/release-notes/$new.md" ]; then
  cat "$here/release-notes/$new.md"
else
  echo "(без описания)"
fi
echo
if [ -n "$previous" ]; then
  echo "### Все изменения с ${previous#desktop-}"
else
  echo "### Все изменения"
fi
echo
git log --no-merges --reverse --format='%s' "$range" -- desktop \
  | grep -v '^Release ' | sed -E 's/^Desktop: ?//' | awk 'NF && !seen[$0]++ { print "- " toupper(substr($0,1,1)) substr($0,2) }'
echo
echo "### Что есть в клиенте"
echo
cat "$here/FEATURES.md"
