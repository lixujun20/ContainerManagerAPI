#!/bin/bash
# API服务管理工具
# 提供API服务的启动、停止、重启等管理功能

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"
API_SCRIPT="$BASE_DIR/container_manager.py"
PID_FILE="/tmp/container_manager.pid"
LOG_FILE="/tmp/container_manager.log"
SERVICE_NAME="dify-container-manager"

# 获取进程PID
get_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE"
    else
        pgrep -f container_manager.py
    fi
}

# 检查API是否运行
is_running() {
    local pid=$(get_pid)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# 启动API服务
start_api() {
    if is_running; then
        echo "API服务已在运行"
        return 1
    fi
    
    echo "启动API服务..."
    
    # 检查Python3
    if ! command -v python3 &> /dev/null; then
        echo "错误: Python3未安装"
        return 1
    fi
    
    # 检查Flask
    if ! python3 -c "import flask" &> /dev/null; then
        echo "警告: Flask未安装，正在安装..."
        pip3 install flask || sudo pip3 install flask
    fi
    
    # 检查端口
    if netstat -tln 2>/dev/null | grep -q ":8080 "; then
        echo "错误: 端口8080已被占用"
        return 1
    fi
    
    # 启动服务
    cd "$BASE_DIR"
    nohup python3 "$API_SCRIPT" > "$LOG_FILE" 2>&1 &
    local pid=$!
    echo $pid > "$PID_FILE"
    
    # 等待启动
    echo -n "等待服务启动"
    for i in {1..10}; do
        sleep 1
        echo -n "."
        if curl -s http://localhost:8080 > /dev/null 2>&1; then
            echo ""
            echo "API服务启动成功"
            echo "PID: $pid"
            echo "日志: $LOG_FILE"
            return 0
        fi
    done
    
    echo ""
    echo "API服务启动失败，请查看日志: $LOG_FILE"
    return 1
}

# 停止API服务
stop_api() {
    if ! is_running; then
        echo "API服务未运行"
        return 1
    fi
    
    echo "停止API服务..."
    local pid=$(get_pid)
    
    # 优雅停止
    kill -TERM "$pid" 2>/dev/null
    
    # 等待进程结束
    echo -n "等待服务停止"
    for i in {1..10}; do
        sleep 1
        echo -n "."
        if ! kill -0 "$pid" 2>/dev/null; then
            echo ""
            echo "API服务已停止"
            rm -f "$PID_FILE"
            return 0
        fi
    done
    
    # 强制停止
    echo ""
    echo "强制停止服务"
    kill -9 "$pid" 2>/dev/null
    rm -f "$PID_FILE"
    return 0
}

# 重启API服务
restart_api() {
    echo "重启API服务..."
    stop_api
    sleep 2
    start_api
}

# 查看状态
status_api() {
    echo "API服务状态"
    echo "============"
    
    # 检查进程
    if is_running; then
        local pid=$(get_pid)
        echo "进程状态: 运行中"
        echo "PID: $pid"
        ps -p $pid -o pid,user,%cpu,%mem,etime,cmd --no-headers
    else
        echo "进程状态: 未运行"
    fi
    echo ""
    
    # 检查端口
    echo -n "端口8080: "
    if netstat -tln 2>/dev/null | grep -q ":8080 "; then
        echo "监听中"
    else
        echo "未监听"
    fi
    
    # 检查API响应
    echo -n "API响应: "
    if response=$(curl -s -w "\n%{http_code}" http://localhost:8080/ 2>/dev/null); then
        http_code=$(echo "$response" | tail -1)
        echo "HTTP $http_code"
    else
        echo "无响应"
    fi
    
    # 显示日志位置
    echo ""
    echo "日志文件: $LOG_FILE"
    if [ -f "$LOG_FILE" ]; then
        echo "最新日志:"
        tail -5 "$LOG_FILE"
    fi
}

# 查看日志
logs_api() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "日志文件不存在: $LOG_FILE"
        return 1
    fi
    
    echo "API日志"
    echo "======="
    echo "日志文件: $LOG_FILE"
    echo ""
    
    echo "1) 查看最新20行"
    echo "2) 实时查看日志"
    echo "3) 查看错误日志"
    echo "4) 查看完整日志"
    echo ""
    read -p "请选择 [1-4]: " choice
    
    case $choice in
        1) tail -20 "$LOG_FILE" ;;
        2) tail -f "$LOG_FILE" ;;
        3) grep -i "error\|exception" "$LOG_FILE" | tail -20 ;;
        4) less "$LOG_FILE" ;;
        *) echo "无效选择" ;;
    esac
}

# 安装systemd服务
install_service() {
    echo "安装Systemd服务"
    echo "==============="
    
    local service_file="$BASE_DIR/dify-container-manager.service"
    if [ ! -f "$service_file" ]; then
        echo "错误: 服务文件不存在"
        return 1
    fi
    
    # 复制服务文件
    sudo cp "$service_file" /etc/systemd/system/
    
    # 更新服务文件中的路径
    sudo sed -i "s|WorkingDirectory=.*|WorkingDirectory=$BASE_DIR|g" /etc/systemd/system/$SERVICE_NAME.service
    sudo sed -i "s|ExecStart=.*|ExecStart=/usr/bin/python3 $API_SCRIPT|g" /etc/systemd/system/$SERVICE_NAME.service
    
    # 重载systemd
    sudo systemctl daemon-reload
    sudo systemctl enable $SERVICE_NAME
    
    echo "服务安装成功"
    echo ""
    echo "使用以下命令管理服务:"
    echo "  sudo systemctl start $SERVICE_NAME"
    echo "  sudo systemctl stop $SERVICE_NAME"
    echo "  sudo systemctl restart $SERVICE_NAME"
    echo "  sudo systemctl status $SERVICE_NAME"
}

# 显示使用帮助
show_help() {
    echo "DIFY容器管理API服务管理工具"
    echo "============================"
    echo ""
    echo "用法: $0 <命令>"
    echo ""
    echo "命令:"
    echo "  start       启动API服务"
    echo "  stop        停止API服务"
    echo "  restart     重启API服务"
    echo "  status      查看服务状态"
    echo "  logs        查看服务日志"
    echo "  install     安装为systemd服务"
    echo "  help        显示此帮助信息"
    echo ""
    echo "示例:"
    echo "  $0 start    # 启动服务"
    echo "  $0 status   # 查看状态"
}

# 主逻辑
case "$1" in
    start) start_api ;;
    stop) stop_api ;;
    restart) restart_api ;;
    status) status_api ;;
    logs) logs_api ;;
    install) install_service ;;
    help|--help|-h) show_help ;;
    *)
        if [ -z "$1" ]; then
            show_help
        else
            echo "未知命令: $1"
            show_help
            exit 1
        fi
        ;;
esac
