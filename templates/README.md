# 同事交接模板

IT 为每个网站单独生成交接包：

```text
.env
AGENTS.md
```

操作方法：

1. site-a 复制 `site-a.env.example`，site-b 复制 `site-b.env.example`，目标文件名为项目根目录 `.env`；
2. 填入目标服务器 IP 和对应站点的随机密码；
3. site-a 复制 `site-a.AGENTS.md`，site-b 复制 `site-b.AGENTS.md`，目标文件名为项目根目录 `AGENTS.md`；
4. 确认 `.env` 已加入同事项目的 `.gitignore`；
5. 扫描交接包，确认不包含其他网站信息；
6. 通过安全渠道单独交付给对应同事。

本仓库中的示例文件不得直接作为真实交接成品；包含真实密码的生成结果必须保存在仓库之外。
