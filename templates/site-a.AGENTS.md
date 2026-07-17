# site-a 内网发布规则

## 用户口令

当用户说“更新内网页面”、“更新页面”或意思相同的话时，按本文执行。

## 固定边界

- 只能部署到 `.env` 中指定的 site-a 共享目录。
- 不得更换主机、共享目录、用户名或预览地址。
- 不得把密码、`.env` 内容或包含密码的命令输出到回复、日志或其他文件。
- 不得上传 `.env`、`.git`、`AGENTS.md`、`node_modules`、日志、私钥或其他敏感文件。
- `.internal` 是部署流程保留目录；项目源文件和构建产物不得自行占用该目录。
- 不得安装第三方上传工具；使用 Windows 自带的 SMB、PowerShell 和 `robocopy`。

## 部署流程

1. 从当前项目根目录读取 `.env`，但不显示其中的密码。
2. 确认 `.env` 包含 `SITE_A_SHARE`、`SITE_A_USERNAME`、`SITE_A_PASSWORD` 和 `SITE_A_PREVIEW_URL`。
3. 如果当前项目使用 Git，先确认 `.env` 已被 `.gitignore` 忽略；如未忽略，将 `.env` 加入 `.gitignore`，且绝不得暂存或提交 `.env`。
4. 确定静态产物来源：
   - 如果项目有现成构建命令，先构建并使用其 `dist`、`build` 或 `out` 目录。
   - 如果是纯 HTML 项目，只收集页面运行所需的 HTML、CSS、JavaScript、图片、字体等静态文件。
5. 把静态产物复制到系统临时目录下的独立发布目录；不得直接修改项目源文件或原构建产物。
6. 确认临时发布目录存在 `index.html`，且不包含 `.env`、`.git`、`.internal`、`AGENTS.md`、私钥、日志、符号链接、junction 或其他 reparse point。
7. 生成 UTC 部署时间和唯一部署 ID，格式使用 `yyyyMMddTHHmmssfffZ`。把临时发布目录中所有文件的 `LastWriteTimeUtc` 统一更新为本次部署时间，确保服务器的 `Last-Modified` 和 `ETag` 随部署变化。
8. 在临时发布目录之外生成 `deployment.json`，只包含 `deploymentId` 和 `deployedAt`，不得包含项目路径、账号或密码。
9. 使用 `.env` 中的账号密码建立到 `SITE_A_SHARE` 的临时 Windows 网络连接。不永久保存网络映射。
10. 使用 `robocopy` 镜像同步临时发布目录到共享目录，最多重试 2 次，每次等待 2 秒。
11. `robocopy` 退出码 `0`–`7` 视为成功，`8` 及以上视为失败。
12. 主同步成功后，在共享根目录创建保留目录 `.internal`，最后上传 `deployment.json` 到 `.internal/deployment.json`。只有完成这一步才视为本次部署完整。
13. 同步完成后断开临时网络连接，并删除本机临时发布目录和临时部署标识文件。
14. 使用部署 ID 构造版本化预览地址：`SITE_A_PREVIEW_URL?v=<deploymentId>`。如果原地址已有查询参数，则使用 `&v=`。
15. 从 `SITE_A_PREVIEW_URL` 解析出协议、主机和端口，请求该站点的 `/.internal/deployment.json?v=<deploymentId>`，确认 HTTP 200 且返回的 `deploymentId` 与本次一致。
16. 请求版本化预览地址，确认首页返回 HTTP 200、`Cache-Control` 包含 `no-cache`，且主要 CSS、JavaScript 和图片资源没有 404。

## 结果回复

成功时只需说：

```text
内网页面更新成功：
http://<SERVER_IP>:8520/?v=<本次部署ID>

固定地址：
http://<SERVER_IP>:8520/
```

失败时停止操作，返回脱敏的失败阶段和错误摘要，并提醒联系管理员。不得改用其他服务器、账号、公网服务或上传方式。
