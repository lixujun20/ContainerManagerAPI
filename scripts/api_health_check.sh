#!/bin/bash
# API健康检查脚本
# 用于定期检查API服务状态

API_URL="http://localhost:8080"
ALERT_EMAIL="admin@example.com"
LOG_FILE="/tmp/api_health_check.log"

HEALTH_STATUS="OK"
ISSUES=""

# 1. 检查API进程
if pgrep -f container_manager.py > /dev/null; then
    PID=$(pgrep -f container_manager.py)
    ps -p $PID -o %cpu,%mem,etime --no-headers | while read cpu mem time; do
        : # 进程正常运行
    done
else
    HEALTH_STATUS="CRITICAL"
    ISSUES="$ISSUES\n- API进程未运行"
fi

# 2. 检查端口监听
if ! netstat -tln 2>/dev/null | grep -q ":8080 "; then
    HEALTH_STATUS="CRITICAL"
    ISSUES="$ISSUES\n- 端口8080未监听"
fi

# 3. 检查API响应
START_TIME=$(date +%s.%N)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$API_URL/" 2>/dev/null)
END_TIME=$(date +%s.%N)
RESPONSE_TIME=$(echo "$END_TIME - $START_TIME" | bc 2>/dev/null || echo "0")

if [ "$HTTP_CODE" != "200" ]; then
    HEALTH_STATUS="CRITICAL"
    ISSUES="$ISSUES\n- API返回错误状态码: $HTTP_CODE"
elif (( $(echo "$RESPONSE_TIME > 2" | bc -l 2>/dev/null || echo 0) )); then
    HEALTH_STATUS="WARNING"
    ISSUES="$ISSUES\n- API响应时间过长: ${RESPONSE_TIME}s"
fi

# 4. 检查容器列表接口
if CONTAINERS=$(curl -s --connect-timeout 5 "$API_URL/list" 2>/dev/null); then
    if echo "$CONTAINERS" | jq . > /dev/null 2>&1; then
        TOTAL=$(echo "$CONTAINERS" | jq -r '.total // 0')
        if [ "$TOTAL" -gt 90 ]; then
            HEALTH_STATUS="WARNING"
            ISSUES="$ISSUES\n- 容器数接近上限: $TOTAL/100"
        fi
    else
        HEALTH_STATUS="WARNING"
        ISSUES="$ISSUES\n- 容器列表接口返回格式错误"
    fi
else
    HEALTH_STATUS="CRITICAL"
    ISSUES="$ISSUES\n- 容器列表接口无响应"
fi

# 5. 检查磁盘空间
DISK_USAGE=$(df -h ~ | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -ge 90 ]; then
    HEALTH_STATUS="CRITICAL"
    ISSUES="$ISSUES\n- 磁盘空间严重不足: $DISK_USAGE%"
elif [ "$DISK_USAGE" -ge 80 ]; then
    HEALTH_STATUS="WARNING"
    ISSUES="$ISSUES\n- 磁盘使用率高: $DISK_USAGE%"
fi

# 6. 检查最近错误日志
if [ -f /tmp/container_manager.log ]; then
    ERROR_COUNT=$(tail -1000 /tmp/container_manager.log 2>/dev/null | grep -i "error\|exception" | wc -l)
    if [ "$ERROR_COUNT" -ge 10 ]; then
        HEALTH_STATUS="WARNING"
        ISSUES="$ISSUES\n- 最近1000行日志中有 $ERROR_COUNT 个错误"
    fi
fi

# 记录到日志
{
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Health Check: $HEALTH_STATUS"
    if [ "$HEALTH_STATUS" != "OK" ]; then
        echo "Issues:$ISSUES"
    fi
} >> "$LOG_FILE"

# 退出码
case "$HEALTH_STATUS" in
    "OK") exit 0 ;;
    "WARNING") exit 1 ;;
    "CRITICAL") exit 2 ;;
esac
