#!/usr/bin/env bash
set -e

# ================= 基础配置 =================
BASE_DIR="/opt/sun-panel-v2"
COMPOSE_FILE="$BASE_DIR/docker-compose.yml"
WEBROOT="$BASE_DIR/nginx/certbot"
HTTP_PORT=3002
HTTPS_PORT=3443
DOMAIN_FILE="$BASE_DIR/.domain"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# ================= 工具函数 =================
pause() { read -rp "按 Enter 键继续..."; }

check_root() {
  [[ $EUID -ne 0 ]] && echo -e "${RED}请使用 root 运行${RESET}" && exit 1
}

install_base() {
  apt update
  apt install -y curl nginx docker.io docker-compose-plugin certbot
  systemctl enable docker nginx
  systemctl start docker nginx
}

get_domain() {
  if [[ -f "$DOMAIN_FILE" ]]; then
    DOMAIN=$(cat "$DOMAIN_FILE")
  else
    read -rp "请输入绑定域名: " DOMAIN
    echo "$DOMAIN" > "$DOMAIN_FILE"
  fi
}

cert_exists() {
  [[ -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]]
}

# ================= Nginx 配置 =================
write_nginx_http() {
  cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen ${HTTP_PORT};
    server_name ${DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${WEBROOT};
    }

    location / {
        proxy_pass http://127.0.0.1:${HTTP_PORT};
        proxy_set_header Host \$host;
    }
}
EOF
}

write_nginx_https() {
  cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen ${HTTP_PORT};
    server_name ${DOMAIN};
    return 301 https://\$host:${HTTPS_PORT}\$request_uri;
}

server {
    listen ${HTTPS_PORT} ssl http2;
    server_name ${DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:${HTTP_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF
}

reload_nginx() {
  nginx -t && systemctl reload nginx
}

# ================= Docker =================
write_compose() {
  read -rp "请输入容器映射的端口（例如：3002，默认值是3002）: " CONTAINER_PORT
  CONTAINER_PORT=${CONTAINER_PORT:-3002}

  mkdir -p "$BASE_DIR"
  cat > "$COMPOSE_FILE" <<EOF
services:
  sun-panel:
    image: ghcr.io/75412701/sun-panel-v2:latest
    container_name: sun-panel-v2
    restart: unless-stopped
    ports:
      - "${CONTAINER_PORT}:3002"
    volumes:
      - ${BASE_DIR}/database:/app/database
EOF
}

docker_up() {
  docker compose -f "$COMPOSE_FILE" up -d
}

# ================= 功能实现 =================
install_all() {
  check_root
  install_base
  get_domain

  mkdir -p "$WEBROOT"
  write_compose
  docker_up

  write_nginx_http
  reload_nginx

  echo -e "${GREEN}✔ 安装完成（HTTP 端口 ${HTTP_PORT}）${RESET}"
}

apply_cert() {
  get_domain

  if cert_exists; then
    echo -e "${YELLOW}证书已存在，无需重复申请${RESET}"
    pause; return
  fi

  certbot certonly \
    --webroot \
    -w "$WEBROOT" \
    -d "$DOMAIN" \
    --agree-tos \
    -m "admin@$DOMAIN" \
    --non-interactive

  if cert_exists; then
    write_nginx_https
    reload_nginx
    echo -e "${GREEN}✔ HTTPS 已启用（端口 ${HTTPS_PORT}）${RESET}"
  else
    echo -e "${RED}❌ 证书申请失败${RESET}"
  fi
}

status_check() {
  get_domain
  echo "==================== 系统状态 ===================="
  systemctl is-active docker >/dev/null && echo "Docker: 运行" || echo "Docker: 停止"
  docker ps | grep sun-panel >/dev/null && echo "Sun-Panel 容器: 运行" || echo "Sun-Panel 容器: 未运行"
  systemctl is-active nginx >/dev/null && echo "Nginx: 运行" || echo "Nginx: 停止"

  if cert_exists; then
    echo "HTTPS 证书: 已申请"
  else
    echo "HTTPS 证书: 未申请"
  fi
  echo "访问地址:"
  echo "  HTTP  → http://${DOMAIN}:${HTTP_PORT}"
  cert_exists && echo "  HTTPS → https://${DOMAIN}:${HTTPS_PORT}"
  echo "=================================================="
  pause
}

update_panel() {
  docker compose -f "$COMPOSE_FILE" pull
  docker compose -f "$COMPOSE_FILE" up -d
  echo -e "${GREEN}✔ 更新完成${RESET}"
  pause
}

# ================= 菜单 =================
menu() {
clear
cat <<EOF
==================================
 Sun-Panel 管理脚本 v1.3.1 稳定版
==================================
1) 一键安装 Sun-Panel
2) 更新 Sun-Panel
3) 申请 / 启用 HTTPS
4) 查看系统状态
0) 退出
==================================
EOF
read -rp "请选择: " CHOICE

case "$CHOICE" in
  1) install_all ;;
  2) update_panel ;;
  3) apply_cert ;;
  4) status_check ;;
  0) exit ;;
  *) echo "无效选择"; pause ;;
esac
}

while true; do menu; done
