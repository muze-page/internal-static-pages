# site-a SMB 部署验证记录

## 日期与范围

<VALIDATION_DATE>，目标为临时 M4 验证机 `<OLD_MAC_IP>`。

## 当前运行状态

```text
SMB 共享：\\<OLD_MAC_IP>\site-a
SMB 账号：site-a-writer
SMB 端口：445
网页地址：http://<OLD_MAC_IP>:8520/
Samba 容器：internal-pages-samba
Nginx 容器：internal-pages-site-a-web
网站数据卷：internal-pages-site-a-data
```

Samba 镜像为 `dockurr/samba:4.23.8`，目标机拉取的架构为 `arm64`。Nginx 使用 `nginx:1.29.8-alpine`，以只读方式挂载网站卷。

截至 <VALIDATION_DATE> 复核时，Samba 已收敛为统一容器，并同时挂载 `internal-pages-site-a-data` 与 `internal-pages-site-b-data`。两个共享使用独立账号和 `valid users` 规则隔离；统一容器不代表两个账号可以互访网站数据。

## 备份与回滚资产

切换前完整备份：

```text
<OLD_MAC_HOME>/internal-pages-poc/backups/<BACKUP_TIMESTAMP>/
```

保留的旧 SFTPGo 卷：

```text
internal-pages-sftpgo-data-poc
internal-pages-sftpgo-state-poc
```

原 SFTPGo 容器已删除，但上述卷未删除。旧端口 `2022`、`18080` 和 `8510` 均不再监听。

## 交接资产

IT 本机上当前保留的 同事 A 交接包为：

```text
<OLD_MAC_HOME>/site-a-handoff/.env
<OLD_MAC_HOME>/site-a-handoff/AGENTS.md
<OLD_MAC_HOME>/site-a-handoff/给同事 A的说明.txt
```

`.env` 权限为 `0600`，包含随机 SMB 密码，不得进入 Git、文档仓库或聊天记录。服务器上的配置源文件仍保留在 `<OLD_MAC_HOME>/internal-pages-poc/site-a-windows.env`。

## 已完成验证

| 验证项 | 结果 |
|---|---|
| Samba 容器健康检查 | `healthy` |
| 正确账号密码登录 | 成功 |
| 错误密码 | 拒绝 |
| 访客登录 | 拒绝 |
| 创建目录 | 成功 |
| 上传文件 | 成功 |
| 重命名文件 | 成功 |
| 读取文件 | 成功 |
| 删除文件和目录 | 成功 |
| 外部 macOS SMB 客户端挂载 | 成功 |
| Samba/Nginx 重启后持久化 | 成功 |
| `8520` 页面状态 | `HTTP 200` |
| `8510/2022/18080` | 已停止监听 |
| 既有 `8260` 服务 | 仍为 `HTTP 200` |
| 既有 `8261` 服务 | 仍保持原有 `HTTP 404` |

## <VALIDATION_DATE> 协商缓存修正

Nginx 已增加 `Cache-Control: private, no-cache`，并保留 `ETag` 和 `Last-Modified`。现场回归结果：

| 验证项 | 结果 |
|---|---|
| Nginx 配置检查 | 通过 |
| 普通请求 | `HTTP 200` |
| 携带当前 `ETag` | `HTTP 304` |
| 携带过期 `ETag` | `HTTP 200` |
| `/?v=<deploymentId>` | `HTTP 200` |

本次修改前的 Nginx 配置保存在：

```text
<OLD_MAC_HOME>/internal-pages-poc/backups/<BACKUP_TIMESTAMP>-cache-policy/
```

详细决策和边界见 [ADR-004：静态页面协商缓存与部署版本标识](../decisions/ADR-004-cooperative-cache.md)。

## 2026-07-17 真实 Windows Codex 盲操作

使用者确认：site-a 已在真实 Windows 项目中由同事只说“更新内网页面”，Codex 盲操作结果通过。

本记录没有保存真实人员、项目、地址、网页内容或原始日志，也没有独立核对本次 `robocopy` 退出码、完成标记内容和浏览器网络请求。因此该结论证明结果级用户路径已经走通，但不能替代试运行清单中每个子项的独立证据。

当前仍待验收：site-b 真实 Windows Codex 盲操作、目标环境受保护备份、隔离恢复演练，以及 Docker Desktop 和 Mac mini 重启恢复。阶段边界见 [2026-07-17 阶段收口记录](./phase-closeout-2026-07-17.md)。
