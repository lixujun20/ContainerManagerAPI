# MATLAB容器管理API接口参考

> 快速参考文档 - 用于开发和测试  
> 服务地址: http://localhost:8080  
> 完整文档: 参见 MATLAB容器管理API接口文档.md

---

## 服务信息

### GET /

- 接口名称: 获取API服务信息
- 功能描述: 返回API服务的基本信息、版本号和可用端点列表，用于服务健康检查和API探索
- 入参: 无
- 返回参数:
  - service: string - 服务名称
  - version: string - 版本号
  - architecture: string - 架构说明
  - websocket_service: string - WebSocket服务启动方式说明
  - endpoints: object - 所有可用的API端点及说明
- url地址: /
- 请求方式: GET

**curl测试用例**:
```bash
curl http://localhost:8080/
```

**期望返回**:
```json
{
  "service": "MATLAB Container Manager",
  "version": "1.0",
  "architecture": "One container, one MATLAB session",
  "websocket_service": "Auto-started via startup.m",
  "endpoints": {
    "POST /create": "Create a new container (WebSocket auto-starts)",
    "POST /destroy/<container_id>": "Destroy a container",
    "GET /health/<container_id>": "Health check for a container",
    "GET /list": "List all containers",
    "POST /restart/<container_id>": "Restart a container"
  }
}
```

---

## 容器管理接口

### POST /create

- 接口名称: 创建MATLAB容器
- 功能描述: 为指定用户创建并启动MATLAB Docker容器，自动分配HTTP和WebSocket端口，配置独立的工作环境和数据存储，MATLAB启动后会自动运行startup.m初始化WebSocket服务
- 入参:
  - user_id: number - 用户ID，必填，范围1-100
  - session_id: string - 会话ID，可选，用于日志关联和调试
- 返回参数:
  - container_id: string - 容器标识符，格式 "matlab-user-{user_id}"
  - http_port: number - HTTP服务端口，计算公式: 30000 + user_id
  - ws_port: number - WebSocket服务端口，计算公式: 31000 + user_id
  - status: string - 容器状态，"running" 表示新创建，"already_running" 表示已存在
  - message: string - 操作结果描述
- url地址: /create
- 请求方式: POST

**curl测试用例**:
```bash
# 创建用户1的容器
curl -X POST http://localhost:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"user_id": 1}'
```

**期望返回** (新建容器):
```json
{
  "container_id": "matlab-user-1",
  "http_port": 30001,
  "ws_port": 31001,
  "status": "running",
  "message": "Container created successfully"
}
```

**期望返回** (容器已存在):
```json
{
  "container_id": "matlab-user-1",
  "http_port": 30001,
  "ws_port": 31001,
  "status": "already_running",
  "message": "Container is already running"
}
```

**批量操作示例**:
```bash
# 创建用户1-5的容器
for i in {1..5}; do
  curl -X POST http://localhost:8080/create \
    -H 'Content-Type: application/json' \
    -d "{\"user_id\": $i}"
  sleep 2
done
```

**错误响应示例**:
```json
{
  "error": "Invalid user_id. Must be between 1 and 100"
}
```

---

### POST /destroy/<container_id>

- 接口名称: 销毁MATLAB容器
- 功能描述: 停止并删除指定的MATLAB容器，释放端口和系统资源，用户数据目录保留在磁盘上不会被删除
- 入参:
  - container_id: string - 容器ID，在URL路径中指定，格式 "matlab-user-{1-100}"
- 返回参数:
  - message: string - 操作结果描述
  - container_id: string - 被销毁的容器ID
- url地址: /destroy/<container_id>
- 请求方式: POST

**curl测试用例**:
```bash
# 销毁用户1的容器
curl -X POST http://localhost:8080/destroy/matlab-user-1
```

**期望返回** (成功):
```json
{
  "message": "Container destroyed successfully",
  "container_id": "matlab-user-1"
}
```

**期望返回** (容器不存在):
```json
{
  "message": "Container not found",
  "container_id": "matlab-user-1"
}
```

**批量操作示例**:
```bash
# 批量销毁用户1-5的容器
for i in {1..5}; do
  curl -X POST http://localhost:8080/destroy/matlab-user-$i
done
```

**错误响应示例**:
```json
{
  "error": "Invalid container_id format"
}
```

---

### GET /health/<container_id>

- 接口名称: 容器健康检查
- 功能描述: 获取指定容器的运行状态、资源使用情况（CPU、内存）和服务健康状态（Web、WebSocket），用于监控和故障诊断
- 入参:
  - container_id: string - 容器ID，在URL路径中指定
- 返回参数:
  - container_id: string - 容器ID
  - status: string - 容器状态，"running" 或 "stopped"
  - started_at: string - 启动时间，ISO 8601格式
  - cpu_usage: string - CPU使用率，如 "2.74%"
  - memory_usage: string - 内存使用量，如 "2.302GiB / 4GiB"
  - memory_percent: string - 内存使用百分比，如 "57.5%"
  - web_service: string - Web服务状态，"healthy" 或 "unhealthy"
  - websocket_service: string - WebSocket服务状态，"healthy" 或 "unhealthy"
  - http_port: number - HTTP端口
  - ws_port: number - WebSocket端口
- url地址: /health/<container_id>
- 请求方式: GET

**curl测试用例**:
```bash
# 检查用户1的容器
curl http://localhost:8080/health/matlab-user-1
```

**期望返回** (容器运行中):
```json
{
  "container_id": "matlab-user-1",
  "status": "running",
  "started_at": "2025-10-13T10:30:00.000Z",
  "cpu_usage": "2.74%",
  "memory_usage": "2.302GiB / 4GiB",
  "memory_percent": "57.5%",
  "web_service": "healthy",
  "websocket_service": "healthy",
  "http_port": 30001,
  "ws_port": 31001
}
```

**期望返回** (容器已停止):
```json
{
  "container_id": "matlab-user-1",
  "status": "stopped",
  "started_at": "2025-10-13T10:30:00.000Z"
}
```

**批量操作示例**:
```bash
# 监控多个容器状态
for i in {1..5}; do
  echo "=== User $i ==="
  curl -s http://localhost:8080/health/matlab-user-$i | jq '.status, .cpu_usage, .memory_percent'
done
```

**错误响应示例**:
```json
{
  "error": "Container not found",
  "container_id": "matlab-user-1"
}
```

---

### GET /list

- 接口名称: 列出所有容器
- 功能描述: 返回所有MATLAB容器的列表，包括容器状态、端口分配和创建时间，按用户ID升序排列
- 入参: 无
- 返回参数:
  - total: number - 容器总数
  - containers: array - 容器列表
    - container_id: string - 容器ID
    - user_id: number - 用户ID
    - status: string - 容器状态，如 "running", "exited"
    - created: string - 创建时间
    - http_port: number - HTTP端口
    - ws_port: number - WebSocket端口
- url地址: /list
- 请求方式: GET

**curl测试用例**:
```bash
curl http://localhost:8080/list
```

**期望返回**:
```json
{
  "total": 3,
  "containers": [
    {
      "container_id": "matlab-user-1",
      "user_id": 1,
      "status": "running",
      "created": "2025-10-13 10:30:00",
      "http_port": 30001,
      "ws_port": 31001
    },
    {
      "container_id": "matlab-user-5",
      "user_id": 5,
      "status": "running",
      "created": "2025-10-13 11:00:00",
      "http_port": 30005,
      "ws_port": 31005
    },
    {
      "container_id": "matlab-user-10",
      "user_id": 10,
      "status": "exited",
      "created": "2025-10-12 15:20:00",
      "http_port": 30010,
      "ws_port": 31010
    }
  ]
}
```

**批量操作示例**:
```bash
# 只显示运行中的容器
curl -s http://localhost:8080/list | jq '.containers[] | select(.status=="running")'

# 统计各状态容器数量
curl -s http://localhost:8080/list | jq '.containers | group_by(.status) | map({status: .[0].status, count: length})'
```

---

### POST /restart/<container_id>

- 接口名称: 重启MATLAB容器
- 功能描述: 重启指定的MATLAB容器，保留容器配置和数据，重启后会重新加载startup.m初始化WebSocket服务
- 入参:
  - container_id: string - 容器ID，在URL路径中指定
- 返回参数:
  - message: string - 操作结果描述
  - container_id: string - 被重启的容器ID
- url地址: /restart/<container_id>
- 请求方式: POST

**curl测试用例**:
```bash
# 重启用户1的容器
curl -X POST http://localhost:8080/restart/matlab-user-1
```

**期望返回** (成功):
```json
{
  "message": "Container restarted successfully",
  "container_id": "matlab-user-1"
}
```

**期望返回** (容器不存在):
```json
{
  "error": "Container not found",
  "container_id": "matlab-user-1"
}
```

**批量操作示例**:
```bash
# 批量重启多个容器
for i in {1..5}; do
  curl -X POST http://localhost:8080/restart/matlab-user-$i
  sleep 5
done
```

**错误响应示例**:
```json
{
  "error": "Failed to restart container",
  "details": "Container in invalid state"
}
```

---

## 常见使用场景

### 场景1: 创建并验证容器
```bash
# 1. 创建容器
curl -X POST http://localhost:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"user_id": 1}'

# 2. 等待容器完全启动
sleep 10

# 3. 检查容器健康状态
curl http://localhost:8080/health/matlab-user-1

# 4. 访问MATLAB Web界面
# 浏览器打开: http://localhost:30001
```

### 场景2: 监控所有容器
```bash
# 获取所有容器状态
curl -s http://localhost:8080/list | jq '.'

# 检查每个运行中容器的健康状态
curl -s http://localhost:8080/list | jq -r '.containers[] | select(.status=="running") | .container_id' | while read cid; do
  curl -s http://localhost:8080/health/$cid | jq '{container_id, cpu_usage, memory_percent}'
done
```

### 场景3: 清理停止的容器
```bash
# 获取所有停止的容器
curl -s http://localhost:8080/list | jq -r '.containers[] | select(.status!="running") | .container_id' | while read cid; do
  curl -X POST http://localhost:8080/destroy/$cid
done
```

---

## 端口分配规则

| 用户ID | HTTP端口 | WebSocket端口 |
|--------|----------|---------------|
| 1      | 30001    | 31001         |
| 2      | 30002    | 31002         |
| ...    | ...      | ...           |
| 50     | 30050    | 31050         |
| 100    | 30100    | 31100         |

**计算公式**:
- HTTP端口 = 30000 + 用户ID
- WebSocket端口 = 31000 + 用户ID

---

## 注意事项

1. **容器启动时间**: 容器创建后需要15-20秒完全启动，建议创建后等待10秒再进行健康检查
2. **并发限制**: 建议同时创建容器数量不超过10个，避免系统资源争抢
3. **用户ID范围**: 仅支持1-100的用户ID，超出范围会返回400错误
4. **数据持久化**: 销毁容器不会删除用户数据，数据保存在 `~/matlab_data/user_{user_id}/`
5. **资源限制**: 每个容器默认限制2核CPU、4GB内存
6. **端口冲突**: 如果宿主机端口已被占用，容器创建会失败

---

## 相关文件

- API实现: `/home/zhangbo/workspace/ContainerManagerAPI/container_manager.py`
- 容器启动脚本: `/home/zhangbo/workspace/ContainerManagerAPI/start_matlab_multi_user.sh`
- 服务管理: `/home/zhangbo/workspace/ContainerManagerAPI/scripts/api_manager.sh`
- 完整文档: `/home/zhangbo/workspace/ContainerManagerAPI/docs/MATLAB容器管理API接口文档.md`

