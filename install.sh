#!/bin/bash
set -e

####################################################################
# Sun Panel V2 一键部署脚本
# 支持 Ubuntu、CentOS 等 Linux 系统
# 功能：Docker部署、Nginx反向代理、SSL证书、状态管理、备份升级
####################################################################

# 配置项
APP_NAME="sun-panel-v2"
APP_DIR="/opt/${APP_NAME}"
GITHUB_REPO="https://github.com/75412701/sun-panel-v2.git"
DOCKER_COMPOSE_FILE="docker-compose.yml"
NGINX_CONF_DIR="/etc/nginx/conf.d"
DOMAIN=""  # 用户输入的域名
HTTP_PORT=3002  # 原项目端口
HTTPS_PORT=443   # HTTPS端口
ACME_SH_DIR="/root/.acme.sh"

# 颜色输出函数
red() { echo -e "\033[31m$1\033[0m"; }
green() { echo -e "\033[32m$1\033[0m"; }
yellow() { echo -e "\033[33m$1\033[0m"; }
blue() { echo -e "\033[34m$1\033[0m"; }

# 检查是否为root用户
check_root() {
    if [ $EUID -ne 0 ]; then
        red "错误：必须以root用户运行此脚本！"
        exit 1
    fi
}

# 安装依赖（Docker、Docker Compose、Nginx、curl、git、socat）
install_dependencies() {
    blue "=== 安装系统依赖 ==="
    apt update && apt install -y curl git nginx apt-transport-https ca-certificates software-properties-common socat

    # 安装Docker
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh
        systemctl enable --now docker
        green "Docker安装完成"
    else
        yellow "Docker已安装，跳过"
    fi

    # 安装Docker Compose
    if ! command -v docker-compose &> /dev/null; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
        green "Docker Compose安装完成"
    else
        yellow "Docker Compose已安装，跳过"
    fi

    # 安装acme.sh（改用官方一键在线安装，稳定无路径问题）
    if [ ! -d "${ACME_SH_DIR}" ] || [ ! -x "${ACME_SH_DIR}/acme.sh" ]; then
        blue "=== 安装acme.sh（官方一键安装） ==="
        # 官方一键安装命令，自动配置home目录、软链接、自动升级
        curl https://get.acme.sh | sh -s email=admin@${DOMAIN}  # 自动使用输入的域名作为邮箱（可选）
        # 验证安装是否成功
        if [ ! -x "${ACME_SH_DIR}/acme.sh" ]; then
            red "acme.sh 官方安装失败，请检查网络连接或手动执行：curl https://get.acme.sh | sh"
            exit 1
        fi
        # 强制更新软链接（确保全局可调用）
        ln -sf ${ACME_SH_DIR}/acme.sh /usr/local/bin/acme.sh
        green "acme.sh安装完成"
    else
        yellow "acme.sh已安装，跳过"
    fi
}

# 克隆项目代码
clone_project() {
    blue "=== 克隆项目代码 ==="
    if [ -d "${APP_DIR}" ]; then
        yellow "项目目录已存在，先备份并删除旧目录"
        mv ${APP_DIR} ${APP_DIR}_$(date +%Y%m%d%H%M%S)
    fi
    git clone ${GITHUB_REPO} ${APP_DIR}
    cd ${APP_DIR}
    green "项目代码克隆完成"
}

# 申请SSL证书
apply_ssl_certificate() {
    if [ -z "${DOMAIN}" ]; then
        red "域名未输入，跳过SSL证书申请"
        return 1
    fi

    blue "=== 申请SSL证书（Let's Encrypt） ==="
    # 停止Nginx避免端口占用
    systemctl stop nginx
    # 改用全局acme.sh命令，无需依赖绝对路径，避免文件不存在错误
    acme.sh --issue -d ${DOMAIN} --standalone -k ec-256
    # 安装证书到Nginx目录
    acme.sh --install-cert -d ${DOMAIN} \
        --key-file /etc/ssl/${DOMAIN}_key.pem \
        --fullchain-file /etc/ssl/${DOMAIN}_cert.pem \
        --reloadcmd "systemctl restart nginx"
    green "SSL证书申请并安装完成"
}

# 配置Nginx反向代理（隐藏端口）
configure_nginx() {
    blue "=== 配置Nginx反向代理 ==="
    # 生成Nginx配置文件
    cat > ${NGINX_CONF_DIR}/${APP_NAME}.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    # 强制跳转到HTTPS
    return 301 https://\$host\$request_uri;
}

server {
    listen ${HTTPS_PORT} ssl http2;
    server_name ${DOMAIN};

    # SSL配置
    ssl_certificate /etc/ssl/${DOMAIN}_cert.pem;
    ssl_certificate_key /etc/ssl/${DOMAIN}_key.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers on;

    # 反向代理配置
    location / {
        proxy_pass http://127.0.0.1:${HTTP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # 静态资源缓存
    location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
        proxy_pass http://127.0.0.1:${HTTP_PORT};
        proxy_set_header Host \$host;
        expires 30d;
    }
}
EOF

    # 检查Nginx配置并重启
    nginx -t && systemctl restart nginx
    green "Nginx反向代理配置完成"
}

# 部署项目（Docker Compose）
deploy_project() {
    blue "=== 部署项目 ==="
    cd ${APP_DIR}

    # 生成docker-compose.yml（适配原项目配置）
    cat > ${DOCKER_COMPOSE_FILE} << EOF
version: "3.2"
services:
  ${APP_NAME}:
    image: 'ghcr.io/75412701/${APP_NAME}:latest'
    container_name: ${APP_NAME}
    volumes:
      - ./conf:/app/conf
      - ./uploads:/app/uploads
      - ./database:/app/database
    ports:
      - ${HTTP_PORT}:${HTTP_PORT}
    restart: always
    network_mode: bridge
EOF

    # 启动容器
    docker-compose up -d
    green "项目容器启动完成"
    green "项目访问地址："
    if [ -n "${DOMAIN}" ]; then
        green "HTTPS: https://${DOMAIN}"
    else
        green "HTTP: http://$(curl -s ifconfig.me):${HTTP_PORT}"
    fi
}

# 主菜单
main_menu() {
    clear
    blue "==================== Sun-Panel-V2 一键部署脚本 ===================="
    echo "1. 完整部署（安装依赖+克隆代码+部署项目+申请证书+配置Nginx）"
    echo "2. 仅部署项目（已安装依赖时使用）"
    echo "3. 申请/更新SSL证书"
    echo "4. 配置Nginx反向代理"
    echo "5. 停止项目"
    echo "6. 启动项目"
    echo "7. 查看项目日志"
    echo "0. 退出"
    blue "====================================================================="
    read -p "请输入操作序号：" OPTION

    case ${OPTION} in
        1)
            check_root
            read -p "请输入你的域名（为空则不配置HTTPS）：" DOMAIN
            install_dependencies
            clone_project
            deploy_project
            if [ -n "${DOMAIN}" ]; then
                apply_ssl_certificate
                configure_nginx
            fi
            green "=== 完整部署完成 ==="
            ;;
        2)
            check_root
            clone_project
            deploy_project
            green "=== 项目部署完成 ==="
            ;;
        3)
            check_root
            read -p "请输入你的域名：" DOMAIN
            # 确保acme.sh已安装
            if ! command -v acme.sh &> /dev/null; then
                red "acme.sh未安装，先执行完整部署或手动安装"
                exit 1
            fi
            apply_ssl_certificate
            ;;
        4)
            check_root
            read -p "请输入你的域名：" DOMAIN
            configure_nginx
            ;;
        5)
            check_root
            cd ${APP_DIR} && docker-compose down
            green "=== 项目已停止 ==="
            ;;
        6)
            check_root
            cd ${APP_DIR} && docker-compose up -d
            green "=== 项目已启动 ==="
            ;;
        7)
            check_root
            cd ${APP_DIR} && docker-compose logs -f
            ;;
        0)
            exit 0
            ;;
        *)
            red "输入错误，请重新选择！"
            sleep 2
            main_menu
            ;;
    esac
}

# 启动主菜单
main_menu
