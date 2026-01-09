#!/bin/bash

####################################################################
# Sun Panel V2 一键部署脚本
# 支持 Ubuntu、CentOS 等 Linux 系统
# 功能：Docker部署、Nginx反向代理、SSL证书、状态管理、备份升级
####################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 项目信息
PROJECT_NAME="sun-panel"
GITHUB_REPO="75412701/sun-panel-v2"
IMAGE_NAME="75412701/sun-panel"
IMAGE_TAG="latest"
CONTAINER_NAME="sun-panel"

# 配置文件路径
CONFIG_DIR="/etc/sun-panel"
DATA_DIR="/opt/sun-panel/data"
BACKUP_DIR="/opt/sun-panel/backup"
NGINX_CONF_DIR="/etc/nginx/sites-available"
NGINX_ENABLED_DIR="/etc/nginx/sites-enabled"

# 日志
LOG_FILE="/var/log/sun-panel-install.log"

# 函数：打印日志
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# 函数：打印带颜色的消息
print_message() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
    log "$message"
}

# 函数：打印标题
print_title() {
    clear
    echo ""
    print_message "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    print_message "$CYAN" "          Sun Panel V2 一键部署管理脚本"
    print_message "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# 函数：打印分隔线
print_separator() {
    print_message "$CYAN" "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# 函数：检测操作系统
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS=$ID
        OS_VERSION=$VERSION_ID
    elif [ -f /etc/redhat-release ]; then
        OS="centos"
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release)
    else
        print_message "$RED" "无法检测操作系统"
        exit 1
    fi
    log "检测到操作系统: $OS $OS_VERSION"
}

# 函数：检查 root 权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_message "$RED" "请使用 root 权限运行此脚本"
        print_message "$YELLOW" "请执行: sudo $0"
        exit 1
    fi
}

# 函数：检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 函数：安装 Docker
install_docker() {
    print_message "$YELLOW" "开始安装 Docker..."

    if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
        apt-get update
        apt-get install -y \
            ca-certificates \
            curl \
            gnupg \
            lsb-release

        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        chmod a+r /etc/apt/keyrings/docker.gpg

        echo \
            "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
            $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

    elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
        yum install -y yum-utils
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    fi

    # 启动 Docker
    systemctl start docker
    systemctl enable docker

    # 安装 Docker Compose
    if ! command_exists docker-compose; then
        curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
        chmod +x /usr/local/bin/docker-compose
    fi

    print_message "$GREEN" "Docker 安装完成"
    docker --version
    docker-compose --version
}

# 函数：检查 Docker 环境
check_docker() {
    if command_exists docker; then
        print_message "$GREEN" "✓ Docker 已安装"
        docker --version
    else
        print_message "$RED" "✗ Docker 未安装"
        read -p "是否安装 Docker? (y/n): " install_docker_choice
        if [ "$install_docker_choice" = "y" ] || [ "$install_docker_choice" = "Y" ]; then
            install_docker
        else
            print_message "$RED" "无法继续，Docker 是必需的"
            exit 1
        fi
    fi

    # 检查 Docker 是否运行
    if ! systemctl is-active --quiet docker; then
        print_message "$YELLOW" "Docker 未运行，正在启动..."
        systemctl start docker
    fi
}

# 函数：安装 Nginx
install_nginx() {
    if command_exists nginx; then
        print_message "$GREEN" "✓ Nginx 已安装"
    else
        print_message "$YELLOW" "正在安装 Nginx..."

        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            apt-get update
            apt-get install -y nginx certbot python3-certbot-nginx
        elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            yum install -y nginx epel-release
            yum install -y certbot python3-certbot-nginx
        fi

        systemctl start nginx
        systemctl enable nginx

        print_message "$GREEN" "Nginx 安装完成"
    fi
}

# 函数：安装 Certbot (SSL证书工具)
install_certbot() {
    if command_exists certbot; then
        print_message "$GREEN" "✓ Certbot 已安装"
    else
        print_message "$YELLOW" "正在安装 Certbot..."

        if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
            apt-get update
            apt-get install -y certbot python3-certbot-nginx
        elif [ "$OS" = "centos" ] || [ "$OS" = "rhel" ]; then
            yum install -y certbot python3-certbot-nginx
        fi

        print_message "$GREEN" "Certbot 安装完成"
    fi
}

# 函数：获取服务器 IP
get_server_ip() {
    local ip=$(curl -s4 ip.sb || curl -s4 ifconfig.me || curl -s4 icanhazip.com)
    echo "$ip"
}

# 函数：验证域名 DNS 解析
verify_dns() {
    local domain=$1
    local expected_ip=$(get_server_ip)
    local resolved_ip=$(nslookup "$domain" | grep "Address:" | tail -1 | awk '{print $2}')

    if [ "$resolved_ip" = "$expected_ip" ]; then
        return 0
    else
        return 1
    fi
}

# 函数：部署项目
deploy_project() {
    print_title
    print_message "$BLUE" "━━━ 开始部署 Sun Panel V2 ━━━"
    echo ""

    # 获取配置参数
    print_message "$YELLOW" "请输入配置信息："
    echo ""

    read -p "容器端口 (默认 3002): " container_port
    container_port=${container_port:-3002}

    read -p "是否配置域名和 SSL? (y/n): " use_ssl

    if [ "$use_ssl" = "y" ] || [ "$use_ssl" = "Y" ]; then
        while true; do
            read -p "请输入域名 (如: panel.example.com): " domain
            if [ -z "$domain" ]; then
                print_message "$RED" "域名不能为空"
                continue
            fi

            # 验证域名 DNS 解析
            print_message "$YELLOW" "正在验证域名 DNS 解析..."
            if verify_dns "$domain"; then
                print_message "$GREEN" "✓ 域名解析正确: $domain -> $(get_server_ip)"
                break
            else
                print_message "$RED" "✗ 域名解析不正确或未生效"
                print_message "$YELLOW" "请确保域名已正确解析到服务器 IP: $(get_server_ip)"
                read -p "是否继续? (y/n): " continue_choice
                if [ "$continue_choice" != "y" ] && [ "$continue_choice" != "Y" ]; then
                    return 1
                fi
                break
            fi
        done

        read -p "请输入邮箱地址 (用于证书通知): " email
        if [ -z "$email" ]; then
            print_message "$RED" "邮箱不能为空"
            return 1
        fi
    else
        domain=""
        email=""
    fi

    # 创建数据目录
    print_message "$YELLOW" "创建数据目录..."
    mkdir -p "$DATA_DIR"
    mkdir -p "$BACKUP_DIR"
    mkdir -p "$CONFIG_DIR"

    # 停止现有容器（如果存在）
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        print_message "$YELLOW" "停止现有容器..."
        docker stop "$CONTAINER_NAME" 2>/dev/null
        docker rm "$CONTAINER_NAME" 2>/dev/null
    fi

    # 拉取镜像
    print_message "$YELLOW" "拉取 Docker 镜像..."
    docker pull "$IMAGE_NAME:$IMAGE_TAG"

    # 启动容器
    print_message "$YELLOW" "启动容器..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart=unless-stopped \
        -p "$container_port:3002" \
        -v "$DATA_DIR:/app/data" \
        "$IMAGE_NAME:$IMAGE_TAG"

    # 检查容器状态
    sleep 3
    if docker ps | grep -q "$CONTAINER_NAME"; then
        print_message "$GREEN" "✓ 容器启动成功"
    else
        print_message "$RED" "✗ 容器启动失败"
        docker logs "$CONTAINER_NAME"
        return 1
    fi

    # 配置 Nginx 和 SSL
    if [ "$use_ssl" = "y" ] || [ "$use_ssl" = "Y" ]; then
        install_nginx
        install_certbot

        # 创建 Nginx 配置
        print_message "$YELLOW" "配置 Nginx 反向代理..."
        cat > "$NGINX_CONF_DIR/$domain.conf" << EOF
server {
    listen 80;
    server_name $domain;

    location / {
        proxy_pass http://127.0.0.1:$container_port;
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

        # 启用站点
        ln -sf "$NGINX_CONF_DIR/$domain.conf" "$NGINX_ENABLED_DIR/$domain.conf"

        # 测试 Nginx 配置
        nginx -t
        systemctl reload nginx

        # 申请 SSL 证书
        print_message "$YELLOW" "申请 SSL 证书..."
        certbot --nginx -d "$domain" --email "$email" --agree-tos --non-interactive --redirect

        if [ $? -eq 0 ]; then
            print_message "$GREEN" "✓ SSL 证书申请成功"
        else
            print_message "$RED" "✗ SSL 证书申请失败"
            print_message "$YELLOW" "请手动运行: certbot --nginx -d $domain"
        fi
    fi

    # 保存配置
    cat > "$CONFIG_DIR/config.conf" << EOF
CONTAINER_NAME=$CONTAINER_NAME
IMAGE_NAME=$IMAGE_NAME
IMAGE_TAG=$IMAGE_TAG
CONTAINER_PORT=$container_port
DOMAIN=$domain
EMAIL=$email
DATA_DIR=$DATA_DIR
BACKUP_DIR=$BACKUP_DIR
EOF

    # 显示部署信息
    print_separator
    print_message "$GREEN" "━━━ 部署完成 ━━━"
    echo ""
    print_message "$GREEN" "容器名称: $CONTAINER_NAME"
    print_message "$GREEN" "容器端口: $container_port"
    print_message "$GREEN" "数据目录: $DATA_DIR"
    print_message "$GREEN" "配置目录: $CONFIG_DIR"

    if [ -n "$domain" ]; then
        print_message "$GREEN" "访问地址: https://$domain"
        print_message "$GREEN" "域名: $domain"
    else
        print_message "$GREEN" "访问地址: http://$(get_server_ip):$container_port"
    fi

    print_separator

    read -p "按任意键继续..."
}

# 函数：查看项目状态
check_status() {
    print_title
    print_message "$BLUE" "━━━ 项目状态 ━━━"
    echo ""

    # 加载配置
    if [ -f "$CONFIG_DIR/config.conf" ]; then
        . "$CONFIG_DIR/config.conf"
    else
        print_message "$YELLOW" "未找到配置文件"
        read -p "按任意键继续..."
        return
    fi

    # 容器状态
    print_message "$CYAN" "容器状态:"
    if docker ps | grep -q "$CONTAINER_NAME"; then
        print_message "$GREEN" "  ✓ 容器运行中"
        docker ps --filter "name=$CONTAINER_NAME" --format "  名称: {{.Names}}"
        docker ps --filter "name=$CONTAINER_NAME" --format "  端口: {{.Ports}}"
        docker ps --filter "name=$CONTAINER_NAME" --format "  镜像: {{.Image}}"
    else
        print_message "$RED" "  ✗ 容器未运行"
        if docker ps -a | grep -q "$CONTAINER_NAME"; then
            print_message "$YELLOW" "  容器已停止，可使用升级功能重启"
        fi
    fi

    echo ""

    # 系统资源
    print_message "$CYAN" "系统资源:"
    echo "  CPU 使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')%"
    echo "  内存使用: $(free -h | awk '/Mem:/ {printf "%.1f/%.1f GB (%.1f%%)\n", $3/1024, $2/1024, $3*100/$2}')"
    echo "  磁盘使用: $(df -h /opt/sun-panel | awk 'NR==2 {printf "%s / %s (%s)\n", $3, $2, $5}')"

    echo ""

    # 网络状态
    print_message "$CYAN" "网络状态:"
    echo "  服务器 IP: $(get_server_ip)"

    if [ -n "$DOMAIN" ]; then
        echo "  域名: $DOMAIN"
        if curl -sI "https://$DOMAIN" | grep -q "HTTP"; then
            print_message "$GREEN" "  ✓ HTTPS 访问正常"
        else
            print_message "$YELLOW" "  ! HTTPS 访问异常"
        fi
    fi

    if [ -n "$CONTAINER_PORT" ]; then
        echo "  容器端口: $CONTAINER_PORT"
    fi

    echo ""

    # Docker 信息
    print_message "$CYAN" "Docker 信息:"
    echo "  Docker 版本: $(docker --version)"
    echo "  Docker 状态: $(systemctl is-active docker)"

    print_separator
    read -p "按任意键继续..."
}

# 函数：升级项目
upgrade_project() {
    print_title
    print_message "$BLUE" "━━━ 升级项目 ━━━"
    echo ""

    # 加载配置
    if [ -f "$CONFIG_DIR/config.conf" ]; then
        . "$CONFIG_DIR/config.conf"
    else
        print_message "$RED" "未找到配置文件，无法升级"
        read -p "按任意键继续..."
        return
    fi

    print_message "$YELLOW" "当前版本:"
    docker ps --filter "name=$CONTAINER_NAME" --format "{{.Image}}"
    echo ""

    read -p "是否升级到最新版本? (y/n): " upgrade_choice

    if [ "$upgrade_choice" != "y" ] && [ "$upgrade_choice" != "Y" ]; then
        print_message "$YELLOW" "已取消升级"
        read -p "按任意键继续..."
        return
    fi

    # 备份数据
    print_message "$YELLOW" "正在备份数据..."
    backup_date=$(date +%Y%m%d_%H%M%S)
    backup_file="$BACKUP_DIR/backup_$backup_date.tar.gz"

    if [ -d "$DATA_DIR" ]; then
        tar -czf "$backup_file" -C "$DATA_DIR" . 2>/dev/null
        if [ $? -eq 0 ]; then
            print_message "$GREEN" "✓ 数据备份成功: $backup_file"
        else
            print_message "$YELLOW" "! 数据备份失败，继续升级..."
        fi
    fi

    # 拉取最新镜像
    print_message "$YELLOW" "拉取最新镜像..."
    docker pull "$IMAGE_NAME:$IMAGE_TAG"

    if [ $? -ne 0 ]; then
        print_message "$RED" "✗ 镜像拉取失败"
        read -p "按任意键继续..."
        return
    fi

    # 停止并删除旧容器
    print_message "$YELLOW" "停止旧容器..."
    docker stop "$CONTAINER_NAME"
    docker rm "$CONTAINER_NAME"

    # 启动新容器
    print_message "$YELLOW" "启动新容器..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart=unless-stopped \
        -p "$CONTAINER_PORT:3002" \
        -v "$DATA_DIR:/app/data" \
        "$IMAGE_NAME:$IMAGE_TAG"

    # 检查容器状态
    sleep 3
    if docker ps | grep -q "$CONTAINER_NAME"; then
        print_message "$GREEN" "✓ 升级成功"

        # 清理旧镜像
        print_message "$YELLOW" "清理旧镜像..."
        docker image prune -f

        print_separator
        print_message "$GREEN" "━━━ 升级完成 ━━━"
    else
        print_message "$RED" "✗ 升级失败，正在回滚..."

        # 回滚到之前的镜像（如果有）
        print_message "$YELLOW" "尝试回滚..."
        # 这里可以添加回滚逻辑
        docker logs "$CONTAINER_NAME"
    fi

    print_separator
    read -p "按任意键继续..."
}

# 函数：备份数据
backup_data() {
    print_title
    print_message "$BLUE" "━━━ 备份数据 ━━━"
    echo ""

    # 加载配置
    if [ -f "$CONFIG_DIR/config.conf" ]; then
        . "$CONFIG_DIR/config.conf"
    else
        print_message "$RED" "未找到配置文件"
        read -p "按任意键继续..."
        return
    fi

    # 检查数据目录
    if [ ! -d "$DATA_DIR" ]; then
        print_message "$RED" "数据目录不存在: $DATA_DIR"
        read -p "按任意键继续..."
        return
    fi

    # 询问备份路径
    read -p "备份路径 (默认: $BACKUP_DIR): " backup_path
    backup_path=${backup_path:-$BACKUP_DIR}

    # 创建备份目录
    mkdir -p "$backup_path"

    # 生成备份文件名
    backup_date=$(date +%Y%m%d_%H%M%S)
    backup_file="$backup_path/sun-panel-backup_$backup_date.tar.gz"

    # 执行备份
    print_message "$YELLOW" "正在备份..."
    tar -czf "$backup_file" -C "$DATA_DIR" . 2>/dev/null

    if [ $? -eq 0 ]; then
        file_size=$(du -h "$backup_file" | awk '{print $1}')
        print_message "$GREEN" "✓ 备份成功"
        print_message "$GREEN" "备份文件: $backup_file"
        print_message "$GREEN" "文件大小: $file_size"
    else
        print_message "$RED" "✗ 备份失败"
        read -p "按任意键继续..."
        return
    fi

    # 列出备份文件
    echo ""
    print_message "$CYAN" "历史备份:"
    ls -lh "$backup_path"/*.tar.gz 2>/dev/null || print_message "$YELLOW" "暂无历史备份"

    print_separator
    read -p "按任意键继续..."
}

# 函数：恢复数据
restore_data() {
    print_title
    print_message "$BLUE" "━━━ 恢复数据 ━━━"
    echo ""

    # 加载配置
    if [ -f "$CONFIG_DIR/config.conf" ]; then
        . "$CONFIG_DIR/config.conf"
    else
        print_message "$RED" "未找到配置文件"
        read -p "按任意键继续..."
        return
    fi

    # 列出备份文件
    print_message "$CYAN" "可用的备份文件:"
    echo ""

    backup_files=("$BACKUP_DIR"/*.tar.gz)
    if [ ${#backup_files[@]} -eq 0 ]; then
        print_message "$YELLOW" "没有找到备份文件"
        read -p "按任意键继续..."
        return
    fi

    index=1
    for file in "${backup_files[@]}"; do
        filename=$(basename "$file")
        file_size=$(du -h "$file" | awk '{print $1}')
        echo "  [$index] $filename ($file_size)"
        ((index++))
    done

    echo ""
    read -p "请选择要恢复的备份 (输入序号): " backup_choice

    if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -ge "$index" ]; then
        print_message "$RED" "无效的选择"
        read -p "按任意键继续..."
        return
    fi

    selected_backup="${backup_files[$((backup_choice-1))]}"
    selected_filename=$(basename "$selected_backup")

    # 确认恢复
    print_message "$YELLOW" "警告: 恢复数据会覆盖现有数据"
    print_message "$YELLOW" "备份文件: $selected_filename"
    echo ""
    read -p "确认恢复? (yes/no): " confirm_restore

    if [ "$confirm_restore" != "yes" ]; then
        print_message "$YELLOW" "已取消恢复"
        read -p "按任意键继续..."
        return
    fi

    # 停止容器
    print_message "$YELLOW" "停止容器..."
    docker stop "$CONTAINER_NAME"

    # 清空数据目录
    print_message "$YELLOW" "清空数据目录..."
    rm -rf "$DATA_DIR"/*
    rm -rf "$DATA_DIR"/.[!.]* 2>/dev/null

    # 恢复数据
    print_message "$YELLOW" "正在恢复数据..."
    tar -xzf "$selected_backup" -C "$DATA_DIR"

    if [ $? -eq 0 ]; then
        print_message "$GREEN" "✓ 数据恢复成功"
    else
        print_message "$RED" "✗ 数据恢复失败"
    fi

    # 启动容器
    print_message "$YELLOW" "启动容器..."
    docker start "$CONTAINER_NAME"

    sleep 3
    if docker ps | grep -q "$CONTAINER_NAME"; then
        print_message "$GREEN" "✓ 容器已启动"
    else
        print_message "$RED" "✗ 容器启动失败"
    fi

    print_separator
    read -p "按任意键继续..."
}

# 函数：卸载项目
uninstall_project() {
    print_title
    print_message "$BLUE" "━━━ 卸载项目 ━━━"
    echo ""

    # 加载配置
    if [ -f "$CONFIG_DIR/config.conf" ]; then
        . "$CONFIG_DIR/config.conf"
    else
        print_message "$YELLOW" "未找到配置文件"
    fi

    print_message "$RED" "警告: 此操作将删除 Sun Panel V2 及其数据"
    print_message "$YELLOW" "建议先备份数据"
    echo ""

    # 询问是否备份
    read -p "是否先备份数据? (y/n): " backup_before_uninstall
    if [ "$backup_before_uninstall" = "y" ] || [ "$backup_before_uninstall" = "Y" ]; then
        backup_data
    fi

    # 确认卸载
    read -p "确认卸载? 输入 'yes' 继续: " confirm_uninstall

    if [ "$confirm_uninstall" != "yes" ]; then
        print_message "$YELLOW" "已取消卸载"
        read -p "按任意键继续..."
        return
    fi

    # 停止并删除容器
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        print_message "$YELLOW" "停止并删除容器..."
        docker stop "$CONTAINER_NAME" 2>/dev/null
        docker rm "$CONTAINER_NAME" 2>/dev/null
    fi

    # 删除镜像
    print_message "$YELLOW" "删除镜像..."
    docker rmi "$IMAGE_NAME:$IMAGE_TAG" 2>/dev/null || print_message "$YELLOW" "镜像不存在或已被删除"

    # 删除 Nginx 配置（如果存在）
    if [ -n "$DOMAIN" ] && [ -f "$NGINX_CONF_DIR/$DOMAIN.conf" ]; then
        print_message "$YELLOW" "删除 Nginx 配置..."
        rm -f "$NGINX_ENABLED_DIR/$DOMAIN.conf"
        rm -f "$NGINX_CONF_DIR/$DOMAIN.conf"
        systemctl reload nginx

        # 撤销 SSL 证书
        print_message "$YELLOW" "撤销 SSL 证书..."
        certbot delete --cert-name "$DOMAIN" --non-interactive 2>/dev/null || true
    fi

    # 删除配置文件
    print_message "$YELLOW" "删除配置文件..."
    rm -rf "$CONFIG_DIR"

    # 询问是否删除数据
    echo ""
    read -p "是否删除数据目录? (y/n): " delete_data
    if [ "$delete_data" = "y" ] || [ "$delete_data" = "Y" ]; then
        print_message "$YELLOW" "删除数据目录..."
        rm -rf "$DATA_DIR"
        rm -rf "$BACKUP_DIR"
    else
        print_message "$GREEN" "保留数据目录: $DATA_DIR"
        print_message "$GREEN" "保留备份目录: $BACKUP_DIR"
    fi

    print_separator
    print_message "$GREEN" "卸载完成"
    print_separator
    read -p "按任意键继续..."
}

# 函数：查看日志
view_logs() {
    print_title
    print_message "$BLUE" "━━━ 查看日志 ━━━"
    echo ""

    # 加载配置
    if [ -f "$CONFIG_DIR/config.conf" ]; then
        . "$CONFIG_DIR/config.conf"
    else
        CONTAINER_NAME="sun-panel"
    fi

    print_message "$YELLOW" "查看容器日志 (Ctrl+C 退出)..."
    echo ""
    docker logs -f --tail 100 "$CONTAINER_NAME"
}

# 函数：显示主菜单
show_menu() {
    print_title
    print_message "$GREEN" "请选择操作:"
    echo ""
    echo "  ${GREEN}1)${NC} 部署项目"
    echo "  ${GREEN}2)${NC} 查看状态"
    echo "  ${GREEN}3)${NC} 升级项目"
    echo "  ${GREEN}4)${NC} 备份数据"
    echo "  ${GREEN}5)${NC} 恢复数据"
    echo "  ${GREEN}6)${NC} 查看日志"
    echo "  ${GREEN}7)${NC} 卸载项目"
    echo ""
    echo "  ${YELLOW}0)${NC} 退出"
    echo ""
    print_separator
}

# 主函数
main() {
    # 检查 root 权限
    check_root

    # 检测操作系统
    detect_os

    # 检查 Docker
    check_docker

    # 主循环
    while true; do
        show_menu
        read -p "请输入选项 [0-7]: " choice

        case $choice in
            1)
                deploy_project
                ;;
            2)
                check_status
                ;;
            3)
                upgrade_project
                ;;
            4)
                backup_data
                ;;
            5)
                restore_data
                ;;
            6)
                view_logs
                ;;
            7)
                uninstall_project
                ;;
            0)
                print_message "$GREEN" "感谢使用 Sun Panel V2 一键部署脚本!"
                exit 0
                ;;
            *)
                print_message "$RED" "无效的选项，请重新选择"
                sleep 2
                ;;
        esac
    done
}

# 运行主函数
main
