# Codex 同事工作流（SMB）

## 用户可见操作

同事 A 在本地完成静态网页后，只需对当前项目的 Codex 说：

```text
更新内网页面
```

项目所在的 Windows 绝对路径不属于部署配置，项目移动后仍可使用。

## 项目根目录文件

IT 只需向 同事 A 交付：

```text
.env
AGENTS.md
```

`.env` 包含：

```dotenv
SITE_A_SHARE=\\<SERVER_IP>\site-a
SITE_A_USERNAME=site-a-writer
SITE_A_PASSWORD=<由 IT 生成的随机密码>
SITE_A_PREVIEW_URL=http://<SERVER_IP>:8520/
```

`.env` 必须加入 `.gitignore`，不得被输出、上传、暂存或提交。

site-b 使用同样的文件结构，但变量前缀为 `SITE_B_`，共享为 `site-b`，预览端口为 `8530`。两个交接包不得混用。

## Codex 内部流程

1. 脱敏读取 `.env`；
2. 运行项目现有构建命令，或为纯 HTML 项目组织静态发布目录；
3. 将产物复制到系统临时目录下的独立发布目录，不改写源文件或原构建产物；
4. 确认临时发布目录存在 `index.html`，且不包含 `.env`、`.git`、`.internal`、`AGENTS.md`、`node_modules`、私钥、日志、符号链接、junction 或其他 reparse point；
5. 生成 UTC 部署时间和唯一部署 ID，格式为 `yyyyMMddTHHmmssfffZ`；
6. 将临时发布目录中所有文件的 `LastWriteTimeUtc` 统一设为本次部署时间；
7. 在发布目录之外生成仅含 `deploymentId` 和 `deployedAt` 的 `deployment.json`；
8. 用 Windows 系统功能建立到对应共享的临时 SMB 连接；
9. 用 `robocopy /MIR` 镜像同步已验证的临时发布目录；
10. 主同步成功后，在共享根目录创建保留目录 `.internal`，最后写入 `.internal/deployment.json`；
11. 断开临时 SMB 连接并删除本机临时文件；
12. 从 `<PREVIEW_URL>` 解析出协议、主机和端口，请求该站点的 `/.internal/deployment.json?v=<deploymentId>`，验证 HTTP 200 且返回的 `deploymentId` 与本次一致；
13. 请求 `<PREVIEW_URL>?v=<deploymentId>`，验证 HTTP 200、`Cache-Control` 包含 `no-cache`，且主要资源没有 404；
14. 返回本次版本化预览地址和固定内网地址。

`robocopy` 退出码 `0`–`7` 视为成功，`8` 及以上视为失败。镜像同步前必须先确认临时发布目录，不得直接把不确定的项目根目录作为镜像源。`.internal` 只由发布流程管理；如果完成标记上传或回读失败，应报告部署不完整并联系管理员。

## 结果回复

成功：

```text
内网页面更新成功：
http://<SERVER_IP>:8520/?v=<本次部署ID>

固定地址：
http://<SERVER_IP>:8520/
```

失败：

```text
内网页面更新失败，请联系管理员。

失败阶段：本地检查 / SMB 连接 / 文件同步 / 页面验证
错误摘要：<脱敏后的错误>
```

失败后不得修改服务器、账号、密码、共享地址或网页端口，不得改用公网服务。
