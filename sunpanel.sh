#!/bin/bash
# =====================================================
# sun-panel-v2 一键部署脚本 v1.1（稳定修复版）
# 架构：宿主机 Nginx + Docker sun-panel
# =====================================================

set -e

echo "======================================"
echo " sun-panel-v2 一键部署脚本 v1.1 稳定版"
echo "======================================"

# -------------------------------
# 1. 用户输入
# -------------------------------
read -p "请输入访问域名 (如 panel.example.com): " DOMAIN
read -p "请输入邮箱 (用于 HTTPS 证书): " EMAIL
BASE_DIR="/opt/sun-panel-v2"

echo "安装目录: $BASE_DIR"
read -p "确认继续? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 0

# -------------------------------
# 2. 安装依赖
# -------------------------------
apt update
apt install -y curl wget git nginx ca-certificates gnupg lsb-release

# Docker
if ! command -v docker &>/dev/null; then
  curl -fsSL https://get.docker.com | bash
fi

systemctl enable docker
systemctl start docker

# Docker Compose
docker compose version >/dev/null 2>&1 || {
  echo "❌ Docker Compose 不可用"
  exit 1
}

# -------------------------------
# 3. 目录结构
# -------------------------------
mkdir -p $BASE_DIR/{conf,uploads,database}

# -------------------------------
# 4. docker-compose.yml（关键修复）
# -------------------------------
cat > $BASE_DIR/docker-compose.yml <<EOF
version: "3.8"

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

# -------------------------------
# 5. 启动容器
# -------------------------------
cd $BASE_DIR
docker compose up -d

sleep 5

# -------------------------------
# 6. 配置 Nginx
# -------------------------------
cat > /etc/nginx/conf.d/sun-panel.conf <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/html;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;

    location / {
        proxy_pass http://127.0.0.1:3002;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
EOF

nginx -t && systemctl reload nginx

# -------------------------------
# 7. HTTPS 证书
# -------------------------------
apt install -y certbot python3-certbot-nginx

certbot --nginx -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email

# -------------------------------
# 8. 最终检查
# -------------------------------
echo
echo "======================================"
echo "🎉 部署完成（v1.1 稳定版）"
echo "访问地址: https://$DOMAIN"
echo "======================================"
echo "首次访问请创建管理员账号"
