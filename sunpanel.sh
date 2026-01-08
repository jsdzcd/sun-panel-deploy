#!/bin/bash
# =====================================================
# Sun-Panel-v2 菜单式一键部署脚本 v1.2.6
# =====================================================

BASE_DIR="/opt/sun-panel-v2"
DB_FILE="$BASE_DIR/conf/database/database.db"
BACKUP_DIR="$BASE_DIR/backup"
WEBROOT="$BASE_DIR/nginx/certbot"

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

pause(){ read -p "按 Enter 键继续..." ; }

check_root(){
  if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}请使用 root 用户运行${RESET}"
    exit 1
  fi
}

install_env(){
  echo -e "${YELLOW}▶ 安装系统依赖${RESET}"
  apt update
  apt install -y curl wget nginx ca-certificates gnupg lsb-release software-properties-common

  if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}▶ 安装 Docker${RESET}"
    curl -fsSL https://get.docker.com | bash
  fi

  systemctl enable docker nginx
  systemctl start docker nginx
}

fix_permissions(){
  echo -e "${YELLOW}▶ 修复挂载目录权限${RESET}"
  mkdir -p "$BASE_DIR"/{conf,uploads,database,backup,nginx/certs,nginx/certbot,nginx/conf.d}
  chown -R $USER:$USER "$BASE_DIR"
  chmod -R 755 "$BASE_DIR"
  mkdir -p "$WEBROOT"
}

install_sunpanel(){
  read -p "请输入访问域名 (如 panel.example.com): " DOMAIN
  read -p "请输入邮箱 (证书使用，可稍后申请): " EMAIL

  install_env
  fix_permissions

  echo -e "${YELLOW}▶ 创建 docker-compose.yml${RESET}"
cat > $BASE_DIR/docker-compose.yml <<EOF
services:
  sun-panel:
    image: ghcr.io/75412701/sun-panel-v2:latest
    container_name: sun-panel-v2
    restart: always
    ports:
      - "127.0.0.1:3002:3002"
    volumes:
      - ./conf:/app/conf
      - ./uploads:/app/uploads
      - ./database:/app/database
EOF

  cd $BASE_DIR
  echo -e "${YELLOW}▶ 启动容器（后台）${RESET}"
  docker compose up -d

  echo -e "${YELLOW}▶ 配置 Nginx HTTP${RESET}"
cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host \$host;
    }

    location /.well-known/acme-challenge/ {
        root $WEBROOT;
    }
}
EOF

  if nginx -t; then
    systemctl reload nginx
    echo -e "${GREEN}✔ Nginx HTTP 配置完成${RESET}"
  else
    echo -e "${RED}⚠️ Nginx 配置失败，请检查${RESET}"
  fi

  echo -e "${GREEN}✔ 部署完成（HTTP 可先访问）${RESET}"
  echo -e "面板访问地址: http://$DOMAIN 或 http://服务器IP:3002"
  echo -e "⚠️ HTTPS 证书未申请，可使用菜单申请"
  echo -e "▶ 查看容器日志: docker compose logs -f"
}

start_service(){ cd $BASE_DIR && docker compose up -d && echo -e "${GREEN}✔ 服务已启动${RESET}"; }
stop_service(){ cd $BASE_DIR && docker compose down && echo -e "${YELLOW}✔ 服务已停止${RESET}"; }
restart_service(){ cd $BASE_DIR && docker compose restart && echo -e "${GREEN}✔ 服务已重启${RESET}"; }

update_service(){
  cd $BASE_DIR
  echo -e "${YELLOW}▶ 拉取最新镜像${RESET}"
  docker compose pull
  echo -e "${YELLOW}▶ 停止旧容器并启动最新版本${RESET}"
  docker compose up -d
  echo -e "${GREEN}✔ 更新完成（数据保留）${RESET}"
  echo -e "▶ 查看容器日志: docker compose logs -f"
}

backup_db(){
  mkdir -p $BACKUP_DIR
  [[ -f "$DB_FILE" ]] && cp "$DB_FILE" "$BACKUP_DIR/db_$(date +%F_%H-%M-%S).db" && echo -e "${GREEN}✔ 数据库已备份${RESET}" || echo -e "${RED}未找到数据库文件${RESET}"
}

restore_db(){
  [[ ! -d "$BACKUP_DIR" ]] && { echo -e "${RED}未找到备份目录${RESET}"; return; }
  echo "可用备份:"; ls $BACKUP_DIR
  read -p "输入要恢复的文件名: " FILE
  [[ -f "$BACKUP_DIR/$FILE" ]] && cp "$BACKUP_DIR/$FILE" "$DB_FILE" && docker compose restart && echo -e "${GREEN}✔ 数据库已恢复${RESET}" || echo -e "${RED}备份文件不存在${RESET}"
}

uninstall_all(){
  read -p "⚠️ 确认彻底卸载? [y/N]: " OK
  [[ "$OK" =~ ^[Yy]$ ]] || return
  docker compose down
  rm -rf $BASE_DIR
  rm -f /etc/nginx/conf.d/sun-panel.conf
  systemctl reload nginx
  echo -e "${RED}✔ 已卸载${RESET}"
}

request_https(){
  echo "请选择证书申请方式:"
  echo "1) Webroot (HTTP 验证)"
  echo "2) DNS 验证 (Cloudflare / Aliyun 等)"
  echo "3) Let's Encrypt 官方方式 (自动 Nginx 配置)"
  echo "0) 取消"
  read -p "选择: " METHOD

  read -p "请输入域名: " DOMAIN
  read -p "请输入邮箱: " EMAIL

  case $METHOD in
    1)
      echo "▶ 使用 Webroot 方式申请证书..."
      docker run -it --rm \
        -v "$BASE_DIR/nginx/certs:/etc/letsencrypt/live" \
        -v "$WEBROOT:$WEBROOT" \
        certbot/certbot certonly \
        --webroot -w $WEBROOT \
        -d "$DOMAIN" \
        --email "$EMAIL" --agree-tos --no-eff-email
      ;;
    2)
      CF_INI="$BASE_DIR/certbot/cloudflare.ini"
      if [[ ! -f "$CF_INI" ]]; then
        echo -e "${RED}⚠️ Cloudflare API 凭证文件不存在！请创建 $CF_INI 并填写 API TOKEN${RESET}"
        echo "示例内容："
        echo "dns_cloudflare_api_token = 你的_API_TOKEN"
        return
      fi
      echo "▶ 使用 DNS 方式申请证书..."
      docker run -it --rm \
        -v "$BASE_DIR/nginx/certs:/etc/letsencrypt/live" \
        -v "$WEBROOT:$WEBROOT" \
        -v "$CF_INI:/cloudflare.ini:ro" \
        certbot/dns-cloudflare certonly \
        --dns-cloudflare \
        --dns-cloudflare-credentials /cloudflare.ini \
        -d "$DOMAIN" \
        --email "$EMAIL" --agree-tos --no-eff-email
      ;;
    3)
      echo "▶ 使用 Let's Encrypt 官方方式申请证书..."
      docker run -it --rm \
        -v "$BASE_DIR/nginx/certs:/etc/letsencrypt/live" \
        -v "$WEBROOT:$WEBROOT" \
        -v "/etc/nginx:/etc/nginx" \
        certbot/certbot run \
        --nginx \
        -d "$DOMAIN" \
        --email "$EMAIL" --agree-tos --no-eff-email
      ;;
    0)
      echo "取消申请"
      return
      ;;
    *)
      echo "无效选择"
      return
      ;;
  esac

  echo "▶ 测试 Nginx 配置并重载..."
  if nginx -t; then
    systemctl reload nginx
    echo -e "${GREEN}✔ HTTPS 证书申请完成${RESET}"
  else
    echo -e "${RED}⚠️ Nginx 配置测试失败，请检查证书和配置文件${RESET}"
  fi
}

check_status(){
  echo "==================== 系统状态检测 ===================="
  # Docker 服务状态
  if systemctl is-active --quiet docker; then
    echo -e "Docker 服务状态: ${GREEN}运行${RESET}"
  else
    echo -e "Docker 服务状态: ${RED}未运行${RESET}"
  fi

  # Sun-Panel 容器状态
  if docker ps --format '{{.Names}}' | grep -q "sun-panel-v2"; then
    echo -e "Sun-Panel 容器: ${GREEN}运行${RESET}"
  else
    echo -e "Sun-Panel 容器: ${RED}未运行${RESET}"
  fi

  # Nginx 服务状态
  if systemctl is-active --quiet nginx; then
    echo -e "Nginx 服务: ${GREEN}运行${RESET}"
  else
    echo -e "Nginx 服务: ${RED}未运行${RESET}"
  fi

  # HTTP 面板访问
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:3002 || echo "000")
  if [[ "$HTTP_STATUS" == "200" ]]; then
    echo -e "HTTP 面板访问: ${GREEN}可访问${RESET}"
  else
    echo -e "HTTP 面板访问: ${RED}不可访问${RESET}"
  fi

  # HTTPS 证书检测
  CERT_FILE=$(find "$BASE_DIR/nginx/certs" -name "fullchain.pem" | head -n1)
  if [[ -f "$CERT_FILE" ]]; then
    if openssl x509 -checkend 86400 -noout -in "$CERT_FILE"; then
      echo -e "HTTPS 证书: ${GREEN}已申请并有效${RESET}"
    else
      echo -e "HTTPS 证书: ${YELLOW}已申请但即将过期${RESET}"
    fi
  else
    echo -e "HTTPS 证书: ${RED}未申请${RESET}"
  fi
  echo "======================================================"
}

menu(){
  clear
  echo "=================================="
  echo " Sun-Panel 管理脚本 v1.2.6"
  echo "=================================="
  echo "1) 一键安装 Sun-Panel"
  echo "2) 启动服务"
  echo "3) 停止服务"
  echo "4) 重启服务"
  echo "5) 更新 Sun-Panel"
  echo "6) 备份数据库"
  echo "7) 恢复数据库"
  echo "8) 卸载 Sun-Panel"
  echo "9) 申请/更新 HTTPS 证书"
  echo "10) 查看系统状态"
  echo "0) 退出"
  echo "=================================="
}

check_root
while true; do
  menu
  read -p "请选择: " NUM
  case $NUM in
    1) install_sunpanel ;;
    2) start_service ;;
    3) stop_service ;;
    4) restart_service ;;
    5) update_service ;;
    6) backup_db ;;
    7) restore_db ;;
    8) uninstall_all ;;
    9) request_https ;;
    10) check_status ;;
    0) exit 0 ;;
    *) echo "无效选择" ;;
  esac
  pause
done
