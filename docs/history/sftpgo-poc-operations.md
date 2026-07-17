# PoC 验证与运维手册

## 适用范围

本文记录 <VALIDATION_DATE> 在临时 M4 主机上的真实 PoC 状态。它用于复现、检查、停止和迁移测试环境，不代表新 Mac mini 的最终生产配置。

## 主机事实

```text
IP：<OLD_MAC_IP>
主机名：<OLD_MAC_HOSTNAME>
架构：Apple M4 / arm64
操作系统：macOS 26.5.1
Docker Server：29.6.1
```

检查远端状态前必须先确认自己已经进入 M4，不能在 MacBook Air 本地读取 Docker 状态后误认为是目标主机。

```bash
ssh <OLD_MAC_ADMIN_USER>@<OLD_MAC_IP> 'hostname; sw_vers; uname -m'
```

## PoC 目录

目标机配置目录：

```text
<OLD_MAC_HOME>/internal-pages-poc/
```

目录中包含：

```text
compose.yaml
nginx.conf
.env
```

`.env` 权限为 `0600`，包含 PoC 管理凭据，不得复制到仓库或输出到日志。

## 容器和端口

| 服务 | 容器 | 镜像 | 监听 |
|---|---|---|---|
| 上传权限层 | `internal-pages-sftpgo-poc` | `drakkan/sftpgo:v2.7.1-alpine` | `0.0.0.0:2022` |
| 静态页面 | `internal-pages-site-a-web` | `nginx:1.29.8-alpine` | `0.0.0.0:8510` |
| 管理端 | SFTPGo HTTPD | 同上 | `127.0.0.1:18080` |

Docker 网络：

```text
internal-pages-poc
```

Docker 卷：

```text
internal-pages-sftpgo-data-poc
internal-pages-sftpgo-state-poc
```

网页地址：

```text
http://<OLD_MAC_IP>:8510/
```

## SFTPGo 用户

```text
用户名：site-a-writer
状态：启用
密码：未配置
认证：一把临时 PoC SSH 公钥
主目录：/srv/sftpgo/site-a
容量配额：500 MB
文件数配额：10,000
```

权限：

```text
list
download
upload
overwrite
delete
rename
create_dirs
delete_dirs
```

未授予普通 Shell、任意命令、管理端访问或其他网站目录访问。

## Docker Compose 关键边界

- SFTPGo 数据与状态分别使用命名卷；
- Nginx 只读挂载 SFTPGo 数据卷；
- Nginx 根目录为 `/srv/sites/site-a`；
- SFTPGo 使用 `SFTPGO_COMMON__UPLOAD_MODE=1`，单文件先写入临时文件，再原子重命名；
- SFTPGo 管理端不暴露到局域网；
- 当前 `2022/8510` 对内网监听是为了同事访问，不应被误判为 PoC 缺陷；
- 正式新 Mac mini 仍需配合组织 VLAN、防火墙和内部 DNS。

## 已完成的验证

| 验证项 | 结果 |
|---|---|
| SFTPGo 镜像架构 | `linux/arm64` |
| 正确公钥 SFTP 登录 | 成功 |
| 上传 `index.html` | 成功 |
| 上传后目录可见 | 成功 |
| 错误公钥登录 | 拒绝 |
| 普通 SSH 命令 `id` | 拒绝，`exec request failed` |
| 远程访问 `18080` | 不可访问 |
| 页面 HTTP 状态 | `200` |
| 页面 Content-Type | `text/html` |
| 页面内容 | 与上传文件一致 |
| SFTPGo 重启后用户保留 | 成功 |
| SFTPGo 重启后文件保留 | 成功 |
| 重启后错误日志 | 0 个持续性 error/fatal |
| 现有 `8260` 服务 | 仍为 `200` |
| 现有 `8261` 服务 | 仍保持原有 `404` |

PoC 上传使用了本仓库当时的静态开始页作为样本，只用于证明上传与浏览链路，不代表最终组织页面内容。

## 日志判断注意事项

不能简单使用 `grep error` 判断 SFTPGo 是否失败。

PoC 中出现过两类预期错误日志：

1. 第一次启动 SQLite 时，SFTPGo 先检测不存在 `schema_version`，随后正常初始化；
2. 主动测试错误公钥和禁止 Shell 时，服务按设计记录认证/命令错误。

正确判断顺序：

1. 检查容器是否运行；
2. 检查 `/healthz`；
3. 检查管理 API 是否能读取用户；
4. 重启后重新检查用户和文件是否保留；
5. 只分析重启后的新错误；
6. 从另一台组织内网设备请求网页地址。

## 常用运维命令

### 查看状态

```bash
ssh <OLD_MAC_ADMIN_USER>@<OLD_MAC_IP> '
  cd <OLD_MAC_HOME>/internal-pages-poc &&
  docker compose ps
'
```

### 查看日志

```bash
ssh <OLD_MAC_ADMIN_USER>@<OLD_MAC_IP> '
  cd <OLD_MAC_HOME>/internal-pages-poc &&
  docker compose logs --no-color --tail=200
'
```

### 重启 PoC

```bash
ssh <OLD_MAC_ADMIN_USER>@<OLD_MAC_IP> '
  cd <OLD_MAC_HOME>/internal-pages-poc &&
  docker compose restart
'
```

### 验证页面

```bash
curl -fsS -o /dev/null -w '%{http_code}\n' \
  http://<OLD_MAC_IP>:8510/
```

### 停止但保留数据

```bash
ssh <OLD_MAC_ADMIN_USER>@<OLD_MAC_IP> '
  cd <OLD_MAC_HOME>/internal-pages-poc &&
  docker compose down
'
```

### 完全删除 PoC

仅在确认不再需要测试数据后执行：

```bash
ssh <OLD_MAC_ADMIN_USER>@<OLD_MAC_IP> '
  cd <OLD_MAC_HOME>/internal-pages-poc &&
  docker compose down --volumes
'
```

`--volumes` 会删除网站文件和 SFTPGo 数据库，不属于日常停止命令。

## 凭据处理

- 临时私钥只存在测试发起端，不能提交到 Git；
- 正式接入前应为真实同事生成新密钥并替换 PoC 公钥；
- 不向同事提供 SFTPGo 管理员账号；
- 项目配置只保存 SSH Host 别名、网站 ID、本地构建目录和预览地址；
- 主机指纹应由 IT 预先写入同事电脑的 `known_hosts`；
- 同事离职或设备丢失时，撤销该公钥或禁用账号，网站文件保留。

## 迁移到新 Mac mini

建议迁移顺序：

1. 新 Mac mini 安装并确认 Docker 运行；
2. 分配正式内网 IP；
3. 复制 Compose、Nginx 配置和 SFTPGo 卷备份；
4. 在新主机恢复 SFTPGo 状态与网站文件；
5. 生成或恢复固定 SFTPGo Host Key，避免同事收到主机指纹变化告警；
6. 从 IT 设备验证 SFTP 权限、Shell 拒绝和页面 HTTP 状态；
7. 修改内部 DNS 或项目部署配置指向新主机；
8. 完成同事侧真实上传验证；
9. 停止当前 M4 PoC；
10. 保留一段时间备份后再删除旧卷。
