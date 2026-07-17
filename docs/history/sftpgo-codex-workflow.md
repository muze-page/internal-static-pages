# Codex 同事工作流

> 历史文档：本文记录 SFTPGo 方案，已由 [Codex 同事工作流（SMB）](../operations/coworker-publishing.md) 取代。

## 目标用户

当前按“一名同事维护一个静态网站”设计。同事使用 Codex 完成页面开发，对 Docker、SSH、SFTP、Nginx 和服务器运维没有要求。

## 用户可见操作

同事在本地确认网页效果后，只需说：

```text
更新内网页面
```

同事不需要选择：

- 服务器；
- SFTP 账号；
- 远端目录；
- 网站端口；
- Docker 容器；
- Nginx 配置。

以上信息由 IT 在项目中预配置，并由服务端权限再次约束。

## 项目配置契约

建议在每个网站项目中保存一份不含秘密的配置，例如：

```json
{
  "siteId": "site-a",
  "localDirectory": "./dist",
  "sftpHost": "company-site-a",
  "remoteDirectory": "/",
  "previewUrl": "http://<OLD_MAC_IP>:8510/"
}
```

字段含义：

| 字段 | 含义 | 是否允许同事临时修改 |
|---|---|---|
| `siteId` | 网站稳定标识 | 否 |
| `localDirectory` | 已构建静态产物目录 | 仅在项目构建结构变化时由 IT/开发确认 |
| `sftpHost` | IT 配置的 SSH Host 别名 | 否 |
| `remoteDirectory` | SFTPGo 用户虚拟根目录 | 否 |
| `previewUrl` | 固定内网验收地址 | 否 |

配置中不得出现：

- SSH 私钥内容；
- 密码；
- SFTPGo 管理 Token；
- 管理员账号；
- Makers API Token；
- 任意可切换目标服务器的通用参数。

## SSH 客户端配置

私钥由 IT 写入同事电脑，不进入项目。例如：

```sshconfig
Host company-site-a
    HostName <OLD_MAC_IP>
    Port 2022
    User site-a-writer
    IdentityFile ~/.ssh/company-site-a
    IdentitiesOnly yes
```

IT 同时预置 SFTPGo 主机指纹。Codex 不得在未知指纹变化时使用 `StrictHostKeyChecking=no` 绕过验证。

## Codex 执行流程

### 1. 读取当前项目

- 确认当前工作目录；
- 读取网站配置；
- 确认 `siteId`、SFTP Host 别名和预览地址存在；
- 不允许从聊天临时指定其他主机或远端目录。

### 2. 找到静态产物

- 如果项目需要构建，先运行已有构建命令；
- 部署 `dist`、`build` 或项目明确指定的输出目录；
- 纯 HTML 项目可以部署包含 `index.html` 的目录；
- 禁止上传整个用户目录或不确定的父目录。

### 3. 本地检查

至少检查：

- 存在 `index.html`；
- HTML 可以解析；
- 本地 HTTP 访问成功；
- CSS、JavaScript 和图片路径正确；
- 不包含 `.env`、`.git`、私钥、日志和无关源码；
- 页面不引用组织禁止的公网脚本、字体、图片或分析服务。

### 4. 上传

使用固定部署脚本同步到 SFTPGo 虚拟根目录。部署脚本应：

- 只读取项目配置；
- 不接受任意主机、账号或远端绝对路径；
- 使用 IT 预置 SSH Key；
- 上传新增和修改文件；
- 删除远端已经不存在的旧静态资源；
- 保留清晰的脱敏错误信息；
- 永不打印私钥和认证材料。

推荐后续统一为：

```text
./ops/deploy-internal-site
```

同事不直接调用底层 SFTP 命令。

### 5. 线上验证

上传后必须检查：

- 预览地址可访问；
- HTTP 状态为 `200`；
- Content-Type 合理；
- 首页包含预期内容；
- 主要静态资源没有 `404`；
- 必要时添加时间戳查询参数避免浏览器缓存误判。

### 6. 返回结果

成功回复：

```text
内网页面更新成功。

网站：site-a
访问地址：http://<OLD_MAC_IP>:8510/
线上状态：HTTP 200
页面内容：验证通过
```

失败回复：

```text
内网页面更新失败，请联系管理员。

网站：site-a
失败阶段：本地检查 / 上传 / 线上验证
错误摘要：脱敏后的实际错误
```

失败后不得：

- 改用其他服务器；
- 改用其他 SFTP 账号；
- 创建新的网站目录；
- 修改端口或 Nginx 配置；
- 绕过主机指纹；
- 恢复公网 Makers 发布。

## 账号生命周期

一人一个网站时，账号与网站一一对应：

```text
site-a-writer → site-a 目录 → site-a 内网地址
```

- 同事设备更换：替换公钥，网站目录不变；
- 私钥丢失：撤销旧公钥，签发新公钥；
- 同事离职：禁用账号，保留网站；
- 网站转交：替换公钥或新建接收人的账号映射，访问地址不变；
- 网站下线：先禁用上传，再归档文件，最后移除站点入口。

## PoC 与正式环境差异

当前 PoC 的配置仍使用：

```text
<OLD_MAC_IP>:2022
http://<OLD_MAC_IP>:8510/
```

正式环境应优先改成：

```text
SFTP：固定内部主机名
网页：http(s)://site-a.pages.<组织内部域>/
```

这样更换 Mac mini 时只需调整内部 DNS 和服务端配置，不需要修改同事的使用习惯。
