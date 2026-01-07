#!/bin/bash
# ===============================================
# 交互式 GitHub-ready 一键部署 sun-panel-v2 + Nginx + HTTPS + Docker
# 支持数据库每日备份保留设置
# ===============================================

echo "===== 欢迎使用 sun-panel-v2 一键部署脚本 ====="

# -------------------------------
# 1. 基础信息输入
# -------------------------------
read -p "请输入你的域名 (例如 panel.example.com): " DOMAIN
DOMAIN=${DOMAIN:-"panel.example.com"}

read -p "请输入你的邮箱 (用于 HTTPS 证书): " EMAIL
EMAIL=${EMAIL:-"youremail@example.com"}

read -p "请输入部署目录 (默认 $HOME/sun-panel-v2): " BASE_DIR
BASE_DIR=${BASE_DIR:-"$HOME/sun-panel-v2"}

BACKUP_DIR="$BASE_DIR/backup"

# -------------------------------
# 2. Docker 检测与安装
# -------------------------------
if ! command -v docker &> /dev/null; then
    read -p "检测到未安装 Docker，是否自动安装 Docker? [Y/n]: " INSTALL_DOCKER
    INSTALL_DOCKER=${INSTALL_DOCKER:-Y}
    if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
        echo "🚀 开始安装 Docker ..."
        sudo apt update
        sudo apt install -y ca-certificates curl gnupg lsb-release
        sudo mkdir -p /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt update
        sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        echo "✅ Docker 安装完成"
    else
        echo "请先手动安装 Docker 后再执行脚本"
        exit 1
    fi
else
    echo "✅ Docker 已安装"
fi

# Docker Compose 检查
if ! docker compose version &> /dev/null; then
    echo "⚠️ Docker Compose 未安装，请确认 Docker v2 插件安装成功"
else
    echo "✅ Docker Compose 已安装"
fi

# 添加当前用户到 docker 组
if ! groups $USER | grep -q "\bdocker\b"; then
    sudo usermod -aG docker $USER
    echo "⚠️ 用户已加入 docker 组，请重新登录或执行 'newgrp docker'"
fi

# -------------------------------
# 3. 数据库备份配置
# -------------------------------
read -p "是否启用每日数据库备份? [Y/n]: " ENABLE_BACKUP
ENABLE_BACKUP=${ENABLE_BACKUP:-Y}

if [[ "$ENABLE_BACKUP" =~ ^[Yy]$ ]]; then
    read -p "备份保留天数 (默认 7 天): " BACKUP_DAYS
    BACKUP_DAYS=${BACKUP_DAYS:-7}

    read -p "每日备份时间 (默认 02:00): " BACKUP_TIME
    BACKUP_TIME=${BACKUP_TIME:-02:00}

    echo "✅ 数据库备份配置:"
    echo "每日备份时间: $BACKUP_TIME"
    echo "备份保留天数: $BACKUP_DAYS"
fi

# -------------------------------
# 4. 确认部署信息
# -------------------------------
echo "=============================="
echo "部署信息确认:"
echo "域名: $DOMAIN"
echo "邮箱: $EMAIL"
echo "目录: $BASE_DIR"
echo "每日备份: $ENABLE_BACKUP"
if [[ "$ENABLE_BACKUP" =~ ^[Yy]$ ]]; then
    echo "备份时间: $BACKUP_TIME"
    echo "备份保留天数: $BACKUP_DAYS"
fi
echo "=============================="
read -p "确认无误，开始部署? [Y/n]: " CONFIRM
CONFIRM=${CONFIRM:-Y}
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo "部署已取消"
    exit 0
fi

# -------------------------------
# 5. 创建目录结构
# -------------------------------
mkdir -p "$BASE_DIR/conf"
mkdir -p "$BASE_DIR/uploads"
mkdir -p "$BASE_DIR/nginx/conf.d"
mkdir -p "$BASE_DIR/nginx/certs"
mkdir -p "$BASE_DIR/nginx/certbot"
mkdir -p "$BACKUP_DIR"

# -------------------------------
# 6. 生成 docker-compose.yml
# -------------------------------
cat > "$BASE_DIR/docker-compose.yml" <<EOF
version: "3.8"

services:
  sun-panel:
    image: ghcr.io/75412701/sun-panel-v2:latest
    container_name: sun-panel-v2
    networks:
      - internal
    volumes:
      - ./conf:/app/conf
      - ./uploads:/app/uploads
    restart: always

  nginx:
    image: nginx:latest
    container_name: nginx-proxy
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d
      - ./nginx/certs:/etc/letsencrypt/live
      - ./nginx/certbot:/var/www/certbot
    depends_on:
      - sun-panel
    restart: always
    networks:
      - internal
      - default

  certbot:
    image: certbot/certbot
    container_name: certbot
    volumes:
      - ./nginx/certs:/etc/letsencrypt/live
      - ./nginx/certbot:/var/www/certbot
    entrypoint: /bin/sh -c
    command: >
      "trap exit TERM;
       while :; do
         certbot renew --webroot -w /var/www/certbot --quiet;
         sleep 12h & wait \$\$!;
       done"
    networks:
      - default

networks:
  internal:
    driver: bridge
EOF

# -------------------------------
# 7. 生成 Nginx 配置
# -------------------------------
cat > "$BASE_DIR/nginx/conf.d/sun-panel.conf" <<EOF
server {
    listen 80;
    server_name $DOMAIN;
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
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
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;

    location / {
        proxy_pass http://sun-panel:3002;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

# -------------------------------
# 8. 获取 Let’s Encrypt 证书
# -------------------------------
echo "🔑 获取 Let’s Encrypt 证书..."
docker run -it --rm \
  -v "$BASE_DIR/nginx/certs:/etc/letsencrypt/live" \
  -v "$BASE_DIR/nginx/certbot:/var/www/certbot" \
  certbot/certbot certonly \
  --webroot -w /var/www/certbot \
  -d "$DOMAIN" --email "$EMAIL" --agree-tos --no-eff-email

# -------------------------------
# 9. 启动容器
# -------------------------------
cd "$BASE_DIR"
docker compose up -d

# -------------------------------
# 10. 配置数据库每日备份
# -------------------------------
if [[ "$ENABLE_BACKUP" =~ ^[Yy]$ ]]; then
BACKUP_SCRIPT="$BASE_DIR/backup_db.sh"
cat > "$BACKUP_SCRIPT" <<EOF
#!/bin/bash
DB_FILE="$BASE_DIR/conf/database/database.db"
BACKUP_DIR="$BACKUP_DIR"
if [ -f "\$DB_FILE" ]; then
    cp "\$DB_FILE" "\$BACKUP_DIR/database_\$(date +%Y%m%d_%H%M%S).db"
    find "\$BACKUP_DIR" -type f -name "database_*.db" -mtime +$BACKUP_DAYS -exec rm {} \;
fi
EOF
chmod +x "$BACKUP_SCRIPT"
(crontab -l 2>/dev/null; echo "$BACKUP_TIME * * * $BACKUP_SCRIPT") | crontab -
fi

echo "🎉 部署完成！"
echo "✅ HTTPS 面板已启动: https://$DOMAIN"
if [[ "$ENABLE_BACKUP" =~ ^[Yy]$ ]]; then
    echo "✅ 数据库每日备份已配置，保留最近 $BACKUP_DAYS 天"
fi
echo "⚠️ 第一次访问面板会提示创建管理员账号"
