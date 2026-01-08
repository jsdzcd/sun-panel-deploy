🎯 主要特点：

完整的错误处理 - 所有关键步骤都有错误检查
系统兼容性 - 支持 Ubuntu/Debian/CentOS/Rocky/AlmaLinux
端口冲突检测 - 自动检查端口是否被占用
数据持久化 - 正确挂载配置、上传和数据库目录
交互式菜单 - 美观易用的操作界面
完整功能 - 安装/卸载/更新/日志/状态查看

📦 使用方法：
方式一：一键安装
bash# 下载并执行
wget -O sun-panel-install.sh https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/install.sh && chmod +x sun-panel-install.sh && ./sun-panel-install.sh

方式二：curl 方式
bashcurl -fsSL https://raw.githubusercontent.com/jsdzcd/sun-panel-deploy/main/install.sh | bash

方式三：交互式菜单
bashbash sun-panel-install.sh

方式四：直接安装
bashbash sun-panel-install.sh install
📝 GitHub 使用说明：

创建仓库: 在 GitHub 创建名为 sun-panel-deploy 的仓库
上传脚本: 将脚本保存为 install.sh 并上传
添加 README: 创建使用说明文档
