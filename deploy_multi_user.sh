#!/bin/bash
# DIFY多用户系统快速部署脚本

echo "DIFY多用户容器系统部署"
echo "============================="
echo ""

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. 检查依赖
echo "检查系统依赖..."

# 检查Docker
if ! command -v docker &> /dev/null; then
    echo "错误: Docker未安装，请先安装Docker"
    exit 1
else
    echo "Docker已安装: $(docker --version)"
fi

# 检查Python3
if ! command -v python3 &> /dev/null; then
    echo "错误: Python3未安装，请先安装Python3"
    exit 1
else
    echo "Python3已安装: $(python3 --version)"
fi

# 检查Flask
if ! python3 -c "import flask" &> /dev/null; then
    echo "警告: Flask未安装，正在安装..."
    pip3 install flask || sudo pip3 install flask
fi

# 2. 设置权限
echo ""
echo "设置脚本权限..."
chmod +x "$SCRIPT_DIR/start_dify_multi_user.sh"
chmod +x "$SCRIPT_DIR/manage_multi_user.sh"
chmod +x "$SCRIPT_DIR/container_manager.py"
echo "权限设置完成"

# 3. 创建必要的目录
echo ""
echo "创建数据目录..."
mkdir -p "$HOME/dify_data"
chmod 755 "$HOME/dify_data"
echo "数据目录创建完成: $HOME/dify_data"

# 4. 安装系统服务（可选）
echo ""
read -p "是否安装为系统服务（开机自启动）？[y/N] " -n 1 -r
echo ""
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "安装系统服务..."
    
    # 更新服务文件中的路径
    sed -i "s|/home/lixujun|$HOME|g" "$SCRIPT_DIR/dify-container-manager.service"
    
    # 复制服务文件
    sudo cp "$SCRIPT_DIR/dify-container-manager.service" /etc/systemd/system/
    
    # 启动服务
    sudo systemctl daemon-reload
    sudo systemctl enable dify-container-manager.service
    sudo systemctl start dify-container-manager.service
    
    # 检查服务状态
    sleep 2
    if sudo systemctl is-active --quiet dify-container-manager.service; then
        echo "服务安装并启动成功"
    else
        echo "警告: 服务启动失败，请检查日志: sudo journalctl -u dify-container-manager"
    fi
else
    echo "跳过系统服务安装"
fi

# 5. 启动容器管理API（如果没有作为服务运行）
if ! sudo systemctl is-active --quiet dify-container-manager.service 2>/dev/null; then
    echo ""
    echo "启动容器管理API..."
    
    # 检查8080端口是否被占用
    if netstat -tln 2>/dev/null | grep -q ":8080 "; then
        echo "警告: 端口8080已被占用"
        read -p "是否停止占用8080端口的进程？[y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo fuser -k 8080/tcp
            sleep 2
        else
            echo "错误: 无法启动容器管理API，端口被占用"
            exit 1
        fi
    fi
    
    # 后台启动API服务
    nohup python3 "$SCRIPT_DIR/container_manager.py" > /tmp/container_manager.log 2>&1 &
    API_PID=$!
    
    echo "容器管理API已启动 (PID: $API_PID)"
    echo "日志文件: /tmp/container_manager.log"
fi

# 6. 测试部署
echo ""
echo "测试部署..."
sleep 3

# 测试API
if curl -s http://localhost:8080/ > /dev/null 2>&1; then
    echo "容器管理API响应正常"
else
    echo "警告: 容器管理API无响应"
fi

# 7. 显示部署信息
echo ""
echo "部署完成！"
echo "============================================"
echo ""
echo "使用指南："
echo ""
echo "1. 容器管理API:"
echo "   - 地址: http://localhost:8080"
echo "   - 创建容器: curl -X POST http://localhost:8080/create -H 'Content-Type: application/json' -d '{\"user_id\":1}'"
echo "   - 查看列表: curl http://localhost:8080/list"
echo ""
echo "2. 命令行工具:"
echo "   - 启动单个用户: $SCRIPT_DIR/manage_multi_user.sh start 1"
echo "   - 批量启动: $SCRIPT_DIR/manage_multi_user.sh start-range 1 5"
echo "   - 查看状态: $SCRIPT_DIR/manage_multi_user.sh status"
echo "   - 测试部署: $SCRIPT_DIR/manage_multi_user.sh test 3"
echo ""
echo "3. 直接使用脚本:"
echo "   - 启动容器: $SCRIPT_DIR/start_dify_multi_user.sh <用户ID>"
echo ""
echo "4. 服务管理（如已安装）:"
echo "   - 查看状态: sudo systemctl status dify-container-manager"
echo "   - 查看日志: sudo journalctl -u dify-container-manager -f"
echo "   - 重启服务: sudo systemctl restart dify-container-manager"
echo ""
echo "快速测试:"
echo "   $SCRIPT_DIR/manage_multi_user.sh test 3"
echo ""
