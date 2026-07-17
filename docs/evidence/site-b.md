# site-b SMB 部署验证记录

## 日期与范围

<VALIDATION_DATE>，目标为临时 M4 验证机 `<OLD_MAC_IP>`。

## 当前运行状态

```text
SMB 共享：\\<OLD_MAC_IP>\site-b
SMB 账号：site-b-writer
SMB 端口：445
网页地址：http://<OLD_MAC_IP>:8530/
Samba 容器：internal-pages-samba
Nginx 容器：internal-pages-site-b-web
网站数据卷：internal-pages-site-b-data
```

## 交接资产

IT 本机上已生成 同事 B 交接包：

```text
<OLD_MAC_HOME>/site-b-handoff/.env
<OLD_MAC_HOME>/site-b-handoff/AGENTS.md
<OLD_MAC_HOME>/site-b-handoff/给同事 B的说明.txt
```

`.env` 权限为 `0600`，包含 site-b 独立随机密码，不得进入 Git、文档仓库或聊天记录。

## 已完成验证

| 验证项 | 结果 |
|---|---|
| `site-b-writer` 登录 site-b | 成功 |
| `site-b-writer` 访问 site-a | 拒绝 |
| `site-a-writer` 访问 site-b | 拒绝 |
| 错误密码 | 拒绝 |
| 访客登录 | 拒绝 |
| 创建目录 | 成功 |
| 上传、读取、重命名、删除 | 成功 |
| 外部 macOS SMB 客户端挂载 | 成功 |
| Samba/Nginx 重启后持久化 | 成功 |
| `8530` 页面状态 | `HTTP 200` |
| site-a `8520` 回归验证 | `HTTP 200` |
| 既有 `8260` 服务 | `HTTP 200` |
| 既有 `8261` 服务 | 保持原有 `HTTP 404` |

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

## 备份

新增 site-b 前的 site-a 配置与网站数据备份：

```text
<OLD_MAC_HOME>/internal-pages-poc/backups/<BACKUP_TIMESTAMP>-site-b-before/
```

## 尚待验收

服务端、账号隔离和外部 SMB 客户端均已验证。剩余唯一必要验收是：把交接包放到 同事 B 的真实 Windows 项目根目录，由其 Codex 执行一次“更新内网页面”。
