# ADR-002：采用 Docker Samba + Nginx 管理 site-a

## 状态

已由 [ADR-003：一个 Samba 容器承载多个隔离站点](./ADR-003-single-samba-multi-site.md) 取代。本文保留 site-a 首个 SMB 站点的选型背景。

## 日期

<VALIDATION_DATE>

## 背景

同事 A 使用 Windows 电脑，主要通过 Codex 开发静态网页。当前是一人维护一个网站，用户只应说“更新内网页面”，不应安装或理解 SFTP、SSH 密钥和服务器工具。

SFTPGo PoC 已证明权限隔离可行，但 Windows 自带 `sftp.exe` 不适合从项目 `.env` 非交互传入密码。额外安装 WinSCP 与“同事操作越少越好”的目标不一致。

macOS 原生 SMB 可以完成相同工作，但创建仅共享账号与启用系统级 SMB 需要交互式管理员授权。目标机还存在一个允许访客访问的历史公共文件夹配置，启用全局文件共享会扩大暴露面。

## 决策

- 使用 `dockurr/samba:4.23.8` ARM64 容器提供 SMB3 共享；
- 共享地址固定为 `\\<OLD_MAC_IP>\site-a`；
- 共享账号固定为 `site-a-writer`，使用独立随机密码；
- Samba 统一容器挂载受管网站的独立 Docker 卷；当前包括 `internal-pages-site-a-data` 和 `internal-pages-site-b-data`；
- 每个共享目录使用独立账号和 Samba `valid users` 规则隔离，`site-a-writer` 只能访问 `site-a`；
- Nginx 以只读方式挂载同一卷，对内网提供 `http://<OLD_MAC_IP>:8520/`；
- Windows 侧只使用系统自带 SMB、PowerShell 和 `robocopy`；
- 项目根目录放置 `.env` 和 `AGENTS.md`，密码只存在 `.env`；
- 访客访问和错误密码必须被拒绝；
- 旧 SFTPGo 容器停用，原数据卷和完整备份保留用于回滚。

## 关键实现细节

首次实现曾把 Samba 直接绑定到 macOS 宿主机目录。该方式能上传和重命名，但 SMB 删除返回 `NT_STATUS_NOT_SUPPORTED`。根因是 Docker Desktop 的 macOS 绑定文件系统没有完整提供 Samba 所需的删除语义。

最终改为独立 Docker 卷，Samba 读写、Nginx 只读。该结构已通过创建目录、上传、重命名、读取、删除和容器重启后持久化验证。

## 后果

### 正面后果

- 同事 A 无需安装 WinSCP 或管理 SSH 密钥；
- Windows 和 Codex 直接使用系统文件共享与 `robocopy`；
- 共享容器只能访问显式挂载的受管网站卷，不能访问其他宿主机文件；
- 没有启用 macOS 全局文件共享，历史公共文件夹不会随之暴露；
- 密码丢失时可通过重建 Samba 容器快速轮换。

### 代价与风险

- 密码明文保存在用户指定的项目 `.env`，必须保证它不进入 Git 和发布目录；
- 使用 `robocopy /MIR` 前必须确认本地发布目录，否则会删除远程多余文件；
- 网站数据存在 Docker 卷，IT 必须维护独立备份；
- 当前还没有整站版本发布、原子切换和自动回滚。

## 重新评估条件

- 一个网站需要多人维护；
- 需要完整审计、版本回滚或审批；
- 需要托管动态后端或数据库；
- 网站数量增长到手工分配账号与端口不可接受。
