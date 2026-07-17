#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMPOSE_FILE="$ROOT/deploy/compose.yaml"
SITE_A_URL="http://127.0.0.1:8520/"
SITE_B_URL="http://127.0.0.1:8530/"
REQUIRE_DEPLOYMENT_MARKER=0
FAILURES=0

usage() {
  cat <<'EOF'
用法：
  ./scripts/acceptance-check.sh [选项]

选项：
  --site-a-url URL              site-a 首页地址
  --site-b-url URL              site-b 首页地址
  --require-deployment-marker   要求两个站点的部署完成标记包含必要字段
  --help                        显示帮助

本脚本只读取 Docker、Samba 和 HTTP 状态，不修改容器、卷或网站文件。
EOF
}

pass() {
  printf '通过：%s\n' "$1"
}

fail() {
  printf '失败：%s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "检测到命令 $1"
  else
    fail "缺少命令 $1"
  fi
}

check_container() {
  local container="$1"
  local running

  running="$(docker inspect -f '{{.State.Running}}' "$container" 2>/dev/null || true)"
  if [[ "$running" == "true" ]]; then
    pass "容器 $container 正在运行"
  else
    fail "容器 $container 未运行"
  fi
}

check_valid_user() {
  local config="$1"
  local section="$2"
  local expected_user="$3"

  if printf '%s\n' "$config" | awk -v section="$section" -v expected="$expected_user" '
    tolower($0) == "[" tolower(section) "]" { inside = 1; next }
    inside && /^\[/ { inside = 0 }
    inside && /^[[:space:]]*valid users[[:space:]]*=/ {
      value = $0
      sub(/^[^=]*=/, "", value)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
      if (value == expected) { found = 1 }
    }
    END { exit found ? 0 : 1 }
  '; then
    pass "Samba 共享 $section 只允许 $expected_user"
  else
    fail "Samba 共享 $section 的 valid users 不是 $expected_user"
  fi
}

check_http() {
  local site="$1"
  local url="$2"
  local headers="$TMP_DIR/$site.headers"
  local body="$TMP_DIR/$site.body"
  local status

  case "$url" in
    *\?*|*\#*)
      fail "$site URL 不得包含查询参数或片段：$url"
      return
      ;;
  esac

  if ! status="$(curl --connect-timeout 3 --max-time 15 -sS \
    -D "$headers" -o "$body" -w '%{http_code}' "$url")"; then
    fail "$site 无法访问：$url"
    return
  fi

  if [[ "$status" == "200" ]]; then
    pass "$site 首页返回 HTTP 200"
  else
    fail "$site 首页返回 HTTP $status"
  fi

  if grep -qi '^Cache-Control:.*private.*no-cache' "$headers"; then
    pass "$site 返回 Cache-Control: private, no-cache"
  else
    fail "$site 缺少预期的 Cache-Control"
  fi

  if grep -qi '^X-Content-Type-Options:[[:space:]]*nosniff' "$headers"; then
    pass "$site 返回 X-Content-Type-Options: nosniff"
  else
    fail "$site 缺少 X-Content-Type-Options: nosniff"
  fi

  if [[ "$REQUIRE_DEPLOYMENT_MARKER" -eq 1 ]]; then
    check_deployment_marker "$site" "${url%/}/.internal/deployment.json"
  fi
}

check_deployment_marker() {
  local site="$1"
  local url="$2"
  local body="$TMP_DIR/$site.deployment.json"
  local status

  if ! status="$(curl --connect-timeout 3 --max-time 15 -sS \
    -o "$body" -w '%{http_code}' "$url")"; then
    fail "$site 无法读取部署完成标记"
    return
  fi

  if [[ "$status" != "200" ]]; then
    fail "$site 部署完成标记返回 HTTP $status"
    return
  fi

  if grep -q '"deploymentId"[[:space:]]*:' "$body" && \
    grep -q '"deployedAt"[[:space:]]*:' "$body"; then
    pass "$site 部署完成标记包含 deploymentId 和 deployedAt"
  else
    fail "$site 部署完成标记缺少必要字段"
  fi
}

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --site-a-url)
      [[ "$#" -ge 2 ]] || { printf '%s\n' '--site-a-url 缺少参数。' >&2; exit 64; }
      SITE_A_URL="$2"
      shift 2
      ;;
    --site-b-url)
      [[ "$#" -ge 2 ]] || { printf '%s\n' '--site-b-url 缺少参数。' >&2; exit 64; }
      SITE_B_URL="$2"
      shift 2
      ;;
    --require-deployment-marker)
      REQUIRE_DEPLOYMENT_MARKER=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf '未知参数：%s\n' "$1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/internal-pages-acceptance.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

require_command docker
require_command curl

if [[ "$FAILURES" -gt 0 ]]; then
  printf '验收失败：缺少必要命令。\n' >&2
  exit 1
fi

if docker info >/dev/null 2>&1; then
  pass 'Docker 引擎可用'
else
  fail 'Docker 引擎不可用'
fi

if docker compose -f "$COMPOSE_FILE" config --quiet >/dev/null 2>&1; then
  pass 'Compose 配置有效'
else
  fail 'Compose 配置无效'
fi

check_container internal-pages-samba
check_container internal-pages-site-a-web
check_container internal-pages-site-b-web

SAMBA_CONFIG="$(docker exec internal-pages-samba \
  testparm -s /etc/samba/smb.conf 2>/dev/null || true)"
if [[ -n "$SAMBA_CONFIG" ]]; then
  pass 'Samba 运行配置可读取'
  check_valid_user "$SAMBA_CONFIG" site-a site-a-writer
  check_valid_user "$SAMBA_CONFIG" site-b site-b-writer
else
  fail '无法读取 Samba 运行配置'
fi

check_http site-a "$SITE_A_URL"
check_http site-b "$SITE_B_URL"

if [[ "$FAILURES" -gt 0 ]]; then
  printf '验收失败：共 %d 项未通过。\n' "$FAILURES" >&2
  exit 1
fi

printf '%s\n' '自动验收通过。仍需从 Windows 完成账号隔离、错误密码、访客、CRUD 和 Codex 盲操作验收。'
