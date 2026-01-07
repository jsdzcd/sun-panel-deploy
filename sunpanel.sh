#!/bin/bash

BASE_DIR="/opt/sun-panel-v2"

while true; do
  clear
  echo "================================="
  echo " Sun-Panel-v2 管理菜单"
  echo "================================="
  echo "1. 安装 / 重装 Sun-Panel-v2"
  echo "2. 更新 Sun-Panel-v2"
  echo "3. 手动数据库备份"
  echo "4. 查看运行状态"
  echo "5. 查看日志"
  echo "6. 卸载"
  echo "0. 退出"
  echo
  read -p "请选择: " choice

  case $choice in
    1)
      curl -fsSL https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/deploy_sunpanel_interactive.sh | bash
      ;;
    2)
      cd "$BASE_DIR" && docker compose pull && docker compose up -d
      ;;
    3)
      /usr/local/bin/sunpanel_backup.sh
      ;;
    4)
      cd "$BASE_DIR" && docker compose ps
      read -p "回车继续..."
      ;;
    5)
      cd "$BASE_DIR" && docker compose logs -f
      ;;
    6)
      read -p "确认卸载? 数据将删除 [y/N]: " c
      [[ "$c" =~ ^[Yy]$ ]] || continue
      cd "$BASE_DIR" && docker compose down
      rm -rf "$BASE_DIR"
      rm -f /etc/nginx/sites-enabled/sun-panel.conf
      systemctl reload nginx
      ;;
    0)
      exit 0
      ;;
  esac
done
