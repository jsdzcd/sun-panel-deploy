#!/bin/bash
# =================================================================
# Sun-Panel-v2 Docker 部署脚本 (增强版)
# Author: jsdzcd
# Version: 1.3.1
# Github: https://github.com/jsdzcd/sun-panel-deploy
# =================================================================

# --- 配置参数 ---
BASE_DIR="/opt/sun-panel-v2"
BACKUP_DIR="$BASE_DIR/backup"
WEBROOT="/var/www/html"

# 内部与外部端口配置
APP_PORT=3002
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
  if command -v apt &>/dev/null; then
      apt update
      apt install -y curl wget nginx ca-certificates gnupg lsb-release socat
  elif command -v yum &>/dev/null; then
      yum install -y curl wget nginx ca-certificates socat
  else
      log_err "未知的包管理器，仅支持 Debian/Ubuntu/CentOS"
      exit 1
  fi

  if ! command -v docker &>/dev/null; then
    log_info "安装 Docker..."
    curl -fsSL https://get.docker.com | bash
    systemctl enable docker
    systemctl start docker
  fi
  systemctl enable nginx
  systemctl start nginx
}

# --- 初始化目录 ---
init_dirs(){
  log_info "初始化目录结构..."
  mkdir -p "$BASE_DIR"/{conf,uploads,database,backup}
  mkdir -p "$WEBROOT"
  # 自动适配 Nginx 用户权限
  NGINX_USER=$(ps aux | grep nginx | grep worker | awk '{print $1}' | head -n 1)
  [[ -z "$NGINX_USER" ]] && NGINX_USER="www-data"
  chown -R "$NGINX_USER":"$NGINX_USER" "$WEBROOT"
  chmod -R 755 "$WEBROOT"
}

# --- 部署逻辑 ---
install_sunpanel(){
  check_root
  install_env
  init_dirs

  echo ""
  log_info "准备部署 Sun-Panel"
  read -p "请输入访问域名 (例如 panel.512341.xyz): " DOMAIN
  if [[ -z "$DOMAIN" ]]; then log_err "域名不能为空"; return; fi

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

  cd $BASE_DIR
  log_info "启动 Sun-Panel 容器..."
  docker compose up -d

  gen_nginx_http "$DOMAIN"
  log_info "基础安装完成！"
  echo -e "HTTP 访问地址: http://${DOMAIN}:${HTTP_PORT}"
  echo -e "如需开启加密访问，请在主菜单选择 [9] 申请证书。"
}

# --- Nginx 配置生成 (核心修复版) ---
gen_nginx_http(){
  local domain=$1
  log_info "生成 Nginx HTTP 配置..."
cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen 80;
    listen ${HTTP_PORT};
    server_name ${domain};

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
  log_info "生成 Nginx HTTPS 配置 (兼容模式)..."
cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen 80;
    listen ${HTTP_PORT};
    server_name ${domain};
    
    location ^~ /.well-known/acme-challenge/ {
        default_type "text/plain";
        root ${WEBROOT};
    }

    location / {
        return 301 https://\$host:${HTTPS_PORT}\$request_uri;
    }
}

server {
    # 兼容性写法：listen 后接 ssl http2
    listen ${HTTPS_PORT} ssl http2;
    server_name ${domain};

    ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
    
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
    log_info "Nginx 配置重载成功"
  else
    log_err "Nginx 配置语法错误，请检查！"
  fi
}

# --- HTTPS 证书申请 ---
request_https(){
  [[ ! -f /etc/nginx/conf.d/sun-panel.conf ]] && { log_err "未发现 Nginx 配置，请先安装。"; return; }
  
  DOMAIN=$(grep "server_name" /etc/nginx/conf.d/sun-panel.conf | head -n 1 | awk '{print $2}' | sed 's/;//')
  read -p "当前配置域名为 [${DOMAIN}]，确定吗? (y/n): " CONFIRM
  [[ "$CONFIRM" != "y" ]] && read -p "输入正确域名: " DOMAIN
  
  read -p "输入联系邮箱: " EMAIL
  [[ -z "$EMAIL" ]] && { log_err "邮箱必填"; return; }

  log_info "申请证书中 (Webroot 模式)..."
  docker run -it --rm \
    -v "/etc/letsencrypt:/etc/letsencrypt" \
    -v "/var/lib/letsencrypt:/var/lib/letsencrypt" \
    -v "$WEBROOT:$WEBROOT" \
    certbot/certbot certonly \
    --webroot -w "$WEBROOT" \
    -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email

  if [[ $? -eq 0 && -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    gen_nginx_https "$DOMAIN"
  else
    log_err "证书申请失败，请确认 80 端口开放并已正确解析 DNS。"
  fi
}

# --- 管理功能 ---
start_service(){ cd $BASE_DIR && docker compose up -d && log_info "已启动"; }
stop_service(){ cd $BASE_DIR && docker compose down && log_info "已停止"; }
restart_service(){ cd $BASE_DIR && docker compose restart && log_info "已重启"; }
update_service(){ cd $BASE_DIR && docker compose pull && docker compose up -d && log_info "已更新"; }

uninstall_all(){
  read -p "⚠️ 危险！确认彻底卸载? [y/N]: " OK
  [[ "$OK" =~ ^[Yy]$ ]] || return
  cd $BASE_DIR && docker compose down
  rm -rf $BASE_DIR
  rm -f /etc/nginx/conf.d/sun-panel.conf
  systemctl reload nginx
  log_info "已彻底卸载"
}

# --- 菜单控制 ---
menu(){
  clear
  echo -e "${BLUE}=======================================${RESET}"
  echo -e "${BLUE}   Sun-Panel 一键部署管理脚本 v1.3.1   ${RESET}"
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
