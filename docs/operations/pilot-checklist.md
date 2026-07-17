# 新 Mac mini 试运行验收清单

本清单用于把“配置能够启动”推进到“真实同事能够发布、服务能够恢复”。完整部署命令仍以[新 Mac mini 部署手册](./new-mac-mini.md)为准。

公开仓库只能记录匿名结论。真实 IP、主机名、人员、密码、备份路径和网站内容不得写入本文件或 GitHub Issue。

## 一、P0 安全前置

- [ ] 历史 Makers API Token 已撤销或轮换；
- [ ] 旧公网发布入口已经下线或确认无效；
- [ ] 新机使用新的固定内网 IP 或 DHCP 保留；
- [ ] 防火墙只允许批准的内网网段访问 `445`、`8520` 和 `8530`；
- [ ] site-a 与 site-b 使用不同的新随机密码；
- [ ] `.env` 与 `deploy/samba/users.conf` 权限为 `0600`，且未进入 Git。

P0 未全部完成时不得开始同事交付。

## 二、旁路部署

- [ ] 旧机仍保持可用，新机没有接管旧机 IP；
- [ ] 两个网站使用全新 Docker 命名卷；
- [ ] `docker compose config --quiet` 通过；
- [ ] Samba、site-a Nginx、site-b Nginx 均在运行；
- [ ] 两个占位首页均返回 HTTP 200；
- [ ] 普通响应包含 `Cache-Control: private, no-cache`；
- [ ] Nginx 对网站卷保持只读挂载。

在目标 Mac mini 的仓库根目录执行只读检查：

```bash
./scripts/acceptance-check.sh
```

## 三、Windows 权限矩阵

必须从另一台组织内 Windows 设备完成，不能用服务端本机检查代替。

| 检查项 | 必须结果 | 完成 |
|---|---|---|
| site-a 账号登录 site-a | 成功 | [ ] |
| site-a 账号访问 site-b | 拒绝 | [ ] |
| site-b 账号登录 site-b | 成功 | [ ] |
| site-b 账号访问 site-a | 拒绝 | [ ] |
| 错误密码 | 拒绝 | [ ] |
| 访客访问 | 拒绝 | [ ] |
| 创建、上传、读取、重命名、删除 | 成功 | [ ] |

Windows 出现系统错误 `1219` 时，先断开到该服务器的现有 SMB 连接并清除旧凭据，再测试另一个账号。不得因此开放公共共享。

## 四、真实 Codex 盲操作

分别为 site-a 和 site-b 项目放入对应的 `.env` 与 `AGENTS.md`。同事只说：

```text
更新内网页面
```

每个网站分别确认：

- [ ] 同事没有安装额外上传工具，也没有手工执行服务器命令；
- [ ] Codex 自动选择正确静态产物目录；
- [ ] 发布内容不包含 `.env`、`.git`、`AGENTS.md`、源码缓存、日志或私钥；
- [ ] `robocopy` 退出码在 `0`–`7`；
- [ ] `.internal/deployment.json` 最后写入且可以回读；
- [ ] Codex 返回版本化预览地址和固定地址；
- [ ] 首页、CSS、JavaScript 与图片均无 404；
- [ ] 失败时停止并提示联系管理员，没有切换到公网或其他服务器。

两位同事发布完成后执行：

```bash
./scripts/acceptance-check.sh --require-deployment-marker
```

## 五、重启恢复

- [ ] 单独重启 Samba 容器后，账号与数据正常；
- [ ] 单独重启两个 Nginx 容器后，页面正常；
- [ ] 重启 Docker Desktop 后，三个容器和两个网站自动恢复；
- [ ] 重启 Mac mini 并由 IT 管理员登录后，Docker Desktop 和服务恢复；
- [ ] 运维记录明确注明：未登录 macOS 时不能宣称无人值守恢复。

## 六、备份与恢复演练

备份根目录必须在 Git 仓库之外，并通过受保护的内部存储保存：

```bash
./scripts/backup.sh <BACKUP_ROOT>
```

- [ ] 备份生成 `runtime-config.tar.gz`、两个网站卷归档和 `SHA256SUMS`；
- [ ] 备份期间只有 Samba 写入暂停，Nginx 页面仍可读取；
- [ ] 备份目录权限为 `0700`，文件权限为 `0600`；
- [ ] 备份没有上传到 GitHub、聊天、工单或公开存储。

先只验证备份，不修改系统：

```bash
./scripts/restore.sh <BACKUP_DIR>
```

真实恢复必须先在备用主机或隔离环境演练。确认当前环境另有安全备份后，才执行：

```bash
./scripts/restore.sh <BACKUP_DIR> --apply RESTORE
```

- [ ] 校验和验证通过；
- [ ] 配置、密码文件和两个网站卷恢复成功；
- [ ] 恢复后的基础自动验收通过；
- [ ] Windows 权限矩阵与真实 Codex 发布再次通过。

恢复不是原子操作。中途失败时服务可能保持停止状态，必须联系管理员处理，不能直接切换流量。

## 七、阶段签字

### v0.1.0 候选

- [ ] 新 Mac mini 旁路部署完成；
- [ ] 至少一个真实 Windows 项目完成 Codex 盲操作；
- [ ] 基础重启和备份完成。

### v1.0.0 候选

- [ ] 两个真实 Windows 项目均完成 Codex 盲操作；
- [ ] 全部账号隔离检查通过；
- [ ] Docker 与 Mac 重启恢复通过；
- [ ] 备用环境恢复演练通过；
- [ ] 历史 Token 下线完成；
- [ ] 公开证据再次完成脱敏和秘密扫描。

任何一项没有证据时，只能标记“待验收”，不得根据脚本存在或文档完成推断真实部署成功。
