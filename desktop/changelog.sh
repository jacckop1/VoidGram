#!/usr/bin/env bash
# Prints what changed in the desktop client since the previous desktop release (tag desktop-v*), or
# since the start for the first one: one line per commit that touched desktop/. Usage:
#   desktop/changelog.sh <new tag>
set -euo pipefail

new="${1:?usage: changelog.sh <new tag>}"
previous="$(git tag --list 'desktop-v*' --sort=-v:refname | grep -vx "$new" | head -n 1 || true)"
range="${previous:+$previous..}${new}"

echo "## VoidGram Desktop ${new#desktop-}"
echo
if [ -n "$previous" ]; then
  echo "Changes since ${previous#desktop-}:"
else
  echo "First release. What it has:"
fi
echo
git log --no-merges --reverse --format='%s' "$range" -- desktop \
  | sed -E 's/^Desktop: ?//' | awk 'NF && !seen[$0]++ { print "- " toupper(substr($0,1,1)) substr($0,2) }'
