# Sun-Panel-v2 一键部署脚本（交互式增强版）

这是一个 **交互式 GitHub-ready 一键部署脚本**，用于在 Ubuntu 系统上快速部署 **sun-panel-v2** 面板，支持：

- Docker / Docker Compose 自动检测与安装  
- Nginx + HTTPS + HTTP2 + HSTS  
- 内网限制 sun-panel-v2，仅 Nginx 可访问  
- 数据库每日自动备份，支持自定义保留天数  
- 全程交互式，用户可以选择域名、邮箱、部署目录、备份策略  

---

## **一、脚本文件**

文件名：`deploy_sunpanel_interactive.sh`

具体执行下面这段命令
curl -fsSL https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/deploy_sunpanel_interactive.sh | bash

## **二、菜单式入口脚本（推荐）**

curl -fsSL https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/sunpanel.sh | bash
