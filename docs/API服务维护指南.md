# MATLAB容器管理API服务维护指南

## 一、服务概述

### 服务信息
- **服务名称**：MATLAB Container Manager API
- **服务文件**：`container_manager.py`
- **监听端口**：8080
- **框架**：Flask (Python3)
- **功能**：管理MATLAB Docker容器的生命周期

## 二、日常维护操作

### 2.1 服务启动/停止

#### 手动启动
```bash
# 前台运行（调试模式）
cd /home/zhangbo/workspace/ContainerManagerAPI
python3 container_manager.py

# 后台运行
nohup python3 container_manager.py > /tmp/container_manager.log 2>&1 &

# 查看进程ID
ps aux | grep container_manager
```

#### 使用systemd管理（推荐）
```bash
# 安装服务
sudo cp matlab-container-manager.service /etc/systemd/system/
sudo systemctl daemon-reload

# 启动服务
sudo systemctl start matlab-container-manager

# 停止服务
sudo systemctl stop matlab-container-manager

# 重启服务
sudo systemctl restart matlab-container-manager

# 查看状态
sudo systemctl status matlab-container-manager

# 设置开机自启
sudo systemctl enable matlab-container-manager
```

### 2.2 日志管理

#### 查看日志
```bash
# systemd服务日志
sudo journalctl -u matlab-container-manager -f

# 查看最近100行
sudo journalctl -u matlab-container-manager -n 100

# 按时间查看
sudo journalctl -u matlab-container-manager --since "2024-01-15 10:00:00"

# 手动启动的日志
tail -f /tmp/container_manager.log
```

#### 日志轮转配置
创建 `/etc/logrotate.d/container-manager`:
```
/tmp/container_manager.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    create 0644 zhangbo zhangbo
    postrotate
        pkill -USR1 -f container_manager.py
    endscript
}
```

### 2.3 健康检查

#### API健康检查脚本
```bash
#!/bin/bash
# health_check.sh

API_URL="http://localhost:8080"

# 检查API响应
if curl -s "$API_URL" > /dev/null; then
    echo "✅ API服务正常"
else
    echo "❌ API服务异常"
    exit 1
fi

# 检查端口
if netstat -tln | grep -q ":8080 "; then
    echo "✅ 端口8080正常监听"
else
    echo "❌ 端口8080未监听"
    exit 1
fi

# 检查进程
if pgrep -f container_manager.py > /dev/null; then
    echo "✅ 进程运行正常"
else
    echo "❌ 进程未运行"
    exit 1
fi
```

## 三、监控配置

### 3.1 Prometheus监控

创建监控端点（修改container_manager.py）：
```python
from prometheus_client import Counter, Histogram, Gauge, generate_latest

# 定义指标
api_requests = Counter('api_requests_total', 'Total API requests', ['method', 'endpoint'])
api_latency = Histogram('api_latency_seconds', 'API latency')
active_containers = Gauge('active_containers', 'Number of active containers')

@app.route('/metrics')
def metrics():
    return generate_latest()
```

### 3.2 监控告警规则

```yaml
# prometheus-alerts.yml
groups:
  - name: container_manager
    rules:
      - alert: APIServiceDown
        expr: up{job="container-manager"} == 0
        for: 5m
        annotations:
          summary: "Container Manager API is down"
          
      - alert: HighAPILatency
        expr: api_latency_seconds > 2
        for: 10m
        annotations:
          summary: "API latency is high"
          
      - alert: TooManyContainers
        expr: active_containers > 90
        for: 5m
        annotations:
          summary: "Too many active containers (>90)"
```

### 3.3 性能监控脚本

```bash
#!/bin/bash
# monitor_api.sh

while true; do
    # CPU和内存使用
    PID=$(pgrep -f container_manager.py)
    if [ -n "$PID" ]; then
        ps -p $PID -o %cpu,%mem,cmd --no-headers
    fi
    
    # API响应时间
    START=$(date +%s.%N)
    curl -s http://localhost:8080/list > /dev/null
    END=$(date +%s.%N)
    LATENCY=$(echo "$END - $START" | bc)
    echo "API响应时间: ${LATENCY}秒"
    
    # 活跃容器数
    CONTAINERS=$(curl -s http://localhost:8080/list | jq '.total')
    echo "活跃容器数: $CONTAINERS"
    
    sleep 60
done
```

## 四、故障处理

### 4.1 常见问题及解决方案

#### 问题1：API服务无响应
```bash
# 1. 检查进程
ps aux | grep container_manager

# 2. 检查端口
netstat -tln | grep 8080

# 3. 检查日志
sudo journalctl -u matlab-container-manager -n 50

# 4. 重启服务
sudo systemctl restart matlab-container-manager
```

#### 问题2：端口被占用
```bash
# 查找占用进程
sudo lsof -i :8080

# 强制释放端口
sudo fuser -k 8080/tcp

# 重启服务
sudo systemctl restart matlab-container-manager
```

#### 问题3：内存泄漏
```bash
# 监控内存使用
watch -n 1 'ps aux | grep container_manager'

# 临时解决：定期重启
# 添加到crontab
0 3 * * * /bin/systemctl restart matlab-container-manager
```

### 4.2 紧急恢复流程

```bash
#!/bin/bash
# emergency_recovery.sh

echo "🚨 执行紧急恢复..."

# 1. 停止服务
sudo systemctl stop matlab-container-manager

# 2. 清理遗留进程
pkill -f container_manager.py

# 3. 释放端口
sudo fuser -k 8080/tcp

# 4. 备份日志
cp /tmp/container_manager.log /tmp/container_manager.log.$(date +%Y%m%d_%H%M%S)

# 5. 清理临时文件
rm -f /tmp/container_manager.pid

# 6. 重启服务
sudo systemctl start matlab-container-manager

# 7. 验证服务
sleep 5
if curl -s http://localhost:8080 > /dev/null; then
    echo "✅ 服务恢复成功"
else
    echo "❌ 服务恢复失败，请检查日志"
fi
```

## 五、性能优化

### 5.1 API优化建议

#### 添加缓存
```python
from functools import lru_cache
import time

# 缓存容器列表（5秒过期）
@lru_cache(maxsize=1)
def get_container_list_cached():
    return list_containers_internal()

# 定期清理缓存
def clear_cache():
    while True:
        time.sleep(5)
        get_container_list_cached.cache_clear()
```

#### 异步处理
```python
from concurrent.futures import ThreadPoolExecutor
executor = ThreadPoolExecutor(max_workers=10)

@app.route('/create', methods=['POST'])
def create_container():
    # 异步创建容器
    future = executor.submit(create_container_async, user_id)
    return jsonify({"message": "Container creation initiated"}), 202
```

### 5.2 系统优化

#### 调整文件描述符限制
```bash
# /etc/security/limits.conf
* soft nofile 65536
* hard nofile 65536
```

#### 优化Python性能
```bash
# 使用生产级WSGI服务器
pip install gunicorn

# 启动命令
gunicorn -w 4 -b 0.0.0.0:8080 container_manager:app
```

## 六、安全维护

### 6.1 访问控制

#### 添加基础认证
```python
from functools import wraps
from flask import request, Response

def check_auth(username, password):
    return username == 'admin' and password == 'secure_password'

def authenticate():
    return Response('Authentication required', 401,
                   {'WWW-Authenticate': 'Basic realm="Login Required"'})

def requires_auth(f):
    @wraps(f)
    def decorated(*args, **kwargs):
        auth = request.authorization
        if not auth or not check_auth(auth.username, auth.password):
            return authenticate()
        return f(*args, **kwargs)
    return decorated

# 应用到所有路由
@app.before_request
@requires_auth
def before_request():
    pass
```

### 6.2 安全加固

```bash
# 1. 限制访问源（iptables）
sudo iptables -A INPUT -p tcp --dport 8080 -s 13.229.200.109 -j ACCEPT
sudo iptables -A INPUT -p tcp --dport 8080 -j DROP

# 2. 使用HTTPS（nginx反代）
server {
    listen 443 ssl;
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;
    
    location / {
        proxy_pass http://localhost:8080;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

## 七、备份与恢复

### 7.1 配置备份

```bash
#!/bin/bash
# backup_api_config.sh

BACKUP_DIR="/backup/api_service/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"

# 备份服务文件
cp container_manager.py "$BACKUP_DIR/"
cp matlab-container-manager.service "$BACKUP_DIR/"

# 备份启动脚本
cp start_matlab_multi_user.sh "$BACKUP_DIR/"

# 打包压缩
tar -czf "$BACKUP_DIR.tar.gz" "$BACKUP_DIR"
rm -rf "$BACKUP_DIR"

echo "✅ 备份完成: $BACKUP_DIR.tar.gz"
```

### 7.2 服务迁移

```bash
# 导出容器列表
curl http://localhost:8080/list > containers_backup.json

# 在新服务器上恢复
# 1. 复制所有脚本和配置
# 2. 安装依赖
pip3 install flask

# 3. 恢复用户数据
rsync -av ~/matlab_data/ newserver:~/matlab_data/

# 4. 启动服务
sudo systemctl start matlab-container-manager
```

## 八、定期维护任务

### 每日任务
- [ ] 检查API服务状态
- [ ] 查看错误日志
- [ ] 监控资源使用

### 每周任务
- [ ] 分析API调用统计
- [ ] 清理过期日志
- [ ] 性能基准测试

### 每月任务
- [ ] 更新依赖包
- [ ] 安全漏洞扫描
- [ ] 容量规划评估

## 九、故障升级流程

### Level 1 - 自动恢复（5分钟）
- 服务自动重启
- 基础健康检查

### Level 2 - 运维介入（15分钟）
- 手动排查日志
- 重启相关服务
- 临时扩容

### Level 3 - 紧急响应（30分钟）
- 切换备用服务
- 回滚到上个版本
- 通知相关团队

## 十、运维工具箱

### 快速诊断命令
```bash
# 一键诊断
alias api-status='systemctl status matlab-container-manager'
alias api-logs='journalctl -u matlab-container-manager -f'
alias api-restart='systemctl restart matlab-container-manager'
alias api-test='curl -s http://localhost:8080/ | jq'
```

### 性能分析
```bash
# API调用统计
grep "POST /create" /tmp/container_manager.log | wc -l

# 响应时间分析
grep "took" /tmp/container_manager.log | awk '{print $NF}' | sort -n | tail -10
```

### 容器清理
```bash
# 清理所有停止的容器
docker rm $(docker ps -aq -f status=exited -f name=matlab-user)

# 清理未使用的镜像
docker image prune -a
```

---

**重要联系人**：
- 运维负责人：[姓名] [电话]
- 值班电话：[电话]
- 邮件列表：[邮箱]

**相关文档**：
- [API接口文档](./服务器C接口说明文档.md)
- [部署指南](./deploy_multi_user.sh)
- [故障处理手册](./故障处理.md)

