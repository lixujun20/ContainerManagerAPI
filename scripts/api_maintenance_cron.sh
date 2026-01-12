#!/bin/bash
# API维护定时任务配置
# 设置自动化维护任务

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(dirname "$SCRIPT_DIR")"

echo "配置API维护定时任务"
echo "===================="
echo ""

# 创建维护脚本目录
MAINT_DIR="/opt/dify-api-maintenance"
sudo mkdir -p "$MAINT_DIR"
sudo cp "$SCRIPT_DIR/api_health_check.sh" "$MAINT_DIR/"
sudo cp "$SCRIPT_DIR/api_manager.sh" "$MAINT_DIR/"
sudo chmod +x "$MAINT_DIR"/*.sh

# 创建日志目录
sudo mkdir -p /var/log/dify-api
sudo chown $USER:$USER /var/log/dify-api

# 生成crontab配置
cat > /tmp/dify-api-cron << 'EOF'
# DIFY容器管理API维护任务

# 每5分钟进行一次健康检查
*/5 * * * * /opt/dify-api-maintenance/api_health_check.sh > /var/log/dify-api/health_check.log 2>&1

# 每小时清理过期日志
0 * * * * find /tmp -name "container_manager.log.*" -mtime +7 -delete

# 每天凌晨4点清理停止的容器
0 4 * * * docker rm $(docker ps -aq -f status=exited -f name=dify-user) > /var/log/dify-api/cleanup.log 2>&1

# 每周日凌晨5点生成使用报告
0 5 * * 0 /opt/dify-api-maintenance/generate_weekly_report.sh > /var/log/dify-api/weekly_report.log 2>&1

# 每月1号凌晨6点进行磁盘清理
0 6 1 * * /opt/dify-api-maintenance/monthly_cleanup.sh > /var/log/dify-api/monthly_cleanup.log 2>&1
EOF

# 创建周报生成脚本
sudo tee "$MAINT_DIR/generate_weekly_report.sh" > /dev/null << 'EOF'
#!/bin/bash
# 生成周使用报告

REPORT_DIR="/var/log/dify-api/reports"
mkdir -p "$REPORT_DIR"

REPORT_FILE="$REPORT_DIR/weekly_report_$(date +%Y%m%d).txt"

{
    echo "DIFY容器管理API周报"
    echo "===================="
    echo "报告时间: $(date)"
    echo ""
    
    # API调用统计
    echo "API调用统计:"
    if [ -f /tmp/container_manager.log ]; then
        echo "- 创建容器请求: $(grep "POST /create" /tmp/container_manager.log | wc -l)"
        echo "- 销毁容器请求: $(grep "POST /destroy" /tmp/container_manager.log | wc -l)"
        echo "- 健康检查请求: $(grep "GET /health" /tmp/container_manager.log | wc -l)"
        echo "- 列表查询请求: $(grep "GET /list" /tmp/container_manager.log | wc -l)"
    fi
    echo ""
    
    # 容器使用统计
    echo "容器使用统计:"
    echo "- 当前活跃容器: $(docker ps --filter "name=dify-user" | wc -l)"
    echo ""
    
    # 资源使用
    echo "资源使用情况:"
    echo "- 磁盘使用: $(df -h ~ | tail -1 | awk '{print $5}')"
    echo "- 用户数据总大小: $(du -sh ~/dify_data 2>/dev/null | cut -f1)"
    echo ""
    
    # 错误统计
    echo "错误统计:"
    if [ -f /tmp/container_manager.log ]; then
        echo "- 错误总数: $(grep -i "error\|exception" /tmp/container_manager.log | wc -l)"
        echo "- 最近错误:"
        grep -i "error\|exception" /tmp/container_manager.log | tail -5
    fi
    
} > "$REPORT_FILE"

echo "报告已生成: $REPORT_FILE"
EOF

# 创建月度清理脚本
sudo tee "$MAINT_DIR/monthly_cleanup.sh" > /dev/null << 'EOF'
#!/bin/bash
# 月度清理任务

echo "执行月度清理任务 - $(date)"

# 清理30天未使用的用户目录
echo "清理30天未使用的用户目录..."
find ~/dify_data -name ".initialized" -mtime +30 | while read init_file; do
    user_dir=$(dirname "$init_file")
    echo "删除: $user_dir"
    rm -rf "$user_dir"
done

# 清理Docker未使用的镜像
echo "清理未使用的Docker镜像..."
docker image prune -a -f

# 清理旧日志
echo "清理旧日志文件..."
find /var/log/dify-api -name "*.log" -mtime +30 -delete
find /tmp -name "container_manager.log.*" -mtime +7 -delete

# 压缩当前日志
if [ -f /tmp/container_manager.log ]; then
    cp /tmp/container_manager.log "/tmp/container_manager.log.$(date +%Y%m%d)"
    > /tmp/container_manager.log
    gzip "/tmp/container_manager.log.$(date +%Y%m%d)"
fi

echo "月度清理完成"
EOF

# 设置脚本权限
sudo chmod +x "$MAINT_DIR"/*.sh

# 显示当前crontab
echo "当前crontab配置:"
crontab -l 2>/dev/null || echo "（空）"
echo ""

# 询问是否安装
read -p "是否安装这些定时任务？[y/N] " -n 1 -r
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    # 备份现有crontab
    crontab -l > /tmp/crontab.backup 2>/dev/null || true
    
    # 添加新任务
    (crontab -l 2>/dev/null || true; cat /tmp/dify-api-cron) | crontab -
    
    echo "定时任务已安装"
    echo ""
    echo "查看当前定时任务:"
    crontab -l | grep dify
    echo ""
    echo "日志文件位置: /var/log/dify-api/"
else
    echo "跳过定时任务安装"
    echo ""
    echo "您可以手动添加以下内容到crontab:"
    cat /tmp/dify-api-cron
fi

# 清理临时文件
rm -f /tmp/dify-api-cron

echo ""
echo "维护建议:"
echo "1. 定期检查 /var/log/dify-api/ 中的日志"
echo "2. 根据实际使用情况调整定时任务频率"
echo "3. 监控磁盘空间，避免日志占满磁盘"
echo "4. 定期查看周报了解使用情况"
