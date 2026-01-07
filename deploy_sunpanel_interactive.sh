#!/bin/bash
set -e

# ===============================
# Sun-Panel-v2 v1.0 交互式部署脚本
# ===============================

# ---------- 基础 ----------
if [ "$EUID" -ne 0 ]; then
  echo "[ERROR] 请使用 root 用户运行（sudo -i）"
  exit 1
fi

echo "======================================"
echo " Sun-Panel-v2 一键部署（v1.0 稳定版）"
echo "======================================"
echo

# ---------- 交互输入 ----------
read -p "请输入域名 (如 panel.example.com): " DOMAIN
[ -z "$DOMAIN" ] && { echo "域名不能为空"; exit 1; }

read -p "请输入邮箱 (用于 HTTPS 证书): " EMAIL
[ -z "$EMAIL" ] && { echo "邮箱不能为空"; exit 1; }

read -p "部署目录 (默认 /opt/sun-panel-v2): " BASE_DIR
BASE_DIR=${BASE_DIR:-/opt/sun-panel-v2}

read -p "是否启用数据库每日备份? [Y/n]: " ENABLE_BACKUP
ENABLE_BACKUP=${ENABLE_BACKUP:-Y}

if [[ "$ENABLE_BACKUP" =~ ^[Yy]$ ]]; then
  read -p "备份保留天数 (默认 7): " BACKUP_DAYS
  BACKUP_DAYS=${BACKUP_DAYS:-7}

  read -p "每日备份时间 (HH:MM，默认 02:00): " BACKUP_TIME
  BACKUP_TIME=${BACKUP_TIME:-02:00}

  BACKUP_HOUR=${BACKUP_TIME%:*}
  BACKUP_MIN=${BACKUP_TIME#*:}
fi

echo
echo "========= 配置确认 ========="
echo "域名:        $DOMAIN"
echo "邮箱:        $EMAIL"
echo "部署目录:    $BASE_DIR"
echo "数据库备份:  $ENABLE_BACKUP"
if [[ "$ENABLE_BACKUP" =~ ^[Yy]$ ]]; then
  echo "备份时间:    $BACKUP_TIME"
  echo "保留天数:    $BACKUP_DAYS"
fi
echo "============================"
read -p "确认开始部署? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
[[ ! "$CONFIRM" =~ ^[Yy]$ ]] && exit 0

# ---------- Docker ----------
if ! command -v docker >/dev/null; then
  echo "[INFO] 安装 Docker..."
  curl -fsSL https://get.docker.com | sh
  systemctl enable docker
  systemctl start docker
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "[INFO] 安装 Docker Compose v2..."
  mkdir -p /usr/local/lib/docker/cli-plugins
  curl -SL https://github.com/docker/compose/releases/download/v2.27.0/docker-compose-linux-x86_64 \
    -o /usr/local/lib/docker/cli-plugins/docker-compose
  chmod +x /usr/local/lib/docker/cli-plugins/docker-compose
fi

# ---------- Nginx + Certbot ----------
apt update
apt install -y nginx certbot python3-certbot-nginx

# ---------- 目录 ----------
mkdir -p "$BASE_DIR"/{conf,uploads,database,backup}
cd "$BASE_DIR"

# ---------- docker-compose ----------
cat > docker-compose.yml <<EOF
version: "3.8"
services:
  sun-panel:
    image: ghcr.io/75412701/sun-panel-v2:latest
    container_name: sun-panel-v2
    volumes:
      - ./conf:/app/conf
      - ./uploads:/app/uploads
      - ./database:/app/database
    expose:
      - "3002"
    restart: always
EOF

# ---------- Nginx ----------
cat > /etc/nginx/sites-available/sun-panel.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF

ln -sf /etc/nginx/sites-available/sun-panel.conf /etc/nginx/sites-enabled/
nginx -t && systemctl reload nginx

# ---------- HTTPS ----------
certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --non-interactive --redirect

# ---------- 启动 ----------
docker compose up -d

# ---------- 数据库备份 ----------
if [[ "$ENABLE_BACKUP" =~ ^[Yy]$ ]]; then
cat > /usr/local/bin/sunpanel_backup.sh <<EOF
#!/bin/bash
BASE_DIR="$BASE_DIR"
BACKUP_DIR="\$BASE_DIR/backup"
DB_DIR="\$BASE_DIR/database"
DATE=\$(date +%F_%H-%M)

mkdir -p "\$BACKUP_DIR"
tar czf "\$BACKUP_DIR/db_\$DATE.tar.gz" -C "\$DB_DIR" .
find "\$BACKUP_DIR" -type f -mtime +$BACKUP_DAYS -delete
EOF

chmod +x /usr/local/bin/sunpanel_backup.sh
(crontab -l 2>/dev/null; echo "$BACKUP_MIN $BACKUP_HOUR * * * /usr/local/bin/sunpanel_backup.sh") | crontab -
fi

echo
echo "======================================"
echo " 🎉 部署完成（v1.0 稳定版）"
echo "--------------------------------------"
echo "访问地址: https://$DOMAIN"
echo "首次访问需创建管理员账号"
echo "部署目录: $BASE_DIR"
echo "======================================"
