#!/bin/bash
# DIFY多用户容器批量管理工具

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
START_SCRIPT="$SCRIPT_DIR/start_dify_multi_user.sh"

function show_usage() {
    echo "DIFY多用户容器管理工具"
    echo "========================"
    echo ""
    echo "用法: $0 <命令> [参数]"
    echo ""
    echo "命令:"
    echo "  start <用户ID>           启动指定用户的容器"
    echo "  start-range <起始> <结束> 批量启动用户容器"
    echo "  stop <用户ID>            停止指定用户的容器"
    echo "  stop-all                 停止所有用户容器"
    echo "  status                   显示所有容器状态"
    echo "  clean                    清理所有停止的容器"
    echo "  test <数量>              测试启动指定数量的容器"
    echo ""
    echo "示例:"
    echo "  $0 start 1              # 启动用户1的容器"
    echo "  $0 start-range 1 5      # 启动用户1-5的容器"
    echo "  $0 test 3               # 测试启动3个容器"
}

function start_user() {
    local user_id=$1
    echo "启动用户 $user_id 的容器..."
    bash "$START_SCRIPT" "$user_id"
}

function start_range() {
    local start_id=$1
    local end_id=$2
    
    echo "批量启动用户 $start_id 到 $end_id 的容器..."
    echo ""
    
    for ((i=$start_id; i<=$end_id; i++)); do
        echo "[$i/$end_id] 启动用户 $i..."
        start_user $i
        echo "-----------------------------------"
        echo ""
        # 稍微延迟，避免同时启动太多容器
        sleep 2
    done
    
    echo "批量启动完成！"
}

function stop_user() {
    local user_id=$1
    local container_name="dify-user-$user_id"
    
    echo "停止用户 $user_id 的容器..."
    docker stop "$container_name" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "容器 $container_name 已停止"
    else
        echo "容器 $container_name 不存在或已停止"
    fi
}

function stop_all() {
    echo "停止所有DIFY用户容器..."
    local containers=$(docker ps -q --filter "name=dify-user-")
    
    if [ -z "$containers" ]; then
        echo "没有运行中的用户容器"
    else
        docker stop $containers
        echo "所有用户容器已停止"
    fi
}

function show_status() {
    echo "DIFY用户容器状态"
    echo "=================="
    echo ""
    
    # 统计信息
    local running_count=$(docker ps -q --filter "name=dify-user-" | wc -l)
    local total_count=$(docker ps -aq --filter "name=dify-user-" | wc -l)
    
    echo "统计信息:"
    echo "  运行中: $running_count"
    echo "  总计: $total_count"
    echo ""
    
    # 详细列表
    echo "容器列表:"
    echo "用户ID | 容器名称           | 状态     | Web端口 | WS端口  | CPU  | 内存"
    echo "-------|-------------------|----------|---------|---------|------|-------"
    
    # 获取所有dify-user容器
    for container in $(docker ps -a --format "{{.Names}}" | grep "dify-user-" | sort -V); do
        if [[ $container =~ dify-user-([0-9]+) ]]; then
            local user_id="${BASH_REMATCH[1]}"
            local web_port=$((40000 + user_id))
            local ws_port=$((41000 + user_id))
            
            # 获取容器状态
            local status=$(docker ps -a --filter "name=$container" --format "{{.State}}")
            
            # 如果运行中，获取资源使用情况
            if [ "$status" = "running" ]; then
                local stats=$(docker stats --no-stream --format "{{.CPUPerc}}|{{.MemUsage}}" "$container" 2>/dev/null)
                local cpu=$(echo "$stats" | cut -d'|' -f1)
                local mem=$(echo "$stats" | cut -d'|' -f2 | cut -d'/' -f1)
            else
                local cpu="-"
                local mem="-"
            fi
            
            printf "%-6s | %-17s | %-8s | %-7s | %-7s | %-4s | %s\n" \
                "$user_id" "$container" "$status" "$web_port" "$ws_port" "$cpu" "$mem"
        fi
    done
    
    echo ""
    
    # 端口检查
    echo "服务健康检查:"
    for container in $(docker ps --format "{{.Names}}" | grep "dify-user-" | sort -V); do
        if [[ $container =~ dify-user-([0-9]+) ]]; then
            local user_id="${BASH_REMATCH[1]}"
            local web_port=$((40000 + user_id))
            local ws_port=$((41000 + user_id))
            
            echo -n "用户 $user_id: "
            
            # 检查Web服务
            if curl -s http://localhost:$web_port > /dev/null 2>&1; then
                echo -n "Web[OK] "
            else
                echo -n "Web[--] "
            fi
            
            # 检查WebSocket
            if nc -z localhost $ws_port 2>/dev/null; then
                echo "WS[OK]"
            else
                echo "WS[--]"
            fi
        fi
    done
}

function clean_containers() {
    echo "清理停止的容器..."
    local stopped=$(docker ps -aq --filter "name=dify-user-" --filter "status=exited")
    
    if [ -z "$stopped" ]; then
        echo "没有需要清理的容器"
    else
        docker rm $stopped
        echo "清理完成"
    fi
}

function test_deployment() {
    local count=$1
    
    echo "测试部署 $count 个用户容器"
    echo "=============================="
    echo ""
    
    # 启动容器
    echo "启动阶段..."
    local start_time=$(date +%s)
    
    for ((i=1; i<=$count; i++)); do
        echo "[$i/$count] 启动用户 $i..."
        start_user $i > /dev/null 2>&1
        sleep 1
    done
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo ""
    echo "启动完成，耗时: ${duration}秒"
    echo ""
    
    # 等待服务稳定
    echo "等待30秒让服务稳定..."
    sleep 30
    
    # 检查状态
    echo ""
    echo "部署结果:"
    show_status
    
    echo ""
    echo "测试总结:"
    echo "  请求数量: $count"
    echo "  成功启动: $(docker ps -q --filter "name=dify-user-" | wc -l)"
    echo "  平均启动时间: $((duration / count))秒/容器"
}

# 主逻辑
if [ $# -eq 0 ]; then
    show_usage
    exit 0
fi

# 确保脚本可执行
chmod +x "$START_SCRIPT" 2>/dev/null

case "$1" in
    start)
        if [ $# -ne 2 ]; then
            echo "错误: 需要指定用户ID"
            echo "用法: $0 start <用户ID>"
            exit 1
        fi
        start_user $2
        ;;
        
    start-range)
        if [ $# -ne 3 ]; then
            echo "错误: 需要指定起始和结束用户ID"
            echo "用法: $0 start-range <起始ID> <结束ID>"
            exit 1
        fi
        start_range $2 $3
        ;;
        
    stop)
        if [ $# -ne 2 ]; then
            echo "错误: 需要指定用户ID"
            echo "用法: $0 stop <用户ID>"
            exit 1
        fi
        stop_user $2
        ;;
        
    stop-all)
        stop_all
        ;;
        
    status)
        show_status
        ;;
        
    clean)
        clean_containers
        ;;
        
    test)
        if [ $# -ne 2 ]; then
            echo "错误: 需要指定测试数量"
            echo "用法: $0 test <数量>"
            exit 1
        fi
        test_deployment $2
        ;;
        
    *)
        echo "错误: 未知命令 '$1'"
        echo ""
        show_usage
        exit 1
        ;;
esac
