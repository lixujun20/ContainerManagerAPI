# MATLAB容器管理系统 API 接口文档

> **文档版本**: v1.0  
> **最后更新**: 2025-10-05  
> **服务地址**: 服务器C (166.111.7.155)

## 目录
- [1. 系统架构](#1-系统架构)
- [2. 数据模型设计](#2-数据模型设计)
- [3. 容器管理API](#3-容器管理api)
- [4. 资源配额与限制](#4-资源配额与限制)
- [5. 监控与运维](#5-监控与运维)

---

## 1. 系统架构

### 1.1 三层架构设计

```
服务器A (外网)          服务器B (桥梁)           服务器C (内网)
47.129.183.233  ←→  13.229.200.109  ←VPN→  166.111.7.155
   前端/API            路由/管理              容器运行
      |                    |                      |
      ├── 用户界面         ├── Bridge API         ├── Container Manager API
      ├── 会话管理         ├── 端口转发           ├── Docker容器管理
      └── 用户认证         └── 请求路由           └── 资源调度
```

### 1.2 服务器C核心职责

| 职责 | 说明 | 技术实现 |
|-----|------|---------|
| 容器托管 | 运行所有用户的MATLAB Docker容器 | Docker Engine |
| 资源管理 | CPU、内存、存储的分配和隔离 | Cgroups + Namespace |
| 服务暴露 | 为每个容器提供HTTP和WebSocket服务 | 端口映射(30001-30100, 31001-31100) |
| 数据持久化 | 用户工作空间和数据存储 | Volume挂载 |
| API管理 | 容器生命周期管理接口 | Flask RESTful API |

### 1.3 端口分配规则

```
用户ID → 端口计算公式：
- HTTP端口 = 30000 + 用户ID
- WebSocket端口 = 31000 + 用户ID

示例：
- 用户1:   HTTP=30001, WebSocket=31001
- 用户50:  HTTP=30050, WebSocket=31050
- 用户100: HTTP=30100, WebSocket=31100
```

### 1.4 容器命名规则

```
容器名称格式：matlab-user-{用户ID}
数据目录格式：~/matlab_data/user_{用户ID}

示例：
- 用户1: 容器名=matlab-user-1, 目录=~/matlab_data/user_1
- 用户42: 容器名=matlab-user-42, 目录=~/matlab_data/user_42
```

---

## 2. 数据模型设计

### 2.1 容器配置模型

```javascript
{
  container_id: String,        // 容器ID，格式："matlab-user-{1-100}"
  user_id: Number,            // 用户ID，范围：1-100
  status: String,             // 容器状态：running/stopped/paused/exited
  created_at: Date,           // 创建时间
  started_at: Date,           // 启动时间
  
  ports: {
    http_port: Number,        // HTTP服务端口，计算：30000 + user_id
    ws_port: Number           // WebSocket端口，计算：31000 + user_id
  },
  
  resources: {
    cpu_limit: String,        // CPU限制，默认："2"（2核心）
    memory_limit: String,     // 内存限制，默认："4g"（4GB）
    shm_size: String          // 共享内存，默认："4G"
  },
  
  storage: {
    data_dir: String,         // 数据目录：~/matlab_data/user_{user_id}
    shared_mount: String,     // 容器内挂载点：/home/matlab/shared
    log_file: String          // 日志文件路径
  },
  
  environment: {
    user_id: Number,          // 用户ID环境变量
    license_server: String,   // 许可证服务器地址
    context_tags: String      // MATLAB上下文标签
  }
}
```

### 2.2 健康状态模型

```javascript
{
  container_id: String,        // 容器ID
  status: String,             // 状态：running/stopped
  started_at: String,         // 启动时间（ISO 8601格式）
  uptime: Number,             // 运行时长（秒）
  
  resource_usage: {
    cpu_usage: String,        // CPU使用率，如："2.74%"
    memory_usage: String,     // 内存使用量，如："2.302GiB"
    memory_percent: String    // 内存使用率，如："57.5%"
  },
  
  service_health: {
    web_service: String,      // Web服务状态：healthy/unhealthy
    websocket_service: String // WebSocket状态：healthy/unhealthy
  },
  
  ports: {
    http_port: Number,        // HTTP端口
    ws_port: Number           // WebSocket端口
  }
}
```

### 2.3 用户数据目录结构

```
~/matlab_data/
└── user_{用户ID}/
    ├── commands/           # 命令队列目录
    ├── results/           # 计算结果目录
    ├── scripts/           # 用户脚本目录
    ├── logs/              # 日志文件目录
    │   └── container.log  # 容器日志
    ├── command_queue/     # 命令队列
    ├── models/            # 模型文件目录
    └── Documents/
        └── MATLAB/
            └── startup.m  # MATLAB启动脚本
```

### 2.4 数据存储说明

#### 配置存储

系统配置在API服务启动时加载，存储位置由代码定义：

| 配置项 | 代码位置 | 值 | 说明 |
|--------|---------|-----|------|
| BASE_DATA_DIR | `container_manager.py:17` | `~/matlab_data` | 用户数据根目录 |
| MAX_USERS | `container_manager.py:18` | `100` | 最大用户数限制 |
| START_SCRIPT | `container_manager.py:19` | 同目录下的 `start_matlab_multi_user.sh` | 容器启动脚本路径 |
| 容器命名规则 | `container_manager.py:21-23` | `matlab-user-{user_id}` | get_container_name() 函数 |
| 端口分配规则 | `container_manager.py:25-30` | HTTP: 30000+user_id<br>WS: 31000+user_id | get_ports() 函数 |

#### 运行时数据存储

**用户工作空间**:
- 路径: `~/matlab_data/user_{user_id}/`
- 持久化: 容器销毁后数据仍保留在磁盘
- 挂载: 映射到容器内的 `/home/matlab/shared`
- 创建: 由 `start_matlab_multi_user.sh` 在容器启动时初始化

**容器元数据**:
- 存储: Docker内部存储（通过Docker API管理）
- 包含: 容器配置、网络设置、资源限制、环境变量
- 查询: 通过 `docker inspect <container_name>` 获取

**日志文件**:
- API服务日志: `/tmp/container_manager.log` (服务级别)
- 容器日志: 通过 `docker logs <container_name>` 查看
- 用户日志: `~/matlab_data/user_{user_id}/logs/` (用户级别)

#### 数据持久化策略

**持久化数据** (容器销毁后保留):
- 用户工作文件和脚本
- MATLAB计算结果
- 用户自定义配置
- startup.m 启动脚本

**临时数据** (容器销毁后清除):
- 容器实例及其配置
- 容器内的 MATLAB 运行状态
- 临时文件系统内容

**数据管理建议**:
- 定期备份 `~/matlab_data/` 目录
- 对于不再使用的用户，手动删除 `~/matlab_data/user_{user_id}/` 释放空间
- 容器重启会重新加载 startup.m，确保 WebSocket 服务自动启动

---

## 3. 容器管理API

### 3.1 创建容器

**接口名称**: 创建MATLAB容器

**功能描述**: 为指定用户创建并启动MATLAB Docker容器，自动分配端口和资源，配置用户独立的工作环境

**入参**: 
- user_id: number - 用户ID，必填，范围1-100
- session_id: string - 会话ID，可选，用于日志关联和调试

**返回参数**: 
- container_id: string - 容器标识符，格式："matlab-user-{user_id}"
- http_port: number - HTTP服务端口
- ws_port: number - WebSocket服务端口
- status: string - 容器状态，值：running（新建）或 already_running（已存在）
- message: string - 操作结果描述

**url地址**: `/create`

**请求方式**: `POST`

**请求示例**:
```bash
# 创建用户1的容器
curl -X POST http://166.111.7.155:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"user_id": 1, "session_id": "550e8400-e29b-41d4-a716-446655440000"}'

# 批量创建（用户1-5）
for i in {1..5}; do
  curl -X POST http://166.111.7.155:8080/create \
    -H 'Content-Type: application/json' \
    -d "{\"user_id\": $i}"
  sleep 2  # 避免并发压力
done
```

**成功响应** (201 Created - 新建容器):
```json
{
  "container_id": "matlab-user-1",
  "http_port": 30001,
  "ws_port": 31001,
  "status": "running",
  "message": "Container created successfully"
}
```

**成功响应** (200 OK - 容器已存在):
```json
{
  "container_id": "matlab-user-1",
  "http_port": 30001,
  "ws_port": 31001,
  "status": "already_running",
  "message": "Container is already running"
}
```

**错误响应** (400 Bad Request - 参数错误):
```json
{
  "error": "Invalid user_id. Must be between 1 and 100"
}
```

**错误响应** (500 Internal Server Error - 服务器错误):
```json
{
  "error": "Failed to create container: [详细错误信息]"
}
```

**注意事项**:
- 容器启动需要15-20秒，请耐心等待
- 如果容器已存在，将直接返回现有容器信息
- 同一用户ID只能创建一个容器实例
- 建议同时创建容器数量不超过10个

---

### 3.2 销毁容器

**接口名称**: 销毁MATLAB容器

**功能描述**: 停止并删除指定的MATLAB容器，释放占用的端口和系统资源，用户数据保留在磁盘上

**路径参数**:
- container_id: string - 容器ID（必需），格式："matlab-user-{1-100}"，在URL路径中指定

**入参**: 
- 无需其他入参

**返回参数**: 
- message: string - 操作结果描述
- container_id: string - 被销毁的容器ID

**url地址**: `/destroy/{container_id}`

**请求方式**: `POST`

**请求示例**:
```bash
# 销毁用户1的容器
curl -X POST http://166.111.7.155:8080/destroy/matlab-user-1

# 批量销毁（用户1-5）
for i in {1..5}; do
  curl -X POST http://166.111.7.155:8080/destroy/matlab-user-$i
done
```

**成功响应** (200 OK):
```json
{
  "message": "Container destroyed successfully",
  "container_id": "matlab-user-1"
}
```

**容器不存在响应** (404 Not Found):
```json
{
  "message": "Container not found",
  "container_id": "matlab-user-1"
}
```

**错误响应** (500 Internal Server Error):
```json
{
  "error": "Failed to destroy container: [详细错误信息]"
}
```

**注意事项**:
- 销毁容器会立即停止所有运行中的MATLAB进程
- 用户数据目录不会被删除，仅删除容器实例
- 销毁后的端口会立即释放，可供其他操作使用
- 如需清理用户数据，需手动删除 `~/matlab_data/user_{user_id}` 目录

---

### 3.3 健康检查

**接口名称**: 容器健康检查

**功能描述**: 获取指定容器的运行状态、资源使用情况和服务健康状态，用于监控和故障诊断

**路径参数**:
- container_id: string - 容器ID（必需），在URL路径中指定

**入参**: 
- 无需其他入参

**返回参数**: 
- container_id: string - 容器ID
- status: string - 容器状态：running（运行中）/stopped（已停止）
- started_at: string - 启动时间（ISO 8601格式）
- cpu_usage: string - CPU使用率
- memory_usage: string - 内存使用量
- memory_percent: string - 内存使用百分比
- web_service: string - Web服务健康状态：healthy/unhealthy
- websocket_service: string - WebSocket服务健康状态：healthy/unhealthy
- http_port: number - HTTP服务端口
- ws_port: number - WebSocket服务端口

**url地址**: `/health/{container_id}`

**请求方式**: `GET`

**请求示例**:
```bash
# 检查用户1的容器
curl http://166.111.7.155:8080/health/matlab-user-1

# 监控脚本：每30秒检查一次
while true; do
  curl -s http://166.111.7.155:8080/health/matlab-user-1 | jq '.'
  sleep 30
done
```

**成功响应** (200 OK - 容器运行中):
```json
{
  "container_id": "matlab-user-1",
  "status": "running",
  "started_at": "2025-10-05T10:30:00.000Z",
  "cpu_usage": "2.74%",
  "memory_usage": "2.302GiB",
  "memory_percent": "57.5%",
  "web_service": "healthy",
  "websocket_service": "healthy",
  "http_port": 30001,
  "ws_port": 31001
}
```

**容器停止响应** (200 OK - 容器已停止):
```json
{
  "container_id": "matlab-user-1",
  "status": "stopped",
  "started_at": "unknown"
}
```

**容器不存在响应** (404 Not Found):
```json
{
  "error": "Container not found",
  "container_id": "matlab-user-1"
}
```

**注意事项**:
- 健康检查包含端口可达性测试，可能需要1-2秒响应时间
- `web_service` 通过HTTP GET请求测试
- `websocket_service` 通过TCP端口连接测试
- 建议监控频率不超过1次/30秒，避免资源消耗

---

### 3.4 列出所有容器

**接口名称**: 获取容器列表

**功能描述**: 获取当前所有MATLAB容器的概览信息，包括容器ID、用户ID、状态和端口信息

**入参**: 
- 无需入参

**返回参数**: 
- total: number - 容器总数
- containers: array - 容器列表
  - container_id: string - 容器ID
  - user_id: number - 用户ID
  - status: string - 容器状态
  - created: string - 创建时间
  - http_port: number - HTTP端口
  - ws_port: number - WebSocket端口

**url地址**: `/list`

**请求方式**: `GET`

**请求示例**:
```bash
# 获取所有容器列表
curl http://166.111.7.155:8080/list

# 格式化输出
curl -s http://166.111.7.155:8080/list | jq '.'

# 统计运行中的容器
curl -s http://166.111.7.155:8080/list | jq '.containers[] | select(.status=="running") | .container_id'
```

**成功响应** (200 OK):
```json
{
  "total": 3,
  "containers": [
    {
      "container_id": "matlab-user-1",
      "user_id": 1,
      "status": "running",
      "created": "2025-10-05 10:30:00",
      "http_port": 30001,
      "ws_port": 31001
    },
    {
      "container_id": "matlab-user-2",
      "user_id": 2,
      "status": "running",
      "created": "2025-10-05 10:31:00",
      "http_port": 30002,
      "ws_port": 31002
    },
    {
      "container_id": "matlab-user-42",
      "user_id": 42,
      "status": "stopped",
      "created": "2025-10-05 09:15:00",
      "http_port": 30042,
      "ws_port": 31042
    }
  ]
}
```

**空列表响应** (200 OK):
```json
{
  "total": 0,
  "containers": []
}
```

**注意事项**:
- 返回所有状态的容器（运行中和已停止）
- 容器按名称排序（用户ID升序）
- `created` 时间为容器首次创建时间，非本次启动时间
- 建议定期调用此接口清理僵尸容器

---

### 3.5 重启容器

**接口名称**: 重启MATLAB容器

**功能描述**: 重启指定的MATLAB容器，用于故障恢复或强制重新加载配置，所有运行中的进程将被终止

**路径参数**:
- container_id: string - 容器ID（必需），在URL路径中指定

**入参**: 
- 无需其他入参

**返回参数**: 
- message: string - 操作结果描述
- container_id: string - 被重启的容器ID

**url地址**: `/restart/{container_id}`

**请求方式**: `POST`

**请求示例**:
```bash
# 重启用户1的容器
curl -X POST http://166.111.7.155:8080/restart/matlab-user-1

# 批量重启（用户1-5）
for i in {1..5}; do
  curl -X POST http://166.111.7.155:8080/restart/matlab-user-$i
  sleep 5  # 等待容器启动
done
```

**成功响应** (200 OK):
```json
{
  "message": "Container restarted successfully",
  "container_id": "matlab-user-1"
}
```

**容器不存在响应** (404 Not Found):
```json
{
  "error": "Container not found",
  "container_id": "matlab-user-1"
}
```

**错误响应** (500 Internal Server Error):
```json
{
  "error": "Failed to restart container: [详细错误信息]"
}
```

**注意事项**:
- 重启过程需要20-30秒，包括停止、启动和服务初始化
- 容器内所有未保存的MATLAB工作空间数据将丢失
- 重启不会改变端口分配和资源限制
- 建议在用户无活动时进行重启操作
- 重启后需等待MATLAB服务完全启动才能使用（约10-15秒）

---

## 4. 资源配额与限制

### 4.1 容器资源限制

| 资源类型 | 默认配额 | 说明 | 可调整 |
|---------|---------|------|--------|
| CPU核心 | 2核 | 每容器最多使用2个CPU核心 | ✅ 是 |
| 内存 | 4GB | 每容器最大内存使用量 | ✅ 是 |
| 共享内存 | 4GB | 容器内/dev/shm大小 | ✅ 是 |
| 磁盘空间 | 10GB | 用户数据目录软限制 | ✅ 是 |
| 进程数 | 无限制 | 容器内进程数量 | ❌ 否 |
| 网络带宽 | 共享 | 无单独限制 | ❌ 否 |

**资源配置示例**:
```bash
# 修改启动脚本中的资源限制
MEMORY_LIMIT="4g"    # 可改为 "8g" 提升至8GB
CPU_LIMIT="2"        # 可改为 "4" 提升至4核
```

### 4.2 系统级限制

| 限制项 | 值 | 说明 |
|-------|---|------|
| 最大用户数 | 100 | 用户ID范围：1-100 |
| HTTP端口范围 | 30001-30100 | 100个端口 |
| WebSocket端口范围 | 31001-31100 | 100个端口 |
| API端口 | 8080 | 容器管理API固定端口 |
| 建议并发创建 | ≤10个/分钟 | 避免资源竞争 |
| API并发请求 | ≤100个/秒 | Flask服务限制 |

### 4.3 性能指标

| 指标 | 目标值 | 监控方法 |
|-----|--------|---------|
| 容器启动时间 | < 30秒 | 从create请求到服务可用 |
| API响应时间 | < 500ms | /list、/health接口 |
| WebSocket延迟 | < 100ms | 同数据中心网络 |
| 系统可用性 | > 99% | 按月统计 |
| CPU使用率 | < 80% | 系统级监控 |
| 内存使用率 | < 85% | 系统级监控 |

### 4.4 端口快速查询表

```
用户1-10:   HTTP 30001-30010, WS 31001-31010
用户11-20:  HTTP 30011-30020, WS 31011-31020
用户21-30:  HTTP 30021-30030, WS 31021-31030
用户31-40:  HTTP 30031-30040, WS 31031-31040
用户41-50:  HTTP 30041-30050, WS 31041-31050
用户51-60:  HTTP 30051-30060, WS 31051-31060
用户61-70:  HTTP 30061-30070, WS 31061-31070
用户71-80:  HTTP 30071-30080, WS 31071-31080
用户81-90:  HTTP 30081-30090, WS 31081-31090
用户91-100: HTTP 30091-30100, WS 31091-31100
```

---

## 5. 监控与运维

### 5.1 服务启动与停止

#### 5.1.1 手动启动API服务
```bash
# 前台运行（调试模式）
cd /home/zhangbo/workspace/edumanus/edumanus/matlab_websocket/docs
python3 container_manager.py

# 后台运行
nohup python3 container_manager.py > /tmp/container_manager.log 2>&1 &

# 查看进程
ps aux | grep container_manager
```

#### 5.1.2 使用systemd管理（推荐）
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

#### 5.1.3 查看服务日志
```bash
# systemd服务日志
sudo journalctl -u matlab-container-manager -f

# 查看最近100行
sudo journalctl -u matlab-container-manager -n 100

# 按时间查看
sudo journalctl -u matlab-container-manager --since "2025-10-05 10:00:00"

# 手动启动的日志
tail -f /tmp/container_manager.log
```

### 5.2 健康检查脚本

```bash
#!/bin/bash
# health_check.sh - API服务健康检查

API_URL="http://localhost:8080"

# 检查API响应
if curl -s "$API_URL/list" > /dev/null; then
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

### 5.3 故障处理流程

#### 5.3.1 容器无法启动
```bash
# 1. 检查端口占用
netstat -tulpn | grep 30001

# 2. 查看Docker日志
docker logs matlab-user-1

# 3. 检查镜像是否存在
docker images | grep matlab

# 4. 清理并重试
docker rm -f matlab-user-1
curl -X POST http://localhost:8080/create -d '{"user_id": 1}'
```

#### 5.3.2 Web服务不可访问
```bash
# 1. 检查容器状态
curl http://localhost:8080/health/matlab-user-1

# 2. 重启容器
curl -X POST http://localhost:8080/restart/matlab-user-1

# 3. 手动检查端口
curl -I http://localhost:30001/
```

#### 5.3.3 API服务无响应
```bash
# 1. 检查进程
ps aux | grep container_manager

# 2. 检查端口
netstat -tln | grep 8080

# 3. 查看日志
sudo journalctl -u matlab-container-manager -n 50

# 4. 重启服务
sudo systemctl restart matlab-container-manager
```

#### 5.3.4 资源不足
```bash
# 1. 查看所有容器
curl http://localhost:8080/list

# 2. 清理停止的容器
docker rm $(docker ps -aq -f status=exited -f name=matlab-user)

# 3. 清理未使用的镜像
docker image prune -a

# 4. 检查磁盘空间
df -h
```

### 5.4 批量管理工具

```bash
#!/bin/bash
# manage_multi_user.sh - 批量管理脚本

# 批量启动容器（用户1-5）
for i in {1..5}; do
  curl -X POST http://localhost:8080/create -d "{\"user_id\": $i}"
  sleep 2
done

# 批量健康检查
for i in {1..100}; do
  status=$(curl -s http://localhost:8080/health/matlab-user-$i | jq -r '.status')
  if [ "$status" == "running" ]; then
    echo "✅ 用户$i: 运行中"
  fi
done

# 批量销毁容器
for i in {1..5}; do
  curl -X POST http://localhost:8080/destroy/matlab-user-$i
done
```

### 5.5 性能监控

```bash
#!/bin/bash
# monitor_performance.sh - 性能监控脚本

while true; do
  echo "=== $(date) ==="
  
  # API响应时间
  START=$(date +%s.%N)
  curl -s http://localhost:8080/list > /dev/null
  END=$(date +%s.%N)
  LATENCY=$(echo "$END - $START" | bc)
  echo "API响应时间: ${LATENCY}秒"
  
  # 活跃容器数
  TOTAL=$(curl -s http://localhost:8080/list | jq '.total')
  echo "活跃容器数: $TOTAL"
  
  # 系统资源
  echo "CPU使用率: $(top -bn1 | grep "Cpu(s)" | awk '{print $2}')"
  echo "内存使用率: $(free | grep Mem | awk '{print ($3/$2) * 100.0"%"}')"
  
  echo ""
  sleep 60
done
```

---

## 通用错误响应

所有接口在发生错误时都会返回统一的错误响应格式：

```json
{
  "error": "错误描述信息"
}
```

### 常见错误码

| 状态码 | 含义 | 处理建议 |
|-------|------|---------|
| 200 | 成功（容器已存在） | 直接使用返回的端口信息 |
| 201 | 成功（新建容器） | 等待15-20秒后开始使用 |
| 400 | 参数错误 | 检查user_id范围（1-100） |
| 404 | 容器不存在 | 先调用/create创建容器 |
| 500 | 服务器内部错误 | 重试或联系运维人员 |

### 错误场景说明

#### 用户ID错误
```json
{
  "error": "Invalid user_id. Must be between 1 and 100"
}
```
**原因**: user_id不在1-100范围内或类型不正确  
**解决**: 检查请求参数，确保user_id为1-100的整数

#### 容器创建失败
```json
{
  "error": "Failed to create container: port 30001 already in use"
}
```
**原因**: 端口被占用或Docker资源不足  
**解决**: 检查端口占用情况，清理僵尸容器或重启Docker服务

#### 容器不存在
```json
{
  "error": "Container not found",
  "container_id": "matlab-user-99"
}
```
**原因**: 容器从未创建或已被删除  
**解决**: 先调用/create接口创建容器

---

## 认证说明

### 当前版本
- **认证方式**: 无认证（依赖网络隔离）
- **访问控制**: 仅接受来自服务器B (13.229.200.109) 的请求
- **网络安全**: 通过VPN隧道加密传输

### 安全建议
1. **网络隔离**: 确保服务器C不直接暴露在公网
2. **防火墙规则**: 限制8080端口仅允许服务器B访问
3. **VPN连接**: 保持服务器B与服务器C之间的VPN稳定连接
4. **日志审计**: 定期检查API访问日志，发现异常访问

### 未来增强
- [ ] 添加Token认证机制
- [ ] 实现IP白名单功能
- [ ] 集成TLS/SSL加密
- [ ] 添加请求限流功能

---

## 集成指南

### 典型调用流程

```
1. 服务器B收到用户MATLAB访问请求
   ↓
2. 调用 POST /create 创建容器（附带session_id）
   ↓
3. 等待容器启动（15-20秒）
   ↓
4. 调用 GET /health 验证服务就绪
   ↓
5. 获取分配的http_port和ws_port
   ↓
6. 将端口信息返回给服务器A
   ↓
7. 用户通过iframe访问MATLAB Web界面
   ↓
8. 定期调用 GET /health 监控容器状态（每5分钟）
   ↓
9. 用户会话结束后调用 POST /destroy 释放资源
```

### Python集成示例

```python
import requests
import time

class MatlabContainerClient:
    def __init__(self, base_url="http://166.111.7.155:8080"):
        self.base_url = base_url
        self.timeout = 30
    
    def create_container(self, user_id, session_id=None, max_retries=3):
        """创建MATLAB容器，支持重试"""
        url = f"{self.base_url}/create"
        data = {"user_id": user_id}
        if session_id:
            data["session_id"] = session_id
        
        for attempt in range(max_retries):
            try:
                response = requests.post(url, json=data, timeout=self.timeout)
                
                if response.status_code in [200, 201]:
                    return response.json()
                elif response.status_code == 400:
                    # 参数错误，不重试
                    raise ValueError(response.json().get("error"))
                else:
                    # 服务器错误，可重试
                    if attempt < max_retries - 1:
                        time.sleep(2 ** attempt)  # 指数退避
                        continue
                        
            except requests.exceptions.RequestException as e:
                if attempt < max_retries - 1:
                    time.sleep(2 ** attempt)
                    continue
                raise
        
        raise Exception(f"Failed to create container after {max_retries} attempts")
    
    def destroy_container(self, container_id):
        """销毁容器"""
        url = f"{self.base_url}/destroy/{container_id}"
        response = requests.post(url, timeout=self.timeout)
        return response.json()
    
    def check_health(self, container_id):
        """健康检查"""
        url = f"{self.base_url}/health/{container_id}"
        response = requests.get(url, timeout=self.timeout)
        return response.json()
    
    def wait_for_ready(self, container_id, timeout=60):
        """等待容器服务就绪"""
        start_time = time.time()
        while time.time() - start_time < timeout:
            try:
                health = self.check_health(container_id)
                if (health.get("status") == "running" and 
                    health.get("web_service") == "healthy" and
                    health.get("websocket_service") == "healthy"):
                    return True
            except:
                pass
            time.sleep(2)
        return False
    
    def list_containers(self):
        """列出所有容器"""
        url = f"{self.base_url}/list"
        response = requests.get(url, timeout=self.timeout)
        return response.json()

# 使用示例
client = MatlabContainerClient()

# 为用户1创建容器
result = client.create_container(1, session_id="abc-123")
print(f"容器已创建: {result['container_id']}")

# 等待服务就绪
if client.wait_for_ready(result['container_id']):
    print("服务已就绪")
    web_url = f"http://166.111.7.155:{result['http_port']}/"
    ws_url = f"ws://166.111.7.155:{result['ws_port']}/"
    print(f"Web访问地址: {web_url}")
    print(f"WebSocket地址: {ws_url}")
else:
    print("服务启动超时")
```

### JavaScript集成示例

```javascript
class MatlabContainerClient {
  constructor(baseUrl = 'http://166.111.7.155:8080') {
    this.baseUrl = baseUrl;
  }

  async createContainer(userId, sessionId = null) {
    const response = await fetch(`${this.baseUrl}/create`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: userId, session_id: sessionId })
    });
    
    if (!response.ok) {
      throw new Error(`创建失败: ${response.status}`);
    }
    
    return await response.json();
  }

  async checkHealth(containerId) {
    const response = await fetch(`${this.baseUrl}/health/${containerId}`);
    return await response.json();
  }

  async waitForReady(containerId, timeout = 60000) {
    const startTime = Date.now();
    
    while (Date.now() - startTime < timeout) {
      try {
        const health = await this.checkHealth(containerId);
        if (health.status === 'running' && 
            health.web_service === 'healthy' &&
            health.websocket_service === 'healthy') {
          return true;
        }
      } catch (e) {
        // 继续等待
      }
      await new Promise(resolve => setTimeout(resolve, 2000));
    }
    
    return false;
  }

  async destroyContainer(containerId) {
    const response = await fetch(`${this.baseUrl}/destroy/${containerId}`, {
      method: 'POST'
    });
    return await response.json();
  }
}

// 使用示例
const client = new MatlabContainerClient();

async function initMatlab(userId) {
  // 创建容器
  const result = await client.createContainer(userId, 'session-123');
  console.log('容器已创建:', result.container_id);
  
  // 等待就绪
  if (await client.waitForReady(result.container_id)) {
    console.log('服务已就绪');
    const webUrl = `http://166.111.7.155:${result.http_port}/`;
    const wsUrl = `ws://166.111.7.155:${result.ws_port}/`;
    
    // 显示iframe
    document.getElementById('matlab-iframe').src = webUrl;
    return { webUrl, wsUrl };
  } else {
    throw new Error('服务启动超时');
  }
}
```

---

## 更新日志

### v1.0 (2025-10-05) - 初始版本

#### ✅ 核心功能
- **容器管理API**: 完整实现创建、销毁、健康检查、列表、重启接口
- **多用户支持**: 支持1-100个并发用户，独立容器和数据隔离
- **端口管理**: 自动端口分配（30001-30100, 31001-31100）
- **资源限制**: 每容器2核CPU + 4GB内存

#### 🔧 技术实现
- **API服务**: Python Flask框架，监听8080端口
- **容器引擎**: Docker with shell脚本封装
- **数据持久化**: Volume挂载用户独立目录
- **服务监控**: systemd管理 + 健康检查接口

#### 📝 文档完善
- API接口详细文档
- 集成指南和代码示例
- 故障处理流程
- 性能监控方案

---

## 附录

### A. 端口映射规则速查

```bash
# 端口计算公式
HTTP_PORT = 30000 + USER_ID
WS_PORT = 31000 + USER_ID

# 快速验证
curl http://166.111.7.155:$((30000 + USER_ID))/
```

### B. Docker命令速查

```bash
# 查看所有MATLAB容器
docker ps -a | grep matlab-user

# 查看容器日志
docker logs matlab-user-1

# 进入容器
docker exec -it matlab-user-1 bash

# 查看容器资源使用
docker stats matlab-user-1

# 清理停止的容器
docker container prune -f
```

### C. 系统要求

| 组件 | 最低要求 | 推荐配置 |
|-----|---------|---------|
| 操作系统 | Ubuntu 18.04+ | Ubuntu 22.04 LTS |
| Docker | 20.10+ | 24.0+ |
| Python | 3.6+ | 3.10+ |
| CPU | 16核心 | 32核心+ |
| 内存 | 64GB | 128GB+ |
| 存储 | 500GB SSD | 2TB NVMe SSD |
| 网络 | 100Mbps | 1Gbps |

### D. 相关文档链接

- [服务器C接口说明文档](./服务器C接口说明文档.md)
- [API服务维护指南](./API服务维护指南.md)
- [服务器C快速参考](./服务器C快速参考.md)
- [代码修改详细说明](./代码修改详细说明.md)
- [多用户实现总结](./多用户最简化实现总结.md)

---

**文档维护**: 技术团队  
**联系方式**: [技术支持邮箱]  
**最后更新**: 2025-10-05
