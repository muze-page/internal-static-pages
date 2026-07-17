#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose.yaml"
BACKUP_IMAGE="${BACKUP_IMAGE:-nginx:1.29.8-alpine}"
SITE_A_VOLUME="internal-pages-site-a-data"
SITE_B_VOLUME="internal-pages-site-b-data"
APPLY=0
RESTORE_COMPLETED=0

usage() {
  cat <<'EOF'
用法：
  ./scripts/restore.sh BACKUP_DIR
  ./scripts/restore.sh BACKUP_DIR --apply RESTORE

不带 --apply 时只验证备份完整性，不修改任何文件、容器或 Docker 卷。
带 --apply RESTORE 时会停止服务、清空两个目标卷、恢复配置和网站数据。
执行真实恢复前，必须先为当前环境创建另一份可用备份。
EOF
}

die() {
  printf '恢复失败：%s\n' "$1" >&2
  exit 1
}

on_exit() {
  local status="$?"
  if [[ "$APPLY" -eq 1 && "$RESTORE_COMPLETED" -ne 1 ]]; then
    printf '%s\n' '恢复未完成，服务可能保持停止状态；不要切换流量，请联系管理员。' >&2
  fi
  exit "$status"
}

validate_archive_paths() {
  local archive="$1"

  if tar -tzf "$archive" | awk '
    /^\// { bad = 1 }
    /(^|\/)\.\.(\/|$)/ { bad = 1 }
    END { exit bad ? 1 : 0 }
  '; then
    if tar -tvzf "$archive" | awk '
      substr($1, 1, 1) != "-" && substr($1, 1, 1) != "d" { bad = 1 }
      END { exit bad ? 1 : 0 }
    '; then
      return 0
    fi

    die "压缩包包含符号链接、硬链接或其他不支持的条目：$archive"
  fi

  die "压缩包包含不安全路径：$archive"
}

restore_volume() {
  local volume="$1"
  local archive="$2"

  docker run --rm --entrypoint sh \
    -v "$volume:/target" \
    -v "$BACKUP_DIR:/backup:ro" \
    "$BACKUP_IMAGE" \
    -c 'set -eu; find /target -mindepth 1 -maxdepth 1 -exec rm -rf {} +; tar -C /target -xzf "/backup/$1"' \
    sh "$archive"
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

[[ "$#" -ge 1 && "$#" -le 3 ]] || { usage >&2; exit 64; }

if [[ "$#" -gt 1 ]]; then
  [[ "$#" -eq 3 && "$2" == "--apply" && "$3" == "RESTORE" ]] || {
    usage >&2
    exit 64
  }
  APPLY=1
fi

for command_name in tar shasum; do
  command -v "$command_name" >/dev/null 2>&1 || die "缺少命令 $command_name"
done

[[ -d "$1" ]] || die "备份目录不存在：$1"
BACKUP_DIR="$(cd "$1" && pwd -P)"

for required_file in \
  SHA256SUMS \
  runtime-config.tar.gz \
  site-a-data.tar.gz \
  site-b-data.tar.gz; do
  [[ -f "$BACKUP_DIR/$required_file" ]] || die "备份缺少文件：$required_file"
done

if ! awk '
  NF != 2 { bad = 1 }
  $2 != "runtime-config.tar.gz" &&
  $2 != "site-a-data.tar.gz" &&
  $2 != "site-b-data.tar.gz" { bad = 1 }
  { seen[$2]++ }
  END {
    valid = NR == 3 &&
      seen["runtime-config.tar.gz"] == 1 &&
      seen["site-a-data.tar.gz"] == 1 &&
      seen["site-b-data.tar.gz"] == 1
    if (bad || !valid) { exit 1 }
    exit 0
  }
' "$BACKUP_DIR/SHA256SUMS"; then
  die 'SHA256SUMS 必须且只能包含三个预期归档'
fi

(
  cd "$BACKUP_DIR"
  shasum -a 256 -c SHA256SUMS
)

validate_archive_paths "$BACKUP_DIR/runtime-config.tar.gz"
validate_archive_paths "$BACKUP_DIR/site-a-data.tar.gz"
validate_archive_paths "$BACKUP_DIR/site-b-data.tar.gz"

if ! tar -tzf "$BACKUP_DIR/runtime-config.tar.gz" | awk '
  $0 != "deploy" && $0 != "deploy/" && $0 !~ /^deploy\// { bad = 1 }
  END { exit bad ? 1 : 0 }
'; then
  die '运行时配置备份包含 deploy/ 之外的路径'
fi

tar -tzf "$BACKUP_DIR/runtime-config.tar.gz" | grep -qx 'deploy/compose.yaml' || \
  die '运行时配置备份缺少 deploy/compose.yaml'
tar -tzf "$BACKUP_DIR/runtime-config.tar.gz" | grep -qx 'deploy/.env' || \
  die '运行时配置备份缺少 deploy/.env'
tar -tzf "$BACKUP_DIR/runtime-config.tar.gz" | grep -qx 'deploy/samba/users.conf' || \
  die '运行时配置备份缺少 deploy/samba/users.conf'

if [[ "$APPLY" -eq 0 ]]; then
  printf '%s\n' '备份校验通过；未修改配置、容器或 Docker 卷。'
  printf '确认已有当前环境安全备份后，可执行：\n  %q %q --apply RESTORE\n' "$0" "$BACKUP_DIR"
  exit 0
fi

for command_name in docker; do
  command -v "$command_name" >/dev/null 2>&1 || die "缺少命令 $command_name"
done
docker info >/dev/null 2>&1 || die 'Docker 引擎不可用'

trap on_exit EXIT INT TERM

docker compose -f "$COMPOSE_FILE" down --remove-orphans

for volume in "$SITE_A_VOLUME" "$SITE_B_VOLUME"; do
  if ! docker volume inspect "$volume" >/dev/null 2>&1; then
    docker volume create "$volume" >/dev/null
  fi
done

restore_volume "$SITE_A_VOLUME" site-a-data.tar.gz
restore_volume "$SITE_B_VOLUME" site-b-data.tar.gz
tar -C "$ROOT" -xzf "$BACKUP_DIR/runtime-config.tar.gz"
chmod 600 "$ROOT/deploy/.env" "$ROOT/deploy/samba/users.conf"

docker compose -f "$COMPOSE_FILE" config --quiet
docker compose -f "$COMPOSE_FILE" up -d
"$ROOT/scripts/acceptance-check.sh"

RESTORE_COMPLETED=1
trap - EXIT INT TERM
printf '%s\n' '恢复完成并通过基础自动验收。仍需执行 Windows 账号隔离和 Codex 盲操作验收。'
