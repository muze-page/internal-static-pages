# Internal Static Pages

> **Public Preview / 公开参考预览**
> 当前仓库记录了一个真实 Windows + Codex 发布路径的结果级验证，但双站点、重启和隔离恢复闭环仍待完成。请勿将其描述为生产就绪产品。
> 当前阶段已停止主动功能开发；后续只在具备真实设备、维护窗口和可脱敏证据时恢复实践验收。

面向组织内网静态网站的轻量发布与运维参考项目。IT 使用 Docker Samba 管理每个网站的独立写入权限，Nginx 只读提供内网页面；非技术同事只需在自己的 Windows 项目中对 Codex 说“更新内网页面”。

**English summary:** A public-preview reference for small intranet static sites. Windows coworkers can publish without Git or SSH; Codex follows a fixed build, SMB sync, and verification workflow while Nginx serves each site from a read-only mount.

本仓库只保存文档、脱敏配置模板和检查脚本。它不是网站内容仓库，也不使用 GitHub Pages 发布网页。

## 当前边界

- 适合少量静态网站，当前模型是一人维护一个网站；
- 同事端使用 Windows 自带 SMB、PowerShell 和 `robocopy`；
- 每个网站拥有独立共享、账号、密码、Docker 卷和 HTTP 端口；
- 一个 Samba 容器统一监听 `445`，每个网站使用独立只读 Nginx；
- 实际网页只在组织内网访问；
- 本仓库可以公开，但部署目标、网页内容与真实环境信息不得公开；
- 不提交密码、真实 `.env`、`users.conf`、私钥、网站数据或备份。

## 仓库结构

```text
docs/decisions/   架构决策记录
docs/operations/  当前同事发布与新机部署手册
docs/evidence/    已脱敏的现场验证记录
docs/history/     已停用的 SFTPGo 历史方案
docs/retrospective.md  完整演进与经验复盘
deploy/           可执行的 Compose、Samba 和 Nginx 配置
templates/        同事项目交接模板
scripts/          本地与 CI 质量检查
```

## 开始使用

1. 阅读[完整复盘](./docs/retrospective.md)，确认当前方案适合实际规模；
2. 按[新 Mac mini 部署手册](./docs/operations/new-mac-mini.md)准备新机；
3. 使用 [`deploy/`](./deploy/README.md) 中的受管配置部署服务；
4. 使用 [`templates/`](./templates/README.md) 为每个同事生成独立交接文件；
5. 使用[试运行验收清单](./docs/operations/pilot-checklist.md)完成旁路部署、Windows 权限、重启和恢复演练；
6. 按[同事发布流程](./docs/operations/coworker-publishing.md)完成真实 Windows Codex 盲操作；
7. 提交前执行：

```bash
./scripts/check.sh
```

## 文档入口

### 当前决策

- [ADR-002：Docker Samba + Nginx](./docs/decisions/ADR-002-samba-nginx-first-site.md)
- [ADR-003：单 Samba 容器承载多个隔离站点](./docs/decisions/ADR-003-single-samba-multi-site.md)
- [ADR-004：协商缓存与部署版本标识](./docs/decisions/ADR-004-cooperative-cache.md)

### 运维与验证

- [新 Mac mini 全新部署手册](./docs/operations/new-mac-mini.md)
- [新 Mac mini 试运行验收清单](./docs/operations/pilot-checklist.md)
- [Codex 同事发布流程](./docs/operations/coworker-publishing.md)
- [2026-07-17 阶段收口记录](./docs/evidence/phase-closeout-2026-07-17.md)
- [site-a 验证记录](./docs/evidence/site-a.md)
- [site-b 验证记录](./docs/evidence/site-b.md)

### 历史与复盘

- [完整复盘](./docs/retrospective.md)
- [ADR-001：历史 SFTPGo 方案](./docs/decisions/ADR-001-sftpgo-nginx.md)
- [历史 SFTPGo PoC 运维手册](./docs/history/sftpgo-poc-operations.md)
- [历史 SFTPGo Codex 工作流](./docs/history/sftpgo-codex-workflow.md)

## 当前完成状态

参考方案已完成 Samba 多站点隔离、CRUD、Nginx 只读挂载和协商缓存验证。部署版本标识与 `.internal/deployment.json` 完成标记已进入交接规则；脱敏现场证据还记录了 site-a 一次真实 Windows Codex 盲操作的结果级通过确认。

site-b 盲操作、目标环境受保护备份、隔离恢复和整机重启仍待验证。仓库中的单站点结论不代表任何具体组织已经完成正式部署。

## 需求反馈

如果你的团队也需要“非技术同事通过 Codex 更新内网静态页面”，欢迎提交一条[使用场景反馈](https://github.com/muze-page/internal-static-pages/issues/new?template=use-case.yml)。请只描述匿名场景，不要附加真实 IP、域名、人员、凭据、日志或网站内容。

该入口仅用于了解匿名使用场景，不代表项目恢复主动开发，也不承诺生产部署支持。

## 运维命令

```bash
# 只读检查当前服务
./scripts/acceptance-check.sh

# 创建包含运行配置和两个网站卷的受保护备份
./scripts/backup.sh <BACKUP_ROOT>

# 默认只验证备份，不修改系统
./scripts/restore.sh <BACKUP_DIR>
```

真实恢复需要额外提供 `--apply RESTORE`，并应先在隔离环境演练。详细边界见[试运行验收清单](./docs/operations/pilot-checklist.md)。

## 许可证

本仓库自行编写的文档、配置和脚本采用 [Apache License 2.0](./LICENSE) 授权。仓库引用的 Docker 镜像和其他第三方组件仍分别遵循其自身许可证。
