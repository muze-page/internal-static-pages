# 新 Mac mini 全新部署与同事重新发布手册

> 使用本独立仓库时，`deploy/` 中的 Compose、Samba 和 Nginx 文件是可执行配置源。本手册中的配置块用于解释和审阅；部署时应从仓库复制 `deploy/`，不要手工重新录入。

## 1. 目的与决策

本文用于在新的 Mac mini M4 上重新部署当前内网静态页面服务，并让 同事 A、同事 B 从各自 Windows 项目重新发布网站内容。

本次采用“重建服务、不迁移网站卷”的方式：

- 保留当前服务拓扑、网站 ID、SMB 账号、共享名和网页端口；
- 在新机创建全新的空 Docker 卷；
- 在新机重新生成每个网站的随机密码；
- 重新生成 `.env` 与 `AGENTS.md` 交接包；
- 由同事对 Codex 说“更新内网页面”，把本地最新静态产物发布到新机；
- 旧机保留到两个网站均完成验收后再下线。

这样比迁移旧 Docker 卷更简单，也能顺便轮换密码。前提是 同事 A、同事 B 的本地项目仍是网站内容的权威来源。

执行前必须让 同事 A、同事 B 分别确认本地项目能够构建，并包含当前网站需要的全部 HTML、CSS、JavaScript、图片和字体。如果旧网站卷中存在本地项目没有的文件、手工上传内容或唯一数据，应停止使用本手册，改用 Docker 卷迁移方案。

推荐给新机分配一个新的固定内网 IP，不接管旧机的 `<OLD_MAC_IP>`。旧机还承载其他既有服务；只迁移静态页面就复用旧 IP，会同时影响旧机上的非本项目服务。因为两位同事本来就要替换新 `.env`，使用新地址不会增加其日常操作。

## 2. 最终资源模型

| 网站 | SMB 共享 | SMB 账号 | 网页端口 | Docker 卷 |
|---|---|---|---|---|
| site-a | `\\<NEW_MAC_IP>\site-a` | `site-a-writer` | `8520` | `internal-pages-site-a-data` |
| site-b | `\\<NEW_MAC_IP>\site-b` | `site-b-writer` | `8530` | `internal-pages-site-b-data` |

统一资源：

```text
Samba 容器：internal-pages-samba
Samba 端口：445
Samba 镜像：dockurr/samba:4.23.8
Nginx 镜像：nginx:1.29.8-alpine
Compose 目录：~/internal-pages-poc
Docker 网络：internal-pages-poc
```

为了降低迁移风险，容器名、卷名、网络名和目录名暂时保持与已验证配置一致。名称中的 `poc` 不影响功能，正式改名应作为后续独立变更处理。

## 3. 执行前必须确认的信息

执行者必须先向管理员确认：

```text
新 Mac 当前临时 IP：<NEW_MAC_TEMP_IP>
新 Mac 最终 IP：<NEW_MAC_IP>
Mac 管理账号：<ADMIN_USER>
旧 Mac IP：<OLD_MAC_IP>
最终是否复用 <OLD_MAC_IP>：是 / 否
```

不得带着 `<NEW_MAC_IP>` 等占位符继续部署。

默认选择“否”。只有旧机上的全部服务都已经迁移、下线或确认不再需要时，才允许新机接管 `<OLD_MAC_IP>`。

如果新机最终复用 `<OLD_MAC_IP>`：

- 部署和验收阶段必须先使用临时 IP；
- 旧机和新机不得同时使用 `<OLD_MAC_IP>`；
- 正式切换前必须先停止旧机服务并让旧机退出该 IP；
- 同事仍需替换 `.env`，因为本次会生成新密码。

## 4. 新机前置准备

### 4.1 系统与网络

在新机上完成：

1. 安装所有必要的 macOS 更新；
2. 设置临时固定 IP 或 DHCP 保留；
3. 开启“系统设置 → 通用 → 共享 → 远程登录”；
4. 远程登录只允许 IT 管理账号；
5. 关闭 macOS“文件共享”，避免系统 SMB 占用 `445`；
6. 不配置路由器端口转发，不把 `445`、`8520`、`8530` 暴露到公网；
7. 允许组织内网访问 Docker Desktop 提供的三个端口。

### 4.2 Docker

安装并启动 Docker Desktop，然后执行：

```bash
hostname
sw_vers
uname -m
docker version
docker compose version
docker info
```

要求：

- `uname -m` 为 `arm64`；
- Docker 客户端和服务端均可用；
- Docker Desktop 已设置为登录后自动启动；
- 后续所有容器使用 `restart: unless-stopped`。

Docker Desktop 的“登录后自动启动”不等于开机后无人值守启动。如果 macOS 没有自动登录，断电重启后仍需要 IT 管理员登录一次。不得为了省事直接开启自动登录；应把这一限制写入运维记录，并在验收时实际重启测试。如果正式环境要求无人登录也能恢复，需要另行评估受支持的常驻容器运行方式。

### 4.3 端口预检

执行：

```bash
for port in 445 8520 8530; do
  if lsof -nP -iTCP:"$port" -sTCP:LISTEN; then
    echo "端口 $port 已被占用，停止部署并检查。"
    exit 1
  fi
done
```

如果端口被占用，不得直接杀进程或改用其他端口；先确认是不是 macOS 文件共享或既有组织服务。

## 5. 创建服务目录和新密码

执行：

```bash
set -euo pipefail
export BASE_DIR="$HOME/internal-pages-poc"
mkdir -p "$BASE_DIR"
cd "$BASE_DIR"

umask 077
SITE_A_SMB_PASSWORD="$(openssl rand -hex 24)"
SITE_B_SMB_PASSWORD="$(openssl rand -hex 24)"

test -n "$SITE_A_SMB_PASSWORD"
test -n "$SITE_B_SMB_PASSWORD"
test "$SITE_A_SMB_PASSWORD" != "$SITE_B_SMB_PASSWORD"

printf 'SITE_A_SMB_PASSWORD=%s\nSITE_B_SMB_PASSWORD=%s\n' \
  "$SITE_A_SMB_PASSWORD" \
  "$SITE_B_SMB_PASSWORD" > .env

printf 'site-a-writer:1000:site-a:1000:%s:/shares/site-a\nsite-b-writer:1001:site-b:1001:%s:/shares/site-b\n' \
  "$SITE_A_SMB_PASSWORD" \
  "$SITE_B_SMB_PASSWORD" > users.conf

chmod 600 .env users.conf
```

要求：

- 不得把密码打印到终端；
- 不得使用旧聊天中的 Makers Token 或其他历史密码；
- 不得把 `.env`、`users.conf` 加入 Git；
- Shell 会话结束前完成交接包生成，否则应从服务器 `.env` 脱敏读取，不要重新生成不同密码。

## 6. 创建 Compose 配置

在 `$BASE_DIR/compose.yaml` 写入：

```yaml
services:
  samba:
    image: dockurr/samba:4.23.8
    container_name: internal-pages-samba
    restart: unless-stopped
    ports:
      - "0.0.0.0:445:445"
    volumes:
      - ./smb.conf:/etc/samba/smb.conf:ro
      - ./users.conf:/etc/samba/users.conf:ro
      - site-a-data:/shares/site-a
      - site-b-data:/shares/site-b
    networks:
      - internal-pages

  site-a-web:
    image: nginx:1.29.8-alpine
    container_name: internal-pages-site-a-web
    restart: unless-stopped
    ports:
      - "0.0.0.0:8520:80"
    volumes:
      - site-a-data:/srv/sites/site-a:ro
      - ./nginx.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - internal-pages

  site-b-web:
    image: nginx:1.29.8-alpine
    container_name: internal-pages-site-b-web
    restart: unless-stopped
    ports:
      - "0.0.0.0:8530:80"
    volumes:
      - site-b-data:/srv/sites/site-b:ro
      - ./nginx-site-b.conf:/etc/nginx/conf.d/default.conf:ro
    networks:
      - internal-pages

networks:
  internal-pages:
    name: internal-pages-poc

volumes:
  site-a-data:
    name: internal-pages-site-a-data
    external: true
  site-b-data:
    name: internal-pages-site-b-data
    external: true
```

配置文件权限可以为 `0644`；含密码的 `.env` 和 `users.conf` 必须保持 `0600`。

## 7. 创建 Samba 配置

在 `$BASE_DIR/smb.conf` 写入：

```ini
[global]
    server string = internal-pages
    security = user
    map to guest = Never
    server min protocol = SMB2
    load printers = no
    printing = bsd
    printcap name = /dev/null
    disable spoolss = yes
    host msdfs = no
    wide links = no
    follow symlinks = no
    unix extensions = no
    acl allow execute always = yes
    mangled names = no
    dos charset = CP850
    unix charset = UTF-8

[site-a]
    path = /shares/site-a
    comment = site-a
    browseable = yes
    writable = yes
    read only = no
    guest ok = no
    valid users = site-a-writer
    force user = site-a-writer
    force group = site-a
    create mask = 0644
    directory mask = 0755

[site-b]
    path = /shares/site-b
    comment = site-b
    browseable = yes
    writable = yes
    read only = no
    guest ok = no
    valid users = site-b-writer
    force user = site-b-writer
    force group = site-b
    create mask = 0644
    directory mask = 0755
```

不要增加公共共享、访客访问、宿主机目录或其他账号。

## 8. 创建 Nginx 配置

在 `$BASE_DIR/nginx.conf` 写入：

```nginx
server {
    listen 80 default_server;
    server_name _;

    root /srv/sites/site-a;
    index index.html;

    add_header Cache-Control "private, no-cache" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

在 `$BASE_DIR/nginx-site-b.conf` 写入：

```nginx
server {
    listen 80 default_server;
    server_name _;

    root /srv/sites/site-b;
    index index.html;

    add_header Cache-Control "private, no-cache" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer" always;

    location / {
        try_files $uri $uri/ =404;
    }
}
```

## 9. 创建网站卷和占位页面

首先确认同名卷不存在：

```bash
if docker volume inspect internal-pages-site-a-data >/dev/null 2>&1; then
  echo "site-a 数据卷已存在，停止部署，禁止覆盖。"
  exit 1
fi

if docker volume inspect internal-pages-site-b-data >/dev/null 2>&1; then
  echo "site-b 数据卷已存在，停止部署，禁止覆盖。"
  exit 1
fi
```

创建新卷：

```bash
docker volume create internal-pages-site-a-data
docker volume create internal-pages-site-b-data
```

写入临时占位页面：

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

占位页面只用于确认 Nginx 和网络正常，之后由同事的真实项目覆盖。

## 10. 启动服务

执行：

```bash
cd "$BASE_DIR"
docker compose config --quiet
docker compose pull
docker compose up -d
docker compose ps
```

验证 Samba：

```bash
for i in {1..30}; do
  SAMBA_HEALTH="$(docker inspect --format '{{.State.Health.Status}}' internal-pages-samba)"
  test "$SAMBA_HEALTH" = "healthy" && break
  sleep 2
done

test "$SAMBA_HEALTH" = "healthy"
docker exec internal-pages-samba pdbedit -L
docker exec internal-pages-samba testparm -s
```

要求：

- Samba 状态为 `healthy`；
- 只出现 `site-a-writer` 和 `site-b-writer` 两个网站用户；
- `site-a` 的 `valid users` 只有 `site-a-writer`；
- `site-b` 的 `valid users` 只有 `site-b-writer`。

在新机本地验证页面：

```bash
curl -fsS -o /dev/null -w 'site-a=%{http_code}\n' http://127.0.0.1:8520/
curl -fsS -o /dev/null -w 'site-b=%{http_code}\n' http://127.0.0.1:8530/
```

两个结果都必须为 `200`。

## 11. 生成新的同事交接包

交接包可以在新机生成，但应由 IT 保管并单独交付：

```text
~/internal-pages-handoff/site-a/.env
~/internal-pages-handoff/site-a/AGENTS.md
~/internal-pages-handoff/site-a/给同事 A的说明.txt

~/internal-pages-handoff/site-b/.env
~/internal-pages-handoff/site-b/AGENTS.md
~/internal-pages-handoff/site-b/给同事 B的说明.txt
```

### 11.1 site-a `.env`

```dotenv
SITE_A_SHARE=\\<NEW_MAC_IP>\site-a
SITE_A_USERNAME=site-a-writer
SITE_A_PASSWORD=<新生成的 site-a 密码>
SITE_A_PREVIEW_URL=http://<NEW_MAC_IP>:8520/
```

### 11.2 site-b `.env`

```dotenv
SITE_B_SHARE=\\<NEW_MAC_IP>\site-b
SITE_B_USERNAME=site-b-writer
SITE_B_PASSWORD=<新生成的 site-b 密码>
SITE_B_PREVIEW_URL=http://<NEW_MAC_IP>:8530/
```

`.env` 必须设置为 `0600`。交付前必须确认：

- 不包含 `<NEW_MAC_IP>` 或其他占位符；
- 两个密码不同；
- 每个交接包只包含自己的账号和密码；
- 没有 Makers Token、私钥、服务器 `.env` 或 `users.conf`；
- `.env` 不进入 Git、文档、聊天或网站发布目录。

### 11.3 `AGENTS.md` 必须包含的规则

分别以 `SITE_A_*` 或 `SITE_B_*` 为变量前缀生成站点规则，至少包含：

1. 用户说“更新内网页面”时执行发布；
2. 只能部署到 `.env` 指定的共享和预览地址；
3. 脱敏读取 `.env`，不得输出密码；
4. 确认 `.env` 已被 `.gitignore` 忽略；
5. 构建并选择明确的 `dist`、`build` 或 `out` 产物，再复制到独立的系统临时发布目录，不改写源文件或原产物；
6. 确认临时发布目录存在 `index.html`；
7. 禁止上传 `.env`、`.git`、`.internal`、`AGENTS.md`、私钥、日志、`node_modules`、符号链接、junction 和其他 reparse point；
8. 生成 UTC 部署时间和唯一部署 ID，并将临时发布目录中所有文件的 `LastWriteTimeUtc` 更新为本次部署时间；
9. 使用 Windows 自带 SMB、PowerShell 和 `robocopy /MIR`；
10. `robocopy` 退出码 `0`–`7` 视为成功，`8` 及以上视为失败；
11. 主同步完成后，最后写入仅含 `deploymentId` 和 `deployedAt` 的 `.internal/deployment.json`；
12. 同步后断开临时网络连接，删除本地临时文件；
13. 回读 `.internal/deployment.json`，验证 HTTP 200 且其 `deploymentId` 与本次一致；
14. 验证带 `?v=<deploymentId>` 的本次预览地址返回 HTTP 200、`Cache-Control` 包含 `no-cache`，且主要资源没有 404；
15. 成功时同时返回版本化预览地址和固定地址；
16. 失败时停止并联系管理员，不得切换服务器、账号、公网或上传工具。

可以参考 [Codex 同事工作流（SMB）](./coworker-publishing.md) 生成最终文件，但不得把带占位符的模板直接交给同事。

## 12. 内网验收矩阵

使用另一台组织内网设备验证。旁路部署阶段的 `<ACTIVE_TEST_IP>` 是新机临时 IP；正式切换后，必须再用新机最终 IP 完整执行一次。

| 验证项 | 必须结果 |
|---|---|
| 同事 A 账号登录 site-a | 成功 |
| 同事 A 账号访问 site-b | 拒绝 |
| 同事 B 账号登录 site-b | 成功 |
| 同事 B 账号访问 site-a | 拒绝 |
| 错误密码 | 拒绝 |
| 访客访问 | 拒绝 |
| 创建、上传、读取、重命名、删除 | 成功 |
| `http://<ACTIVE_TEST_IP>:8520/` | HTTP 200 |
| `http://<ACTIVE_TEST_IP>:8530/` | HTTP 200 |
| 两站点普通响应头 | `Cache-Control: private, no-cache`，且存在 `ETag` 和 `Last-Modified` |
| 携带当前 `ETag` 的条件请求 | HTTP 304 |
| `http://<ACTIVE_TEST_IP>:<SITE_PORT>/?v=<deploymentId>` | HTTP 200 |
| `.internal/deployment.json` | HTTP 200，且 `deploymentId` 与本次一致 |
| Nginx 网站卷 | 只读 |
| 重启 Docker 后 | 自动恢复 |
| 重启新 Mac 后 | 自动恢复 |

Windows 可能拒绝同时使用两个账号连接同一服务器，并显示系统错误 `1219`。切换账号测试前，应先断开该服务器的现有 SMB 连接并清除旧凭据；不要因此修改服务器账号或开放公共共享。

## 13. 让同事重新发布

必须先确认新机已经使用最终 IP。若最终接管 `<OLD_MAC_IP>`，应先完成第 14.2 节的正式 IP 切换，再执行本节；不得让同事把最终 `.env` 发布到仍由旧机占用的地址。

IT 分别向 同事 A、同事 B 发送对应交接包。同事只需：

1. 在自己的项目根目录删除旧 `.env` 和旧 `AGENTS.md`；
2. 放入 IT 提供的新 `.env` 和新 `AGENTS.md`；
3. 确认 `.env` 已在 `.gitignore` 中；
4. 在项目 Codex 中说：

```text
更新内网页面
```

5. 打开 Codex 返回的带本次部署 ID 的新内网地址确认页面；固定地址可继续收藏。

项目绝对路径不需要提供给 IT。Codex 应从当前项目目录开始工作。

同事发布完成后，IT 再检查：

- 占位页面已经被真实网站替换；
- 首页和主要静态资源正常；
- 网站没有引用公网私有资源或泄露 `.env`；
- site-a 与 site-b 仍保持交叉访问拒绝。

## 14. 正式 IP 切换

### 14.1 新机使用新 IP

如果新机长期使用新的固定 IP，只需确保交接 `.env` 使用该地址。旧机可以保持原 IP，直到两个网站验收完成。

### 14.2 新机接管 `<OLD_MAC_IP>`

此路径不是当前推荐方案。只有旧机上的静态页面和其他全部服务都已完成迁移或确认下线，才允许新机接管旧地址。如果旧机仍需提供任何其他服务，应停止本节并让新机使用独立固定 IP。

确认满足前提后：

1. 先在临时 IP 上完成本手册全部验收；
2. 通知 同事 A、同事 B 暂停发布；
3. 在旧机执行 `cd <OLD_MAC_HOME>/internal-pages-poc && docker compose down`；
4. 让旧机改用其他 IP、断开网络或关机；
5. 更新 DHCP 保留或新机网络配置；
6. 确认只有新机使用 `<OLD_MAC_IP>`；
7. 必要时清理客户端或网关 ARP 缓存；
8. 重新验证 SMB、HTTP、重启恢复；
9. 再让 同事 A、同事 B 使用新密码各发布一次。

即使最终 IP 没变，同事仍必须替换 `.env`，因为 SMB 密码已经轮换。

## 15. 回退与旧机下线

在以下条件全部满足前，不删除旧机配置、容器和网站卷：

- 新机通过完整验收矩阵；
- 同事 A 已从真实 Windows 项目发布成功；
- 同事 B 已从真实 Windows 项目发布成功；
- 新机重启并由 IT 登录后，Docker Desktop 和服务自动恢复；
- 新机已经产生第一份配置与网站卷备份；
- IT 记录了最终 IP、账号、共享、端口、卷和负责人。

建议旧机保留 7–14 天回退窗口，但旧机不得继续占用正式 IP，也不得继续接受同事发布。

## 16. 给新机 Codex 的执行提示词

把本文交给新机上的 Codex，并发送：

```text
请严格按照《新 Mac mini 全新部署与同事重新发布手册》部署内网静态页面服务。

要求：
1. 先只读检查主机身份、Docker、端口和现有卷；
2. 在我确认新机临时 IP、最终 IP 和是否复用 <OLD_MAC_IP> 前，不创建服务；
3. 不迁移旧网站卷，创建全新的 site-a、site-b 数据卷；
4. 保持现有网站 ID、账号、共享、端口、镜像版本和容器拓扑；
5. 为两个网站重新生成不同的随机密码，不得显示密码；
6. 生成各自独立的 .env、AGENTS.md 和说明文件；
7. 完成正确访问、交叉拒绝、错误密码、访客、CRUD、HTTP 和重启验证；
8. 不修改或下线旧机，正式 IP 切换前单独向我确认；
9. 任一步骤失败立即停止，返回脱敏错误并提醒联系管理员；
10. 完成后返回新机服务状态、交接包路径和同事重新发布说明。
```

该提示词授权部署新机服务，但不授权删除旧机、公开密码、开放公网端口或提前切换正式 IP。

## 17. 完成标准

只有以下结果同时成立，才能宣布迁移完成：

```text
新机服务健康
+ 两个账号彼此隔离
+ 两个网页 HTTP 200
+ Docker 和 Mac 重启后恢复
+ 同事 A 从真实项目重新发布成功
+ 同事 B 从真实项目重新发布成功
+ 新机备份完成
+ 旧机进入只读回退状态
```

否则只能描述为“新机服务已部署，迁移尚未完成”。
