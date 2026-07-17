#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose.yaml"
BACKUP_IMAGE="${BACKUP_IMAGE:-nginx:1.29.8-alpine}"
SITE_A_VOLUME="internal-pages-site-a-data"
SITE_B_VOLUME="internal-pages-site-b-data"
SAMBA_WAS_STOPPED=0

usage() {
  cat <<'EOF'
用法：
  ./scripts/backup.sh BACKUP_ROOT

BACKUP_ROOT 必须位于仓库之外，推荐使用受保护的外部磁盘或备份目录。
脚本会短暂停止 Samba 写入，但 Nginx 页面仍可读取。
备份包含真实密码，生成目录和文件权限将限制为当前用户访问。
EOF
}

die() {
  printf '备份失败：%s\n' "$1" >&2
  exit 1
}

resume_samba() {
  if [[ "$SAMBA_WAS_STOPPED" -eq 1 ]]; then
    if docker compose -f "$COMPOSE_FILE" start samba >/dev/null 2>&1; then
      printf '%s\n' 'Samba 写入服务已恢复。'
    else
      printf '%s\n' '警告：Samba 自动恢复失败，请立即联系管理员。' >&2
    fi
    SAMBA_WAS_STOPPED=0
  fi
}

backup_volume() {
  local volume="$1"
  local archive="$2"
  local destination="$3"

  docker run --rm --entrypoint sh \
    -v "$volume:/source:ro" \
    -v "$destination:/backup" \
    "$BACKUP_IMAGE" \
    -c 'set -eu; test -z "$(find /source -type l -print | head -n 1)"; tar -C /source -czf "/backup/$1" .' \
    sh "$archive"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

[[ "$#" -eq 1 ]] || { usage >&2; exit 64; }

for command_name in docker tar shasum; do
  command -v "$command_name" >/dev/null 2>&1 || die "缺少命令 $command_name"
done

docker info >/dev/null 2>&1 || die 'Docker 引擎不可用'
docker compose -f "$COMPOSE_FILE" config --quiet || die 'Compose 配置无效'

for required_file in "$ROOT/deploy/.env" "$ROOT/deploy/samba/users.conf"; do
  [[ -f "$required_file" ]] || die "缺少运行时秘密文件：$required_file"
done

for volume in "$SITE_A_VOLUME" "$SITE_B_VOLUME"; do
  docker volume inspect "$volume" >/dev/null 2>&1 || die "缺少 Docker 卷：$volume"
done

umask 077
mkdir -p "$1"
BACKUP_ROOT="$(cd "$1" && pwd -P)"

case "$BACKUP_ROOT/" in
  "$ROOT/"*) die 'BACKUP_ROOT 不得位于 Git 仓库内' ;;
esac

TIMESTAMP="$(date -u '+%Y%m%dT%H%M%SZ')"
DESTINATION="$BACKUP_ROOT/internal-pages-$TIMESTAMP"
mkdir -m 700 "$DESTINATION"

trap resume_samba EXIT INT TERM

SAMBA_CONTAINER="$(docker compose -f "$COMPOSE_FILE" ps -q samba)"
if [[ -n "$SAMBA_CONTAINER" ]] && \
  [[ "$(docker inspect -f '{{.State.Running}}' "$SAMBA_CONTAINER" 2>/dev/null || true)" == "true" ]]; then
  SAMBA_WAS_STOPPED=1
  docker compose -f "$COMPOSE_FILE" stop samba >/dev/null
  printf '%s\n' 'Samba 写入已暂停，Nginx 只读访问保持运行。'
fi

[[ -z "$(find "$ROOT/deploy" -type l -print | head -n 1)" ]] || \
  die 'deploy/ 包含符号链接，拒绝创建运行时配置备份'
tar -C "$ROOT" -czf "$DESTINATION/runtime-config.tar.gz" deploy
backup_volume "$SITE_A_VOLUME" site-a-data.tar.gz "$DESTINATION"
backup_volume "$SITE_B_VOLUME" site-b-data.tar.gz "$DESTINATION"

(
  cd "$DESTINATION"
  shasum -a 256 \
    runtime-config.tar.gz \
    site-a-data.tar.gz \
    site-b-data.tar.gz > SHA256SUMS
)
chmod 600 "$DESTINATION"/*

resume_samba
trap - EXIT INT TERM

printf '备份完成：%s\n' "$DESTINATION"
printf '%s\n' '该目录包含真实密码和网站内容，只能通过受保护的内部渠道保存。'
