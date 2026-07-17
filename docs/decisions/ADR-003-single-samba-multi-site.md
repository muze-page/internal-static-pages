# ADR-003：一个 Samba 容器承载多个隔离站点

## 状态

已接受，取代 ADR-002 的单站点 Samba 配置。

## 日期

<VALIDATION_DATE>

## 背景

site-a 上线后，同事 B 需要第二个独立静态网站。SMB 标准端口 `445` 在同一 IP 上只能由一个服务监听，因此不能为每个网站启动一个独立 Samba 容器并都绑定 `445`。

## 决策

- 使用一个 `internal-pages-samba` 容器监听 `0.0.0.0:445`；
- 每个网站使用独立 Docker 卷、SMB 共享名、账号和随机密码；
- `users.conf` 创建 `site-a-writer` 和 `site-b-writer` 两个无 Shell 用户；
- `smb.conf` 在每个共享中使用 `valid users`、`force user` 和 `force group` 强制身份与目录隔离；
- site-a 使用 `internal-pages-site-a-data`、`site-a-writer`、`8520`；
- site-b 使用 `internal-pages-site-b-data`、`site-b-writer`、`8530`；
- 每个 Nginx 容器只读挂载对应站点卷；
- 新增站点时先在备用端口启动临时 Samba 容器验证账号与交叉访问，通过后再切换正式 `445`。

## 已验证不变量

- 同事 A 可以读写 site-a，无法访问 site-b；
- 同事 B 可以读写 site-b，无法访问 site-a；
- 错误密码和访客访问均被拒绝；
- Samba 容器只挂载 site-a 与 site-b 两个站点内容卷，不接触宿主机的其他网站目录；
- Nginx 对站点卷只读；
- 新增 site-b 后，site-a 的 SMB 密码、共享地址和 `8520` 页面地址均未变。

## 后果

- 新增网站不再新增 SMB 端口，Windows 统一访问 `\\<OLD_MAC_IP>\<site-id>`；
- 网页端口仍按站点独立分配；
- 修改 Samba 账号配置会重建统一容器，必须先在备用端口验证；
- `users.conf`、服务器 `.env` 和各交接 `.env` 都包含密码，必须保持 `0600` 且不得进入 Git。
