#!/bin/bash
# API实时监控脚本
# 提供实时的性能和状态监控

# 清屏函数
clear_screen() {
    printf "\033c"
}

# 获取API进程信息
get_process_info() {
    local pid=$(pgrep -f container_manager.py)
    if [ -n "$pid" ]; then
        ps -p $pid -o pid,%cpu,%mem,etime,cmd --no-headers
    else
        echo "N/A N/A N/A N/A API未运行"
    fi
}

# 获取容器统计
get_container_stats() {
    local stats=$(curl -s http://localhost:8080/list 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "$stats" | jq -r '.total // 0' 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# 测试API延迟
test_api_latency() {
    local start=$(date +%s.%N)
    curl -s http://localhost:8080/ > /dev/null 2>&1
    local end=$(date +%s.%N)
    if [ $? -eq 0 ]; then
        echo "$end - $start" | bc 2>/dev/null || echo "N/A"
    else
        echo "N/A"
    fi
}

# 获取端口连接数
get_connections() {
    netstat -an 2>/dev/null | grep :8080 | grep ESTABLISHED | wc -l
}

# 主监控循环
while true; do
    clear_screen
    
    echo "======================================"
    echo "   DIFY容器管理API 实时监控"
    echo "======================================"
    echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
    echo ""
    
    # 进程信息
    echo "进程信息:"
    echo "PID    CPU%   MEM%   运行时间    命令"
    echo "-------------------------------------"
    get_process_info
    echo ""
    
    # API状态
    echo "API状态:"
    LATENCY=$(test_api_latency)
    if [ "$LATENCY" != "N/A" ]; then
        echo "响应时间: ${LATENCY}秒"
    else
        echo "响应时间: 无响应"
    fi
    
    CONNECTIONS=$(get_connections)
    echo "活跃连接数: $CONNECTIONS"
    echo ""
    
    # 容器统计
    echo "容器统计:"
    TOTAL_CONTAINERS=$(get_container_stats)
    if [ "$TOTAL_CONTAINERS" != "N/A" ]; then
        echo "活跃容器: $TOTAL_CONTAINERS/100"
        
        # 容器使用率条形图
        USAGE=$((TOTAL_CONTAINERS * 100 / 100))
        echo -n "使用率: ["
        for i in {1..20}; do
            if [ $((i * 5)) -le $USAGE ]; then
                echo -n "#"
            else
                echo -n "-"
            fi
        done
        echo "] $USAGE%"
    else
        echo "活跃容器: 无法获取"
    fi
    echo ""
    
    # 系统资源
    echo "系统资源:"
    LOAD=$(uptime | awk -F'load average:' '{print $2}')
    echo "系统负载: $LOAD"
    
    MEM_INFO=$(free -h | grep Mem)
    MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
    MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
    echo "内存使用: $MEM_USED / $MEM_TOTAL"
    
    DISK_INFO=$(df -h ~ | tail -1)
    DISK_USED=$(echo $DISK_INFO | awk '{print $5}')
    echo "磁盘使用: $DISK_USED"
    echo ""
    
    # 最近的API调用
    if [ -f /tmp/container_manager.log ]; then
        echo "最近的API调用:"
        tail -5 /tmp/container_manager.log | grep -E "POST|GET" | tail -3
    fi
    
    echo ""
    echo "======================================"
    echo "按 Ctrl+C 退出监控"
    echo "刷新间隔: 5秒"
    
    sleep 5
done
