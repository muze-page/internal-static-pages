#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff --check
  git diff --cached --check
fi

./scripts/check-relative-links.sh

if find . -path './.git' -prune -o -type f \( \
  -name '.env' -o \
  -name 'users.conf' -o \
  -name '*.key' -o \
  -name '*.pem' -o \
  -name '*.p12' -o \
  -name '*.pfx' \
\) -print | grep -q .; then
  printf '%s\n' '发现禁止进入仓库的秘密文件。' >&2
  exit 1
fi

if grep -R -n -E \
  '192\.168\.|(^|[^0-9])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}|(^|[^0-9])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}|/Users/[A-Za-z0-9._-]+|[A-Za-z]:\\Users\\|[M]uze-For-Mac-mini|[y]zh|[c]xz|BEGIN [A-Z ]*PRIVATE KEY' \
  --exclude-dir=.git .; then
  printf '%s\n' '发现未脱敏的内网地址、人员或设备标识、个人主目录或私钥。' >&2
  exit 1
fi

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  docker compose -f deploy/compose.yaml config --quiet
else
  printf '%s\n' '提示：未检测到 Docker Compose，跳过 Compose 语法检查。'
fi

if command -v gitleaks >/dev/null 2>&1; then
  gitleaks dir . --redact --no-banner
else
  printf '%s\n' '提示：未检测到 Gitleaks，提交和推送前必须补做秘密扫描。'
fi

printf '%s\n' '仓库检查通过。'
