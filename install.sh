#!/bin/bash

#================================================================
#   System Required: CentOS 7+/Ubuntu 18+/Debian 10+
#   Description: Sun-Panel 一键安装脚本
#   Author: 小宝弟
#   Github: https://github.com/hslr-s/sun-panel
#================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 版本信息
SCRIPT_VERSION="1.0.0"
PROJECT_NAME="Sun-Panel"
DOCKER_IMAGE="hslr/sun-panel:latest"
CONTAINER_NAME="sun-panel"
INSTALL_PATH="$HOME/docker_data/sun-panel"
DEFAULT_PORT=3002

# 打印函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# 显示 Logo
show_logo() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
   ____                 ____                  _ 
  / ___| _   _ _ __    |  _ \ __ _ _ __   ___| |
  \___ \| | | | '_ \   | |_) / _` | '_ \ / _ \ |
   ___) | |_| | | | |  |  __/ (_| | | | |  __/ |
  |____/ \__,_|_| |_|  |_|   \__,_|_| |_|\___|_|
                                                  
EOF
    echo -e "${NC}"
    echo -e "${GREEN}          Sun-Panel 一键部署脚本 v${SCRIPT_VERSION}${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

# 检查是否为 root 用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "请使用 root 用户运行此脚本！"
        print_info "请执行: sudo -i"
        exit 1
    fi
}

# 检测操作系统
detect_os() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$ID
        VERSION=$VERSION_ID
        print_success "检测到系统: $PRETTY_NAME"
    else
        print_error "无法检测操作系统类型"
        exit 1
    fi
}

# 检查系统资源
check_system() {
    print_info "检查系统资源..."
    
    # 检查内存
    total_mem=$(free -m | awk 'NR==2{print $2}')
    if [[ $total_mem -lt 512 ]]; then
        print_warning "系统内存小于 512MB，可能影响运行"
    else
        print_success "内存检查通过: ${total_mem}MB"
    fi
    
    # 检查磁盘空间
    available_space=$(df -m / | awk 'NR==2{print $4}')
    if [[ $available_space -lt 1024 ]]; then
        print_warning "可用磁盘空间小于 1GB"
    else
        print_success "磁盘空间检查通过: ${available_space}MB"
    fi
}

# 安装依赖
install_dependencies() {
    print_info "安装系统依赖..."
    
    case $OS in
        ubuntu|debian)
            apt-get update -y
            apt-get install -y curl wget git sudo lsof
            ;;
        centos|rhel|rocky|almalinux)
            yum install -y epel-release
            yum install -y curl wget git sudo lsof
            ;;
        *)
            print_error "不支持的操作系统: $OS"
            exit 1
            ;;
    esac
    
    print_success "依赖安装完成"
}

# 安装 Docker
install_docker() {
    if command -v docker &> /dev/null; then
        DOCKER_VERSION=$(docker --version | awk '{print $3}' | sed 's/,//')
        print_success "Docker 已安装 (版本: $DOCKER_VERSION)"
        return 0
    fi
    
    print_info "开始安装 Docker..."
    
    # 使用官方脚本安装 Docker
    curl -fsSL https://get.docker.com | bash -s docker --mirror Aliyun
    
    if [[ $? -ne 0 ]]; then
        print_error "Docker 安装失败"
        exit 1
    fi
    
    # 启动 Docker
    systemctl start docker
    systemctl enable docker
    
    print_success "Docker 安装完成"
}

# 安装 Docker Compose (可选)
install_docker_compose() {
    if command -v docker-compose &> /dev/null; then
        print_success "Docker Compose 已安装"
        return 0
    fi
    
    print_info "安装 Docker Compose..."
    
    COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    
    curl -L "https://github.com/docker/compose/releases/download/${COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" \
        -o /usr/local/bin/docker-compose
    
    chmod +x /usr/local/bin/docker-compose
    
    print_success "Docker Compose 安装完成"
}

# 检查端口占用
check_port() {
    local port=$1
    if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
        return 1
    else
        return 0
    fi
}

# 获取用户输入的端口
get_port() {
    while true; do
        read -p "请输入访问端口 (默认 $DEFAULT_PORT): " PORT
        PORT=${PORT:-$DEFAULT_PORT}
        
        if ! [[ "$PORT" =~ ^[0-9]+$ ]] || [ "$PORT" -lt 1 ] || [ "$PORT" -gt 65535 ]; then
            print_error "端口号无效，请输入 1-65535 之间的数字"
            continue
        fi
        
        if check_port $PORT; then
            print_success "端口 $PORT 可用"
            break
        else
            print_warning "端口 $PORT 已被占用"
            read -p "是否使用其他端口? (y/n): " choice
            if [[ $choice != "y" && $choice != "Y" ]]; then
                exit 0
            fi
        fi
    done
}

# 创建数据目录
create_directories() {
    print_info "创建数据目录..."
    
    mkdir -p "$INSTALL_PATH/conf"
    mkdir -p "$INSTALL_PATH/uploads"
    mkdir -p "$INSTALL_PATH/database"
    
    print_success "目录创建完成: $INSTALL_PATH"
}

# 停止并删除旧容器
remove_old_container() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_info "检测到旧容器，正在删除..."
        docker stop $CONTAINER_NAME >/dev/null 2>&1
        docker rm $CONTAINER_NAME >/dev/null 2>&1
        print_success "旧容器已删除"
    fi
}

# 拉取 Docker 镜像
pull_image() {
    print_info "拉取 Sun-Panel 镜像..."
    
    docker pull $DOCKER_IMAGE
    
    if [[ $? -ne 0 ]]; then
        print_error "镜像拉取失败"
        exit 1
    fi
    
    print_success "镜像拉取完成"
}

# 启动容器
start_container() {
    print_info "启动 Sun-Panel 容器..."
    
    docker run -d \
        --name $CONTAINER_NAME \
        --restart=always \
        -p $PORT:3002 \
        -v "$INSTALL_PATH/conf:/app/conf" \
        -v "$INSTALL_PATH/uploads:/app/uploads" \
        -v "$INSTALL_PATH/database:/app/database" \
        $DOCKER_IMAGE
    
    if [[ $? -ne 0 ]]; then
        print_error "容器启动失败"
        exit 1
    fi
    
    sleep 3
    
    if docker ps | grep -q $CONTAINER_NAME; then
        print_success "容器启动成功"
        return 0
    else
        print_error "容器启动失败，请查看日志: docker logs $CONTAINER_NAME"
        exit 1
    fi
}

# 显示安装信息
show_install_info() {
    clear
    show_logo
    
    echo -e "${GREEN}================================================${NC}"
    echo -e "${GREEN}           Sun-Panel 安装完成！${NC}"
    echo -e "${GREEN}================================================${NC}"
    echo ""
    
    # 获取服务器 IP
    SERVER_IP=$(curl -s ip.sb || curl -s ifconfig.me || echo "YOUR_SERVER_IP")
    
    echo -e "${CYAN}访问信息:${NC}"
    echo -e "  访问地址: ${GREEN}http://${SERVER_IP}:${PORT}${NC}"
    echo -e "  默认账号: ${YELLOW}admin@sun.cc${NC}"
    echo -e "  默认密码: ${YELLOW}12345678${NC}"
    echo ""
    
    echo -e "${CYAN}数据目录:${NC}"
    echo -e "  安装路径: ${BLUE}$INSTALL_PATH${NC}"
    echo -e "  配置文件: ${BLUE}$INSTALL_PATH/conf${NC}"
    echo -e "  上传文件: ${BLUE}$INSTALL_PATH/uploads${NC}"
    echo -e "  数据库: ${BLUE}$INSTALL_PATH/database${NC}"
    echo ""
    
    echo -e "${CYAN}常用命令:${NC}"
    echo -e "  启动: ${BLUE}docker start $CONTAINER_NAME${NC}"
    echo -e "  停止: ${BLUE}docker stop $CONTAINER_NAME${NC}"
    echo -e "  重启: ${BLUE}docker restart $CONTAINER_NAME${NC}"
    echo -e "  查看日志: ${BLUE}docker logs -f $CONTAINER_NAME${NC}"
    echo -e "  查看状态: ${BLUE}docker ps | grep $CONTAINER_NAME${NC}"
    echo ""
    
    echo -e "${YELLOW}提示: 首次登录后请立即修改默认密码！${NC}"
    echo ""
}

# 查看状态
check_status() {
    show_logo
    
    if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        print_success "Sun-Panel 运行中"
        echo ""
        docker ps --filter "name=${CONTAINER_NAME}" --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        echo ""
        
        SERVER_IP=$(curl -s ip.sb 2>/dev/null || echo "YOUR_SERVER_IP")
        MAPPED_PORT=$(docker port $CONTAINER_NAME 2>/dev/null | grep 3002 | cut -d: -f2)
        
        echo -e "${GREEN}访问地址: http://${SERVER_IP}:${MAPPED_PORT}${NC}"
    else
        print_warning "Sun-Panel 未运行"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..."
}

# 查看日志
view_logs() {
    show_logo
    print_info "查看容器日志 (Ctrl+C 退出)"
    echo ""
    docker logs -f --tail 100 $CONTAINER_NAME
}

# 重启服务
restart_service() {
    print_info "重启 Sun-Panel..."
    docker restart $CONTAINER_NAME
    
    if [[ $? -eq 0 ]]; then
        print_success "重启成功"
    else
        print_error "重启失败"
    fi
    
    sleep 2
}

# 更新容器
update_container() {
    show_logo
    print_warning "即将更新 Sun-Panel 到最新版本"
    read -p "确认更新? (y/n): " confirm
    
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        return
    fi
    
    print_info "停止当前容器..."
    docker stop $CONTAINER_NAME
    
    print_info "备份数据..."
    BACKUP_DIR="$HOME/sun-panel-backup-$(date +%Y%m%d-%H%M%S)"
    cp -r $INSTALL_PATH $BACKUP_DIR
    print_success "数据已备份至: $BACKUP_DIR"
    
    print_info "删除旧容器..."
    docker rm $CONTAINER_NAME
    
    print_info "拉取最新镜像..."
    docker pull $DOCKER_IMAGE
    
    print_info "启动新容器..."
    
    # 获取原来的端口
    if [[ -f "$INSTALL_PATH/.port" ]]; then
        PORT=$(cat "$INSTALL_PATH/.port")
    else
        PORT=$DEFAULT_PORT
    fi
    
    start_container
    print_success "更新完成！"
    
    sleep 2
}

# 卸载
uninstall() {
    show_logo
    print_warning "即将卸载 Sun-Panel"
    echo -e "${RED}注意: 这将删除所有容器和镜像，但保留数据文件${NC}"
    read -p "确认卸载? (y/n): " confirm
    
    if [[ $confirm != "y" && $confirm != "Y" ]]; then
        return
    fi
    
    print_info "停止容器..."
    docker stop $CONTAINER_NAME 2>/dev/null
    
    print_info "删除容器..."
    docker rm $CONTAINER_NAME 2>/dev/null
    
    print_info "删除镜像..."
    docker rmi $DOCKER_IMAGE 2>/dev/null
    
    read -p "是否删除数据文件? (y/n): " delete_data
    if [[ $delete_data == "y" || $delete_data == "Y" ]]; then
        rm -rf $INSTALL_PATH
        print_success "数据文件已删除"
    else
        print_info "数据文件保留在: $INSTALL_PATH"
    fi
    
    print_success "卸载完成"
    sleep 2
}

# 完整安装流程
full_install() {
    show_logo
    check_root
    detect_os
    check_system
    install_dependencies
    install_docker
    get_port
    create_directories
    remove_old_container
    pull_image
    start_container
    
    # 保存端口号
    echo $PORT > "$INSTALL_PATH/.port"
    
    show_install_info
}

# 主菜单
main_menu() {
    while true; do
        show_logo
        echo -e "${CYAN}请选择操作:${NC}"
        echo ""
        echo "  1) 安装 Sun-Panel"
        echo "  2) 查看状态"
        echo "  3) 启动服务"
        echo "  4) 停止服务"
        echo "  5) 重启服务"
        echo "  6) 查看日志"
        echo "  7) 更新版本"
        echo "  8) 卸载"
        echo "  0) 退出"
        echo ""
        read -p "请输入选项 [0-8]: " choice
        
        case $choice in
            1)
                full_install
                read -p "按回车键继续..."
                ;;
            2)
                check_status
                ;;
            3)
                docker start $CONTAINER_NAME && print_success "启动成功" || print_error "启动失败"
                sleep 2
                ;;
            4)
                docker stop $CONTAINER_NAME && print_success "停止成功" || print_error "停止失败"
                sleep 2
                ;;
            5)
                restart_service
                ;;
            6)
                view_logs
                ;;
            7)
                update_container
                ;;
            8)
                uninstall
                ;;
            0)
                print_info "感谢使用，再见！"
                exit 0
                ;;
            *)
                print_error "无效选项，请重新选择"
                sleep 2
                ;;
        esac
    done
}

# 脚本入口
if [[ "$1" == "install" ]]; then
    full_install
elif [[ "$1" == "uninstall" ]]; then
    uninstall
else
    main_menu
fi
