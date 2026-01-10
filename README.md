# Sun-Panel V2 一键部署脚本
（方便大家一键部署 感谢原作75412701）

<div align="center">

![Sun-Panel](https://img.shields.io/badge/Sun--Panel-一键部署-blue?style=for-the-badge)
![License](https://img.shields.io/badge/license-MIT-green?style=for-the-badge)
![Shell](https://img.shields.io/badge/shell-bash-orange?style=for-the-badge)

一个简单易用的 Sun-Panel 自动化部署脚本，支持主流 Linux 发行版

[快速开始](#快速安装) • [功能特性](#功能特性) • [使用文档](#使用说明) • [常见问题](#常见问题)

</div>

---

## 📖 项目简介

Sun-Panel 是一个优秀的服务器、NAS导航面板，本脚本提供一键安装、更新、管理等功能，让部署变得更加简单。

**原项目地址**: [75412701/sun-panel-v2](https://github.com/75412701/sun-panel-v2)

## ✨ 功能特性

- 🚀 **一键安装** - 自动安装 Docker 及所有依赖
- 🔍 **智能检测** - 自动检测系统类型和端口占用
- 💾 **数据持久化** - 自动配置数据卷挂载
- 🔄 **便捷管理** - 提供启动、停止、重启、更新等功能
- 📊 **日志查看** - 实时查看运行日志
- 🛡️ **安全备份** - 更新时自动备份数据
- 🎨 **美观界面** - 交互式菜单，操作简单直观

## 🖥️ 系统要求

### 支持的操作系统
- ✅ Ubuntu 18.04+
- ✅ Debian 10+
- ✅ CentOS 7+
- ✅ Rocky Linux 8+
- ✅ AlmaLinux 8+

### 最低配置
- CPU: 1 核
- 内存: 512MB
- 磁盘: 1GB 可用空间

## 🚀 快速安装

### 方式一：wget 安装（推荐）
```bash
wget -O sun-panel-install.sh https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/install.sh && chmod +x sun-panel-install.sh && ./sun-panel-install.sh
```

### 方式二：curl 安装
```bash
curl -fsSL https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/install.sh -o sun-panel-install.sh && chmod +x sun-panel-install.sh && ./sun-panel-install.sh
```

### 方式三：直接安装（跳过菜单）
```bash
curl -fsSL https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/install.sh | bash -s install
```

## 📝 使用说明

### 安装完成后

访问地址：`http://你的服务器IP:3002`

**默认登录信息**：
- 账号：`admin`
- 密码：`12345678`

> ⚠️ **重要提示**：首次登录后请立即修改默认密码！

### 数据目录

所有数据存储在 `~/docker_data/sun-panel/` 目录下：

```
~/docker_data/sun-panel/
├── conf/          # 配置文件
├── uploads/       # 上传文件
└── database/      # 数据库文件
```

### 常用命令

```bash
# 查看容器状态
docker ps | grep sun-panel

# 启动容器
docker start sun-panel

# 停止容器
docker stop sun-panel

# 重启容器
docker restart sun-panel

# 查看日志
docker logs -f sun-panel

# 进入容器
docker exec -it sun-panel /bin/sh
```

### 脚本菜单操作

运行脚本后会显示交互式菜单：

```
请选择操作:

  1) 安装 Sun-Panel
  2) 查看状态
  3) 启动服务
  4) 停止服务
  5) 重启服务
  6) 查看日志
  7) 更新版本
  8) 卸载
  0) 退出
```

## 🔧 高级配置

### 自定义端口

安装时脚本会提示输入端口号，也可以手动修改：

```bash
# 停止容器
docker stop sun-panel

# 删除容器（数据不会丢失）
docker rm sun-panel

# 使用新端口重新创建容器
docker run -d \
  --name sun-panel \
  --restart=always \
  -p 8080:3002 \
  -v ~/docker_data/sun-panel/conf:/app/conf \
  -v ~/docker_data/sun-panel/uploads:/app/uploads \
  -v ~/docker_data/sun-panel/database:/app/database \
  hslr/sun-panel:latest
```

### 自定义数据目录

修改脚本中的 `INSTALL_PATH` 变量：

```bash
INSTALL_PATH="/your/custom/path"
```

### 使用 Docker Compose

创建 `docker-compose.yml` 文件：

```yaml
version: '3'
services:
  sun-panel:
    image: hslr/sun-panel:latest
    container_name: sun-panel
    restart: always
    ports:
      - "3002:3002"
    volumes:
      - ./conf:/app/conf
      - ./uploads:/app/uploads
      - ./database:/app/database
```

启动：
```bash
docker-compose up -d
```

## 🔄 更新升级

### 使用脚本更新
```bash
./sun-panel-install.sh
# 选择菜单中的 "7) 更新版本"
```

### 手动更新
```bash
# 停止容器
docker stop sun-panel

# 删除容器
docker rm sun-panel

# 拉取最新镜像
docker pull hslr/sun-panel:latest

# 重新创建容器（使用原配置）
docker run -d \
  --name sun-panel \
  --restart=always \
  -p 3002:3002 \
  -v ~/docker_data/sun-panel/conf:/app/conf \
  -v ~/docker_data/sun-panel/uploads:/app/uploads \
  -v ~/docker_data/sun-panel/database:/app/database \
  hslr/sun-panel:latest
```

## 🗑️ 卸载

### 使用脚本卸载
```bash
./sun-panel-install.sh
# 选择菜单中的 "8) 卸载"
```

### 手动卸载
```bash
# 停止并删除容器
docker stop sun-panel
docker rm sun-panel

# 删除镜像
docker rmi hslr/sun-panel:latest

# 删除数据（可选，谨慎操作！）
rm -rf ~/docker_data/sun-panel
```

## ❓ 常见问题

<details>
<summary><b>1. 端口被占用怎么办？</b></summary>

安装时脚本会自动检测端口占用，如果默认端口 3002 被占用，可以选择其他端口。

查看端口占用：
```bash
lsof -i :3002
```

更换端口后重新安装即可。
</details>

<details>
<summary><b>2. 忘记密码怎么办？</b></summary>

删除数据库文件重置：
```bash
docker stop sun-panel
rm ~/docker_data/sun-panel/database/*
docker start sun-panel
```

然后使用默认密码登录。
</details>

<details>
<summary><b>3. 容器无法启动？</b></summary>

查看日志排查问题：
```bash
docker logs sun-panel
```

常见原因：
- 端口被占用
- 权限不足
- 磁盘空间不足
</details>

<details>
<summary><b>4. 如何备份数据？</b></summary>

备份整个数据目录：
```bash
tar -czf sun-panel-backup-$(date +%Y%m%d).tar.gz ~/docker_data/sun-panel/
```

恢复备份：
```bash
tar -xzf sun-panel-backup-YYYYMMDD.tar.gz -C ~/
```
</details>

<details>
<summary><b>5. 支持 ARM 架构吗？</b></summary>

Sun-Panel 官方镜像支持多架构，包括：
- amd64 (x86_64)
- arm64 (aarch64)
- armv7

树莓派等 ARM 设备可以直接使用本脚本安装。
</details>

<details>
<summary><b>6. 如何设置开机自启？</b></summary>

容器已设置 `--restart=always`，会随 Docker 自动启动。

确保 Docker 开机自启：
```bash
systemctl enable docker
```
</details>

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启 Pull Request

## 📄 开源协议

本项目采用 [MIT](LICENSE) 协议开源

## 🙏 致谢

- [Sun-Panel](https://github.com/hslr-s/sun-panel) - 原项目
- [Docker](https://www.docker.com/) - 容器化技术

## 📮 联系方式

- 提交 Issue: [GitHub Issues](https://github.com/jsdzcd/sun-panel-deploy/issues)
- 邮箱: your-email@example.com

## ⭐ Star History

如果这个项目对你有帮助，请给个 Star ⭐ 支持一下！

[![Star History Chart](https://api.star-history.com/svg?repos=jsdzcd/sun-panel-deploy&type=Date)](https://star-history.com/#jsdzcd/sun-panel-deploy&Date)

---

<div align="center">

**[⬆ 回到顶部](#sun-panel-一键部署脚本)**

Made with ❤️ by [jsdzcd](https://github.com/jsdzcd)

</div>
