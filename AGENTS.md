# Internal Static Pages 仓库规则

## 项目边界

- 本仓库只管理组织内网静态页面服务的公开参考文档、配置模板和检查脚本。
- 实际网站内容、密码、备份和交接成品不属于本仓库。
- GitHub 仓库可以公开，但不得启用 GitHub Pages 或把实际内网页面发布到公网。

## 秘密与隐私

- 禁止提交真实 `.env`、`users.conf`、密码、Token、私钥、证书、网站数据、Docker 卷导出或备份。
- 示例必须使用 `<SERVER_IP>`、`<SITE_ID>`、`<GENERATE_ON_TARGET>`、`site-a`、`site-b` 等明显占位符或匿名标识。
- 不得写入真实内网 IP、主机名、域名、人员标识、个人主目录或交接包绝对路径。
- 如果发现凭据已经进入 Git，立即停止推送，提醒管理员先撤销或轮换凭据。

## 文档权威顺序

1. 目标 Mac mini 的实时运行状态和验收结果；
2. `docs/decisions/` 中已接受的 ADR；
3. `docs/operations/` 当前手册；
4. `docs/evidence/` 脱敏验证记录；
5. `docs/history/` 历史方案。

不得把历史 SFTPGo、EdgeOne Makers 或公网流程描述成当前方案。

## 修改要求

- 修改部署拓扑时同步更新 `deploy/`、相关 ADR、操作手册和根 README。
- 修改同事工作流时同步更新 `templates/` 与 `docs/operations/coworker-publishing.md`。
- 不得在未经用户明确授权时修改在线 Mac mini、创建 GitHub 远端、推送代码或改变仓库可见性。
- 不得删除历史 ADR；新决策应更新其状态或新增 ADR。
- 提交前必须执行 `./scripts/check.sh`，并检查暂存差异没有秘密和环境专属路径。
