#!/bin/bash
# =====================================================
# sun-panel-v2 菜单式一键部署脚本 v1.2.4
# 稳定增强版（容器启动 + 非阻塞 HTTPS）
# =====================================================

BASE_DIR="/opt/sun-panel-v2"
DB_FILE="$BASE_DIR/database/database.db"
BACKUP_DIR="$BASE_DIR/backup"
WEBROOT="/var/www/html"

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
  apt install -y curl wget nginx ca-certificates gnupg lsb-release \
                 certbot python3-certbot-nginx

  if ! command -v docker &>/dev/null; then
    echo -e "${YELLOW}▶ 安装 Docker${RESET}"
    curl -fsSL https://get.docker.com | bash
  fi

  systemctl enable docker nginx
  systemctl start docker nginx
}

fix_permissions(){
  echo -e "${YELLOW}▶ 修复挂载目录权限${RESET}"
  mkdir -p "$BASE_DIR"/{conf,uploads,database,backup}
  sudo chown -R $USER:$USER "$BASE_DIR"
  sudo chmod -R 755 "$BASE_DIR"
  mkdir -p "$WEBROOT"
}

install_sunpanel(){
  read -p "请输入访问域名: " DOMAIN
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
}
EOF

  if nginx -t; then
    systemctl reload nginx
    echo -e "${GREEN}✔ Nginx HTTP 配置完成${RESET}"
  else
    echo -e "${RED}⚠️ Nginx 配置失败，请检查${RESET}"
  fi

  echo -e "${YELLOW}▶ 部署完成（HTTP 可先访问）${RESET}"
  echo -e "${GREEN}✔ 面板访问地址: http://$DOMAIN 或 http://服务器IP:3002${RESET}"
  echo -e "${YELLOW}⚠️ HTTPS 证书未申请，需单独执行 certbot 或使用菜单申请${RESET}"
  echo -e "${YELLOW}▶ 查看容器日志: docker compose logs -f${RESET}"
}

start_service(){ cd $BASE_DIR && docker compose up -d && echo -e "${GREEN}✔ 服务已启动${RESET}"; }
stop_service(){ cd $BASE_DIR && docker compose down && echo -e "${YELLOW}✔ 服务已停止${RESET}"; }
restart_service(){ cd $BASE_DIR && docker compose restart && echo -e "${GREEN}✔ 服务已重启${RESET}"; }
update_service(){ cd $BASE_DIR && docker compose pull && docker compose up -d && echo -e "${GREEN}✔ 更新完成（数据保留）${RESET}"; }

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

menu(){
  clear
  echo "=================================="
  echo " sun-panel 管理脚本 v1.2.4"
  echo "=================================="
  echo "1) 一键安装 sun-panel"
  echo "2) 启动服务"
  echo "3) 停止服务"
  echo "4) 重启服务"
  echo "5) 更新 sun-panel"
  echo "6) 备份数据库"
  echo "7) 恢复数据库"
  echo "8) 卸载 sun-panel"
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
    0) exit 0 ;;
    *) echo "无效选择" ;;
  esac
  pause
done
