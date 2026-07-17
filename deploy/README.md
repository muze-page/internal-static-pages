# 部署配置

本目录包含当前双站点拓扑的可执行配置。真实密码和 `users.conf` 只在目标 Mac mini 上生成，不进入 Git。

完整前置条件、部署和回退步骤见[新 Mac mini 部署手册](../docs/operations/new-mac-mini.md)，正式交付前使用[试运行验收清单](../docs/operations/pilot-checklist.md)记录证据。

## 1. 创建网站卷

确认目标机没有同名卷后执行：

```bash
docker volume create internal-pages-site-a-data
docker volume create internal-pages-site-b-data
```

## 2. 在目标机生成密码文件

在 `deploy/` 目录执行，过程不会打印密码：

```bash
set -euo pipefail
umask 077

SITE_A_SMB_PASSWORD="$(openssl rand -hex 24)"
SITE_B_SMB_PASSWORD="$(openssl rand -hex 24)"

test "$SITE_A_SMB_PASSWORD" != "$SITE_B_SMB_PASSWORD"

printf 'SITE_A_SMB_PASSWORD=%s\nSITE_B_SMB_PASSWORD=%s\n' \
  "$SITE_A_SMB_PASSWORD" \
  "$SITE_B_SMB_PASSWORD" > .env

printf 'site-a-writer:1000:site-a:1000:%s:/shares/site-a\nsite-b-writer:1001:site-b:1001:%s:/shares/site-b\n' \
  "$SITE_A_SMB_PASSWORD" \
  "$SITE_B_SMB_PASSWORD" > samba/users.conf

chmod 600 .env samba/users.conf
unset SITE_A_SMB_PASSWORD SITE_B_SMB_PASSWORD
```

## 3. 创建占位首页

先写入不含秘密的占位页面，再启动服务：

```bash
docker run --rm --entrypoint sh \
  -v internal-pages-site-a-data:/site \
  nginx:1.29.8-alpine \
  -c 'printf "%s\n" "<!doctype html><html lang=zh-CN><meta charset=utf-8><title>site-a</title><h1>site-a 等待重新发布</h1>" > /site/index.html'

docker run --rm --entrypoint sh \
  -v internal-pages-site-b-data:/site \
  nginx:1.29.8-alpine \
  -c 'printf "%s\n" "<!doctype html><html lang=zh-CN><meta charset=utf-8><title>site-b</title><h1>site-b 等待重新发布</h1>" > /site/index.html'
```

## 4. 检查并启动

```bash
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

启动后仍必须按操作手册完成正确登录、错误密码、访客、交叉拒绝、CRUD、HTTP、缓存头和重启验证。

可以先执行不修改运行状态的基础检查：

```bash
../scripts/acceptance-check.sh
```

备份和恢复命令必须从仓库根目录执行。备份包含真实密码和网站内容，只能保存到仓库外的受保护目录：

```bash
./scripts/backup.sh <BACKUP_ROOT>
./scripts/restore.sh <BACKUP_DIR>
```

第二条命令默认只验证备份。真实恢复具有破坏性，必须先阅读试运行验收清单并显式使用 `--apply RESTORE`。
