# 🌞 Sun-Panel v2 一键部署脚本

> 面向普通用户 / 运维 / 自建面板爱好者的 **生产级一键部署方案**

本项目提供一个 **菜单式一键脚本**，用于在 **Ubuntu 20.04 / 22.04** 服务器上快速部署 **Sun-Panel v2**，并自动完成：

* Docker & Docker Compose 安装
* Sun-Panel 容器部署（数据持久化）
* Nginx 反向代理
* Let’s Encrypt HTTPS 证书
* 菜单式管理（安装 / 更新 / 备份 / 卸载）

---

## ✨ 特性亮点

* 🧩 **菜单式交互**（类似宝塔 / 1Panel）
* 🔐 **自动 HTTPS**（Let’s Encrypt，顺序修复，稳定）
* 🐳 **Docker 化部署**，不污染系统环境
* 💾 **数据库可备份 / 恢复**
* 🔄 **更新不丢数据**
* 🚫 已修复官方/社区常见的 **页面跳转、无法点击问题**

---

## 📦 支持环境

* Ubuntu 20.04 / 22.04
* 需要一个 **已解析到服务器 IP 的域名**
* 服务器需可访问外网（用于拉取镜像 & 申请证书）

---

## 🚀 一键安装（推荐）

```bash
curl -fsSL https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/sunpanel.sh -o sunpanel.sh
chmod +x sunpanel.sh
./sunpanel.sh
```
```bash
curl -sS -O https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/sunpanel.sh && chmod +x sunpanel.sh && ./sunpanel.sh
```

> ⚠️ **请使用 root 用户执行**

---

## 📋 菜单功能说明

运行脚本后会看到如下菜单：

```
1) 一键安装 sun-panel
2) 启动服务
3) 停止服务
4) 重启服务
5) 更新 sun-panel
6) 备份数据库
7) 恢复数据库
8) 卸载 sun-panel
0) 退出
```

### 1️⃣ 一键安装

* 自动安装 Docker / Nginx / Certbot
* 部署 Sun-Panel v2
* 自动配置 HTTPS
* 安装完成后直接可访问

### 5️⃣ 更新 Sun-Panel

* 拉取最新官方镜像
* **不会丢失任何数据**

### 6️⃣ / 7️⃣ 数据库备份与恢复

* 数据库存放路径：

  ```
  /opt/sun-panel-v2/database/database.db
  ```
* 备份文件目录：

  ```
  /opt/sun-panel-v2/backup/
  ```

---

## 🌐 访问方式

安装完成后，浏览器访问：

```
https://你的域名
```

首次访问会引导你 **创建管理员账号**（不是就是默认 admin/123456）。

---

## 🗂️ 目录结构说明

```text
/opt/sun-panel-v2/
├── conf/        # 配置文件
├── uploads/     # 上传文件
├── database/    # SQLite 数据库（核心数据）
├── backup/      # 数据库备份
└── docker-compose.yml
```

---

## ❓ 常见问题（FAQ）

### Q1：页面一直跳转 / 无法点击？

✅ 本脚本 **已彻底修复**，原因是：

* 采用 `127.0.0.1:3002` 本地监听
* 避免 Docker 内部反向代理嵌套

### Q2：证书申请失败怎么办？

请确认：

* 域名已正确解析到服务器 IP
* 80 / 443 端口未被占用

可手动检查：

```bash
ls /etc/letsencrypt/live/你的域名/
```

### Q3：如何完全卸载？

在菜单中选择：

```
8) 卸载 sun-panel
```

---

## 🔒 安全说明

* Nginx 仅代理到本地 `127.0.0.1`
* Sun-Panel 不直接暴露公网端口
* 建议服务器开启防火墙，仅放行 22 / 80 / 443

---

## 🧠 技术架构

```
浏览器
   ↓ HTTPS
Nginx（宿主机）
   ↓ HTTP
Sun-Panel（Docker）
```

这是目前 **最稳定、最易维护** 的部署方式。

---

## 🧾 项目来源

* Sun-Panel 官方项目：
  [https://github.com/75412701/sun-panel-v2](https://github.com/75412701/sun-panel-v2)

* 本项目：
  [https://github.com/jsdzcd/sun-panel-deploy](https://github.com/jsdzcd/sun-panel-deploy)

---

## ⭐ 支持项目

如果这个脚本帮到了你，欢迎：

* ⭐ Star 本仓库
* 📢 推荐给需要的朋友
* 🐛 提 Issue / PR 一起完善

---

## 📌 后续计划

* v1.3 自动更新 / 定时备份
* 多域名 / 多实例支持
* 面板健康检查

欢迎一起共建 🚀
