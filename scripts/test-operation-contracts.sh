#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/internal-pages-contracts.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

FIXTURE_ROOT="$TMP_DIR/fixture"
BACKUP_DIR="$TMP_DIR/backup"
BAD_BACKUP_DIR="$TMP_DIR/bad-backup"
LINK_BACKUP_DIR="$TMP_DIR/link-backup"
OUTSIDE_BACKUP_DIR="$TMP_DIR/outside-backup"

mkdir -p \
  "$FIXTURE_ROOT/deploy/samba" \
  "$FIXTURE_ROOT/deploy/nginx" \
  "$TMP_DIR/site-a" \
  "$TMP_DIR/site-b" \
  "$BACKUP_DIR"

printf '%s\n' 'services: {}' > "$FIXTURE_ROOT/deploy/compose.yaml"
printf '%s\n' 'SITE_A_SMB_PASSWORD=<TEST_ONLY>' > "$FIXTURE_ROOT/deploy/.env"
printf '%s\n' 'site-a-writer:<TEST_ONLY>' > "$FIXTURE_ROOT/deploy/samba/users.conf"
printf '%s\n' 'site-a fixture' > "$TMP_DIR/site-a/index.html"
printf '%s\n' 'site-b fixture' > "$TMP_DIR/site-b/index.html"

tar -C "$FIXTURE_ROOT" -czf "$BACKUP_DIR/runtime-config.tar.gz" deploy
tar -C "$TMP_DIR/site-a" -czf "$BACKUP_DIR/site-a-data.tar.gz" .
tar -C "$TMP_DIR/site-b" -czf "$BACKUP_DIR/site-b-data.tar.gz" .

(
  cd "$BACKUP_DIR"
  shasum -a 256 \
    runtime-config.tar.gz \
    site-a-data.tar.gz \
    site-b-data.tar.gz > SHA256SUMS
)

"$ROOT/scripts/restore.sh" "$BACKUP_DIR" >/dev/null

cp -R "$BACKUP_DIR" "$BAD_BACKUP_DIR"
printf '%s\n' 'not-a-valid-hash  ../outside-file' >> "$BAD_BACKUP_DIR/SHA256SUMS"
if "$ROOT/scripts/restore.sh" "$BAD_BACKUP_DIR" >/dev/null 2>&1; then
  printf '%s\n' '恢复脚本错误接受了包含额外路径的校验清单。' >&2
  exit 1
fi

cp -R "$BACKUP_DIR" "$LINK_BACKUP_DIR"
ln -s index.html "$TMP_DIR/site-a/linked-index.html"
tar -C "$TMP_DIR/site-a" -czf "$LINK_BACKUP_DIR/site-a-data.tar.gz" .
(
  cd "$LINK_BACKUP_DIR"
  shasum -a 256 \
    runtime-config.tar.gz \
    site-a-data.tar.gz \
    site-b-data.tar.gz > SHA256SUMS
)
if "$ROOT/scripts/restore.sh" "$LINK_BACKUP_DIR" >/dev/null 2>&1; then
  printf '%s\n' '恢复脚本错误接受了包含符号链接的归档。' >&2
  exit 1
fi

cp -R "$BACKUP_DIR" "$OUTSIDE_BACKUP_DIR"
printf '%s\n' 'outside fixture' > "$FIXTURE_ROOT/outside.txt"
tar -C "$FIXTURE_ROOT" -czf "$OUTSIDE_BACKUP_DIR/runtime-config.tar.gz" deploy outside.txt
(
  cd "$OUTSIDE_BACKUP_DIR"
  shasum -a 256 \
    runtime-config.tar.gz \
    site-a-data.tar.gz \
    site-b-data.tar.gz > SHA256SUMS
)
if "$ROOT/scripts/restore.sh" "$OUTSIDE_BACKUP_DIR" >/dev/null 2>&1; then
  printf '%s\n' '恢复脚本错误接受了 deploy/ 之外的运行时文件。' >&2
  exit 1
fi

if "$ROOT/scripts/acceptance-check.sh" --unknown-option >/dev/null 2>&1; then
  printf '%s\n' '验收脚本错误接受了未知参数。' >&2
  exit 1
fi

if "$ROOT/scripts/backup.sh" >/dev/null 2>&1; then
  printf '%s\n' '备份脚本错误接受了缺失的 BACKUP_ROOT。' >&2
  exit 1
fi

if "$ROOT/scripts/restore.sh" "$BACKUP_DIR" --apply WRONG >/dev/null 2>&1; then
  printf '%s\n' '恢复脚本错误接受了无效确认词。' >&2
  exit 1
fi

printf '%s\n' '运维脚本接口契约测试通过。'
