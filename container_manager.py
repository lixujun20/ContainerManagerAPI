#!/usr/bin/env python3
"""
DIFY容器管理API服务
最简化的多用户容器管理实现
"""

from flask import Flask, request, jsonify
import subprocess
import json
import os
import re
import time

app = Flask(__name__)

# 配置
BASE_DATA_DIR = os.path.expanduser("~/dify_data")
MAX_USERS = 100
START_SCRIPT = os.path.join(os.path.dirname(__file__), "start_dify_multi_user.sh")

def get_container_name(user_id):
    """获取容器名称"""
    return f"dify_{user_id}-api-1"

def get_ports(user_id):
    """获取用户的端口配置"""
    return {
        "http_port": 50000 + user_id,
        "https_port": 51000 + user_id
    }

def run_command(cmd):
    """执行shell命令并返回结果"""
    try:
        result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
        return result.returncode == 0, result.stdout, result.stderr
    except Exception as e:
        return False, "", str(e)

def check_container_exists(container_id):
    """检查容器是否存在"""
    success, stdout, _ = run_command(f"docker ps | grep {container_id}")
    return bool(stdout.strip())

def check_container_running(container_id):
    """检查容器是否在运行"""
    success, stdout, _ = run_command(f"docker ps | grep {container_id}")
    return bool(stdout.strip())

def get_container_stats(container_id):
    """获取容器资源使用情况"""
    if not check_container_running(container_id):
        return None
    
    # 获取容器统计信息
    # Check dify backend only
    success, stdout, _ = run_command(
        f"docker ps | grep {container_id} | awk '{{print $1}}' | docker stats --no-stream --format '{{{{json .}}}}'"
    )
    
    if success and stdout:
        try:
            stats = json.loads(stdout.strip())
            return {
                "cpu_usage": stats.get("CPUPerc", "0%"),
                "memory_usage": stats.get("MemUsage", "0B / 0B"),
                "memory_percent": stats.get("MemPerc", "0%")
            }
        except:
            pass
    return None

@app.route('/create', methods=['POST'])
def create_container():
    """创建容器"""
    try:
        data = request.get_json()
        user_id = data.get('user_id')
        session_id = data.get('session_id', '')
        password = data.get('password')
        
        # 验证用户ID
        if not user_id or not isinstance(user_id, int) or user_id < 1 or user_id > MAX_USERS:
            return jsonify({
                "error": f"Invalid user_id. Must be between 1 and {MAX_USERS}"
            }), 400
        
        container_name = get_container_name(user_id)
        ports = get_ports(user_id)
        
        # 检查容器是否已存在
        if check_container_running(container_name):
            return jsonify({
                "container_id": container_name,
                "http_port": ports["http_port"],
                "https_port": ports["https_port"],
                "status": "already_running",
                "message": "Container is already running"
            }), 200
        
        # 使用启动脚本创建容器
        print(f"Creating container for user {user_id} with password {password}...")
        success, stdout, stderr = run_command(f"bash {START_SCRIPT} {user_id} {password}")
        print(stdout)
        
        if not success:
            return jsonify({
                "error": "Failed to create container",
                "details": stderr
            }), 500
        
        # 验证容器状态
        if check_container_running(container_name):
            return jsonify({
                "container_id": container_name,
                "http_port": ports["http_port"],
                "https_port": ports["https_port"],
                "status": "running",
                "message": "Container created successfully"
            }), 201
        else:
            return jsonify({
                "error": "Container created but not running",
                "details": "Check docker logs for more information"
            }), 500
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/destroy/<container_id>', methods=['POST'])
def destroy_container(container_id):
    """销毁容器"""
    try:
        # 验证容器名称格式
        if not re.match(r'^dify_\d+-api-1$', container_id):
            return jsonify({"error": "Invalid container_id format"}), 400
        
        if not check_container_exists(container_id):
            return jsonify({
                "message": "Container not found",
                "container_id": container_id
            }), 404
        
        # 停止容器
        print(f"Stopping container {container_id}...")
        COMPOSE_FILE = "/home/lixujun/cosmos_dify/docker/docker-compose.yaml"
        run_command(f"docker compose -f {COMPOSE_FILE} -p dify_{container_id} down")
        
        # 删除容器
        print(f"Removing container {container_id}...")
        VOLUME_PATH = f"/home/lixujun/dify_data/user_{container_id}"
        success, _, stderr = run_command(f"rm -rf {VOLUME_PATH}")
        
        if success:
            return jsonify({
                "message": "Container destroyed successfully",
                "container_id": container_id
            }), 200
        else:
            return jsonify({
                "error": "Failed to destroy container",
                "details": stderr
            }), 500
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/health/<container_id>', methods=['GET'])
def health_check(container_id):
    """健康检查"""
    try:
        # 验证容器名称格式
        if not re.match(r'^dify_\d+-api-1$', container_id):
            return jsonify({"error": "Invalid container_id format"}), 400
        
        if not check_container_exists(container_id):
            return jsonify({
                "error": "Container not found",
                "container_id": container_id
            }), 404
        
        # 获取容器状态
        is_running = check_container_running(container_id)
        
        # 获取启动时间
        success, stdout, _ = run_command(
            f"docker inspect {container_id} --format '{{{{.State.StartedAt}}}}'"
        )
        started_at = stdout.strip() if success else "unknown"
        
        # 获取资源使用情况
        stats = get_container_stats(container_id) if is_running else None
        
        health_data = {
            "container_id": container_id,
            "status": "running" if is_running else "stopped",
            "started_at": started_at
        }
        
        if stats:
            health_data.update({
                "cpu_usage": stats["cpu_usage"],
                "memory_usage": stats["memory_usage"],
                "memory_percent": stats["memory_percent"]
            })
        
        # 检查服务端口
        if is_running:
            # 从容器名称提取用户ID
            match = re.match(r'^dify_(\d+)-api-1$', container_id)
            if match:
                user_id = int(match.group(1))
                ports = get_ports(user_id)
                
                # 检查Web端口
                web_success, _, _ = run_command(
                    f"curl -s http://localhost:{ports['http_port']} > /dev/null 2>&1"
                )
                
                # 检查WebSocket端口
                ws_success, _, _ = run_command(
                    f"nc -z localhost {ports['https_port']} 2>/dev/null"
                )
                
                health_data.update({
                    "web_service": "healthy" if web_success else "unhealthy",
                    "websocket_service": "healthy" if ws_success else "unhealthy",
                    "http_port": ports["http_port"],
                    "https_port": ports["https_port"]
                })
        
        return jsonify(health_data), 200
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/list', methods=['GET'])
def list_containers():
    """列出所有容器"""
    try:
        # 获取所有dify-user-*容器
        success, stdout, _ = run_command(
            "docker ps -a --format '{{json .}}' | grep -E dify_[0123456789]+-api-1"
        )
        
        containers = []
        if success and stdout:
            for line in stdout.strip().split('\n'):
                if line:
                    try:
                        container_data = json.loads(line)
                        container_name = container_data.get("Names", "")
                        
                        # 提取用户ID
                        match = re.match(r'^dify_(\d+)-api-1$', container_name)
                        if match:
                            user_id = int(match.group(1))
                            ports = get_ports(user_id)
                            
                            containers.append({
                                "container_id": container_name,
                                "user_id": user_id,
                                "status": container_data.get("State", "unknown"),
                                "created": container_data.get("CreatedAt", ""),
                                "http_port": ports["http_port"],
                                "https_port": ports["https_port"]
                            })
                    except:
                        continue
        
        # 按用户ID排序
        containers.sort(key=lambda x: x["user_id"])
        
        return jsonify({
            "total": len(containers),
            "containers": containers
        }), 200
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/restart/<container_id>', methods=['POST'])
def restart_container(container_id):
    """重启容器"""
    try:
        # 验证容器名称格式
        if not re.match(r'^dify_\d+-api-1$', container_id):
            return jsonify({"error": "Invalid container_id format"}), 400
        
        if not check_container_exists(container_id):
            return jsonify({
                "error": "Container not found",
                "container_id": container_id
            }), 404
        
        # 重启容器
        print(f"Restarting container {container_id}...")
        success, _, stderr = run_command(f"docker restart {container_id}")
        
        if success:
            return jsonify({
                "message": "Container restarted successfully",
                "container_id": container_id
            }), 200
        else:
            return jsonify({
                "error": "Failed to restart container",
                "details": stderr
            }), 500
            
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/', methods=['GET'])
def index():
    """API信息"""
    return jsonify({
        "service": "DIFY Container Manager",
        "version": "1.0",
        "architecture": "One container, one DIFY session",
        "websocket_service": "Auto-started via startup.m",
        "endpoints": {
            "POST /create": "Create a new container (WebSocket auto-starts)",
            "POST /destroy/<container_id>": "Destroy a container",
            "GET /health/<container_id>": "Health check for a container",
            "GET /list": "List all containers",
            "POST /restart/<container_id>": "Restart a container"
        }
    }), 200

if __name__ == '__main__':
    # 确保启动脚本可执行
    if os.path.exists(START_SCRIPT):
        os.chmod(START_SCRIPT, 0o755)
    
    # 创建基础数据目录
    os.makedirs(BASE_DATA_DIR, exist_ok=True)
    
    # 启动服务
    print("Starting DIFY Container Manager on port 9080...")
    app.run(host='0.0.0.0', port=9080, debug=False)
