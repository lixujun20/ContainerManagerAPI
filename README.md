# MATLAB Container Manager API

> 多用户 MATLAB 容器管理系统  
> **服务端口**: 8080  
> **容器端口范围**: 30001-30100 (HTTP), 31001-31100 (WebSocket)

##  目录结构

```
ContainerManagerAPI/
├── container_manager.py          # 主 API 服务（Flask）
├── start_matlab_multi_user.sh    # 单个容器启动脚本
├── manage_multi_user.sh          # 批量管理脚本
├── deploy_multi_user.sh          # 一键部署脚本
├── init_user_files.sh            # 用户文件初始化
├── matlab-container-manager.service  # systemd 服务文件
├── scripts/
│   ├── api_health_check.sh       # 健康检查脚本
│   ├── api_maintenance_cron.sh   # 定期维护脚本
│   ├── api_manager.sh            # API 管理脚本
│   └── api_monitor.sh            # 监控脚本
└── docs/
    ├── API接口参考.md            # API 快速参考
    ├── MATLAB容器管理API接口文档.md  # 完整 API 文档
    └── API服务维护指南.md        # 运维指南
```

## 快速启动

### 启动 API 服务

```bash
cd /home/zhangbo/workspace/ContainerManagerAPI
python3 container_manager.py
```

服务监听端口: 8080

### 创建用户容器

```bash
# 通过 API
curl -X POST http://localhost:8080/create \
  -H 'Content-Type: application/json' \
  -d '{"user_id": 1}'

# 通过管理脚本
./manage_multi_user.sh start 1

# 直接使用启动脚本
./start_matlab_multi_user.sh 1
```

## 当前运行状态

查看运行中的容器：
```bash
docker ps | grep matlab-user
```

查看 API 服务状态：
```bash
ps aux | grep container_manager | grep -v grep
```

## 服务管理

### 停止服务

```bash
ps aux | grep container_manager | grep -v grep
kill <PID>
```

### 重启服务

```bash
cd /home/zhangbo/workspace/ContainerManagerAPI
nohup python3 container_manager.py > container_manager.log 2>&1 &
```

## 端口分配规则

HTTP端口 = 30000 + 用户ID
WebSocket端口 = 31000 + 用户ID

示例：
- 用户1: HTTP=30001, WebSocket=31001
- 用户2: HTTP=30002, WebSocket=31002

## 文档

- API 快速参考: `docs/API接口参考.md`
- API 完整文档: `docs/MATLAB容器管理API接口文档.md`
- 运维指南: `docs/API服务维护指南.md`

## 说明

本系统为多用户容器管理API，与 edumanus agent API server 独立运行。

---

**最后更新**: 2025-10-13  
**维护者**: bo

