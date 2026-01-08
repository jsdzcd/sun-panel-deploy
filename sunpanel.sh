#!/bin/bash
# =================================================================
# Sun-Panel-v2 Docker 部署脚本 (增强版)
# Author: tanksofchina
# Version: 1.3.0
# Github: https://github.com/your-repo/sun-panel-deploy
# =================================================================

# --- 配置参数 ---
BASE_DIR="/opt/sun-panel-v2"
BACKUP_DIR="$BASE_DIR/backup"
WEBROOT="/var/www/html" # 统一 Webroot 路径，避免权限问题

# 容器内端口 (Sun-Panel 默认是 3002)
APP_PORT=3002

# 外部访问端口 (Nginx 反代端口)
HTTP_PORT=3002
HTTPS_PORT=3443

# --- 颜色定义 ---
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[36m"
RESET="\033[0m"

# --- 基础函数 ---

pause(){ read -p "按 Enter 键继续..." ; }

log_info(){ echo -e "${GREEN}[INFO] $1${RESET}"; }
log_warn(){ echo -e "${YELLOW}[WARN] $1${RESET}"; }
log_err(){ echo -e "${RED}[ERROR] $1${RESET}"; }

check_root(){
  if [[ $EUID -ne 0 ]]; then
    log_err "请使用 root 用户运行此脚本"
    exit 1
  fi
}

# --- 环境安装 ---

install_env(){
  log_info "检查并安装系统依赖..."
  
  # 检测包管理器
  if command -v apt &>/dev/null; then
      apt update
      apt install -y curl wget nginx ca-certificates gnupg lsb-release socat
  elif command -v yum &>/dev/null; then
      yum install -y curl wget nginx ca-certificates socat
  else
      log_err "未知的包管理器，仅支持 Debian/Ubuntu/CentOS"
      exit 1
  fi

  # 安装 Docker
  if ! command -v docker &>/dev/null; then
    log_info "安装 Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
  else
    log_info "Docker 已安装"
  fi

  # 确保 Nginx 启动
  systemctl enable nginx
  systemctl start nginx
}

# --- 初始化目录 ---

init_dirs(){
  log_info "初始化目录结构..."
  mkdir -p "$BASE_DIR"/{conf,uploads,database,backup}
  mkdir -p "$WEBROOT"
  
  # 修复权限，确保 Nginx 可读 Webroot
  chown -R www-data:www-data "$WEBROOT" 2>/dev/null || chown -R nginx:nginx "$WEBROOT" 2>/dev/null
  chmod -R 755 "$WEBROOT"
}

# --- 部署 Sun-Panel ---

install_sunpanel(){
  check_root
  install_env
  init_dirs

  echo ""
  log_info "准备部署 Sun-Panel"
  read -p "请输入访问域名 (例如 panel.example.com): " DOMAIN
  if [[ -z "$DOMAIN" ]]; then log_err "域名不能为空"; return; fi

  # 1. 创建 Docker Compose 文件
  log_info "生成 docker-compose.yml..."
cat > $BASE_DIR/docker-compose.yml <<EOF
services:
  sun-panel:
    image: ghcr.io/75412701/sun-panel-v2:latest
    container_name: sun-panel-v2
    restart: always
    ports:
      - "127.0.0.1:${APP_PORT}:3002" 
    volumes:
      - ./conf:/app/conf
      - ./uploads:/app/uploads
      - ./database:/app/database
EOF
# 注意：端口映射改为 127.0.0.1，防止绕过 Nginx 直接访问

  # 2. 启动容器
  cd $BASE_DIR
  log_info "启动 Sun-Panel 容器..."
  docker compose up -d

  # 3. 生成基础 Nginx HTTP 配置 (带 ACME 验证支持)
  gen_nginx_http "$DOMAIN"

  log_info "部署完成！"
  echo -e "HTTP 访问地址: http://${DOMAIN}:${HTTP_PORT}"
  echo -e "若要开启 HTTPS，请在主菜单选择 [9]"
}

# --- Nginx 配置生成器 ---

gen_nginx_http(){
  local domain=$1
  log_info "配置 Nginx (HTTP Mode)..."

cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen 80;
    listen ${HTTP_PORT};
    server_name ${domain};

    # 用于 Let's Encrypt 验证
    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        root ${WEBROOT};
    }

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
  reload_nginx
}

gen_nginx_https(){
  local domain=$1
  log_info "配置 Nginx (HTTPS Mode)..."

cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen 80;
    listen ${HTTP_PORT};
    server_name ${domain};
    
    # 强制跳转 HTTPS (排除验证文件)
    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        root ${WEBROOT};
    }
    location / {
        return 301 https://\$host:${HTTPS_PORT}\$request_uri;
    }
}

server {
    listen ${HTTPS_PORT} ssl;
    http2 on;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    
    # 安全增强配置
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;
    add_header Strict-Transport-Security "max-age=63072000" always;

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # WebSocket 支持
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF
  reload_nginx
}

reload_nginx(){
  if nginx -t; then
    systemctl reload nginx
    log_info "Nginx 重载成功"
  else
    log_err "Nginx 配置检测失败，请手动检查 /etc/nginx/conf.d/sun-panel.conf"
  fi
}

# --- HTTPS 证书申请 (核心逻辑) ---

request_https(){
  log_info "准备申请 HTTPS 证书..."
  
  # 获取当前配置的域名
  if [[ ! -f /etc/nginx/conf.d/sun-panel.conf ]]; then
    log_err "未检测到 Nginx 配置文件，请先执行安装步骤。"
    return
  fi
  
  # 尝试从 Nginx 配置中提取域名
  DOMAIN=$(grep "server_name" /etc/nginx/conf.d/sun-panel.conf | head -n 1 | awk '{print $2}' | sed 's/;//')
  
  read -p "检测到域名为 [${DOMAIN}]，确认吗? (y/n): " CONFIRM
  if [[ "$CONFIRM" != "y" ]]; then
    read -p "请输入正确域名: " DOMAIN
  fi
  
  read -p "请输入联系邮箱 (用于证书过期提醒): " EMAIL
  if [[ -z "$EMAIL" ]]; then log_err "邮箱不能为空"; return; fi

  echo "------------------------------------------------"
  echo "请确保："
  echo "1. 域名 [${DOMAIN}] 已解析到本机 IP"
  echo "2. 本机防火墙已开放 80 端口 (用于验证)"
  echo "------------------------------------------------"
  pause

  # 确保 Nginx 正在运行且配置了验证目录
  gen_nginx_http "$DOMAIN"

  log_info "开始申请证书 (Webroot 模式)..."
  
  # 使用 Docker 运行 Certbot，映射主机 /etc/letsencrypt 以便 Nginx 直接读取
  docker run -it --rm \
    -v "/etc/letsencrypt:/etc/letsencrypt" \
    -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
    -v "$WEBROOT:$WEBROOT" \
    certbot/certbot certonly \
    --webroot \
    -w "$WEBROOT" \
    -d "$DOMAIN" \
    --email "$EMAIL" \
    --agree-tos \
    --no-eff-email \
    --force-renewal

  EXIT_CODE=$?

  if [[ $EXIT_CODE -eq 0 ]]; then
    # 双重检查文件是否存在
    if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
      log_info "证书申请成功！正在应用 HTTPS 配置..."
      gen_nginx_https "$DOMAIN"
      echo -e "${GREEN}✔ HTTPS 部署完成！请访问 https://${DOMAIN}:${HTTPS_PORT}${RESET}"
    else
      log_err "Certbot 提示成功，但未找到证书文件。可能是路径映射问题。"
    fi
  else
    log_err "证书申请失败。Nginx 将保持 HTTP 模式。"
    log_warn "排查建议："
    echo "1. 检查域名解析是否生效 (ping ${DOMAIN})"
    echo "2. 检查 80 端口是否被防火墙拦截"
    echo "3. 检查 Webroot 路径是否可写"
  fi
}

# --- 其他管理功能 ---

start_service(){ cd $BASE_DIR && docker compose up -d && log_info "服务已启动"; }
stop_service(){ cd $BASE_DIR && docker compose down && log_info "服务已停止"; }
restart_service(){ cd $BASE_DIR && docker compose restart && log_info "服务已重启"; }

update_service(){
  cd $BASE_DIR
  log_info "拉取最新镜像..."
  docker compose pull
  log_info "重启容器..."
  docker compose up -d
  log_info "更新完成"
}

uninstall_all(){
  read -p "⚠️ 确认彻底卸载? 将删除数据和配置文件 [y/N]: " OK
  [[ "$OK" =~ ^[Yy]$ ]] || return
  
  cd $BASE_DIR 2>/dev/null && docker compose down
  rm -rf $BASE_DIR
  rm -f /etc/nginx/conf.d/sun-panel.conf
  systemctl reload nginx
  log_info "卸载完成"
}

# --- 菜单 ---

menu(){
  clear
  echo -e "${BLUE}=======================================${RESET}"
  echo -e "${BLUE}   Sun-Panel 一键部署管理脚本 v1.3.0   ${RESET}"
  echo -e "${BLUE}=======================================${RESET}"
  echo "1. 安装 Sun-Panel (HTTP)"
  echo "2. 启动服务"
  echo "3. 停止服务"
  echo "4. 重启服务"
  echo "5. 更新 Sun-Panel"
  echo "6. 卸载 Sun-Panel"
  echo "------------------------"
  echo "9. 申请并开启 HTTPS (SSL)"
  echo "0. 退出"
  echo "=================================="
}

check_root
while true; do
  menu
  read -p "请输入选项: " NUM
  case $NUM in
    1) install_sunpanel ;;
    2) start_service ;;
    3) stop_service ;;
    4) restart_service ;;
    5) update_service ;;
    6) uninstall_all ;;
    9) request_https ;;
    0) exit 0 ;;
    *) log_err "无效选项" ;;
  esac
  pause
done
