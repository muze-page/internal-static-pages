#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

status=0

while IFS= read -r -d '' file; do
  base="$(dirname "$file")"
  while IFS= read -r target; do
    test -n "$target" || continue
    if [[ ! -e "$base/$target" ]]; then
      printf '缺少相对链接目标：%s -> %s\n' "$file" "$target" >&2
      status=1
    fi
  done < <(perl -ne 'while (/\]\(((?:\.\.?\/)[^)#]+)(?:#[^)]*)?\)/g) { print "$1\n" }' "$file")
done < <(find . -path './.git' -prune -o -type f -name '*.md' -print0)

exit "$status"
