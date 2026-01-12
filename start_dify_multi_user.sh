#!/bin/bash
set -ex
# DIFY Docker容器启动脚本 - 多用户版本
# 基于现有单用户脚本的最简化多用户实现

HOME=/home/lixujun
DIFY_PATH=/home/lixujun/meta-agent/dify
HOST_IP=ai-cosmos.ai
COSMOS_WS_HOST=ai-cosmos.ai:8090
COSMOS_FRONTEND_PORT=3039
COSMOS_FRONTEND_HOST=$HOST_IP:$COSMOS_FRONTEND_PORT

# 检查参数
if [[ $# -ne 1 ]] && [[ $# -ne 2 ]]; then
    echo "用法: $0 <用户ID (1-100)> [password]"
    exit 1
fi

USER_ID=$1
if [ $# -eq 2 ]; then
    EMAIL=1234@gmail.com
    PASSWORD=$2
fi

# 验证用户ID范围
if ! [[ "$USER_ID" =~ ^[0-9]+$ ]] || [ "$USER_ID" -lt 1 ] || [ "$USER_ID" -gt 100 ]; then
    echo "错误: 用户ID必须是1-100之间的数字"
    exit 1
fi

echo "启动DIFY Docker容器 (用户 $USER_ID)"
echo "=============================================="

# 配置变量
SHARED_DIR="$HOME/dify_data/user_$USER_ID"
# IMAGE_NAME="bozhang359/matlabhub-matlab-parallel-extended:latest"
# TAR_IMAGE_PATH="/home/zhangbo/workspace/edumanus/matlabhub-matlab-parallel-extended-latest.tar"

# 根据用户ID计算端口
BRIDGE_API_PORT=$((40000 + USER_ID))
HTTP_PORT=$((50000 + USER_ID))
HTTPS_PORT=$((51000 + USER_ID))
PLUGIN_DAEMON_PORT=$((52000 + USER_ID))
WS_SERVER_PORT=$((53000 + USER_ID))

echo "用户配置："
echo "  - 用户ID: $USER_ID"
echo "  - Http端口: $HTTP_PORT"
echo "  - SSL端口: $HTTPS_PORT"
echo "  - 数据目录: $SHARED_DIR"
echo ""

# # 1. 创建用户专属目录
# echo "准备用户目录..."
# mkdir -p "$SHARED_DIR/commands"
# mkdir -p "$SHARED_DIR/results"  
# mkdir -p "$SHARED_DIR/scripts"
# mkdir -p "$SHARED_DIR/logs"
# mkdir -p "$SHARED_DIR/command_queue"
# mkdir -p "$SHARED_DIR/models"
# mkdir -p "$SHARED_DIR/Documents/MATLAB"
# chmod -R 777 "$SHARED_DIR"
# echo "用户目录准备完成: $SHARED_DIR"

# # 复制必要的文件（如果是新用户）
# # 检查是否需要初始化（通过检查标记文件）
# if [ ! -f "$SHARED_DIR/.initialized" ]; then
#     echo "初始化用户文件..."
    
#     # 复制matlab_library目录
#     if [ -d "$HOME/matlab_shared/matlab_library" ]; then
#         echo "  复制matlab_library..."
#         cp -r "$HOME/matlab_shared/matlab_library" "$SHARED_DIR/" 2>/dev/null || true
#         echo "  matlab_library复制完成"
#     else
#         echo "  未找到matlab_library目录"
#     fi
    
#     # 复制scripts目录（完整复制，不仅仅是.m文件）
#     if [ -d "$HOME/matlab_shared/scripts" ]; then
#         echo "  复制scripts目录..."
#         cp -r "$HOME/matlab_shared/scripts" "$SHARED_DIR/" 2>/dev/null || true
#         echo "  scripts目录复制完成"
#     else
#         echo "  未找到scripts目录"
#     fi
    
#     # 创建初始化标记
#     touch "$SHARED_DIR/.initialized"
#     echo "  用户文件初始化完成"
# else
#     echo "用户文件已存在，跳过初始化"
# fi

# 2. 检查现有容器
echo ""
echo "检查现有容器..."
if docker ps | grep dify_$USER_ID; then
    echo "发现运行中的容器，检查健康状态..."
    if curl -k https://localhost:$HTTPS_PORT > /dev/null 2>&1; then
        echo "  DIFY https服务正常运行"
        # if nc -z localhost $HTTPS_PORT 2>/dev/null; then
        #     echo "  WebSocket服务正常运行"
        #     echo "用户 $USER_ID 的DIFY服务已就绪"
        #     exit 0
        # fi
    fi
    
    echo "停止现有容器..."
    docker compose -f $DIFY_PATH/docker/docker-compose.yaml --profile weaviate -p dify_$USER_ID down
    rm -rf $HOME/dify_data/user_$USER_ID
fi

# 3. 检查并加载镜像
# echo ""
# echo "检查Docker镜像..."
# if ! docker images -q "$IMAGE_NAME" | grep -q .; then
#     echo "未找到本地镜像 '$IMAGE_NAME'"
    
#     if [ -f "$TAR_IMAGE_PATH" ]; then
#         echo "发现本地镜像文件，正在加载..."
#         if docker load -i "$TAR_IMAGE_PATH"; then
#             echo "  本地镜像加载成功"
#         else
#             echo "  本地镜像加载失败"
#             exit 1
#         fi
#     else
#         echo "从Docker Hub拉取镜像..."
#         if docker pull "$IMAGE_NAME"; then
#             echo "  镜像拉取成功"
#         else
#             echo "  镜像拉取失败"
#             exit 1
#         fi
#     fi
# else
#     echo "本地镜像检查通过"
# fi

# 4. 检查端口占用
echo ""
echo "检查端口占用..."
if netstat -tln 2>/dev/null | grep -q ":$HTTP_PORT "; then
    echo "警告: 端口 $HTTP_PORT 已被占用"
    # 不退出，尝试继续（可能是同一用户的容器）
fi

if netstat -tln 2>/dev/null | grep -q ":$HTTPS_PORT "; then
    echo "警告: 端口 $HTTPS_PORT 已被占用"
fi

# 5. 启动DIFY容器
echo ""
echo "启动DIFY容器..."

# 设置资源限制（根据文档中的建议）
MEMORY_LIMIT="4g"
CPU_LIMIT="2"

# TODO
# docker run -d \
#   --restart=unless-stopped \
#   -p $WEB_PORT:8888 \
#   -p $WS_PORT:9001 \
#   --shm-size=4G \
#   --memory=$MEMORY_LIMIT \
#   --cpus=$CPU_LIMIT \
#   --name "$CONTAINER_NAME" \
#   -v "$SHARED_DIR:/home/matlab/shared" \
#   -e MW_CONTEXT_TAGS=MATLAB:SIMULINK:DOCKERHUB:V1 \
#   -e MLM_LICENSE_FILE=27000@matlab.cic.tsinghua.edu.cn \
#   -e USER_ID=$USER_ID \
#   "$IMAGE_NAME" -browser > "$SHARED_DIR/logs/container.log" 2>&1

VOLUME_PATH=$HOME/dify_data/user_${USER_ID}
if [ ! -d $VOLUME_PATH ]; then
    mkdir -p $VOLUME_PATH
    cp -r $DIFY_PATH/docker/volumes/* $VOLUME_PATH
fi

cur_path=`pwd`
cd $DIFY_PATH/docker
# VOLUME_PATH=$VOLUME_PATH \
# EXPOSE_NGINX_PORT=$HTTP_PORT \
# EXPOSE_NGINX_SSL_PORT=$HTTPS_PORT \
# EXPOSE_PLUGIN_DEBUGGING_PORT=$PLUGIN_DAEMON_PORT \
# CONSOLE_API_URL=https://18.142.32.33:${BRIDGE_API_PORT} \
VOLUME_PATH=$VOLUME_PATH \
EXPOSE_NGINX_PORT=$HTTP_PORT \
EXPOSE_NGINX_SSL_PORT=$HTTPS_PORT \
EXPOSE_PLUGIN_DEBUGGING_PORT=$PLUGIN_DAEMON_PORT \
CONSOLE_API_URL=https://$HOST_IP:$HTTPS_PORT \
COSMOS_WS_URL=wss://$COSMOS_WS_HOST/ws/$WS_SERVER_PORT \
COSMOS_WS_HOST=$COSMOS_WS_HOST \
CSP_WHITELIST="http://aicosmos.ai:* http://ai-cosmos.ai:* https://aicosmos.ai:* https://ai-cosmos.ai:* wss://$COSMOS_WS_HOST $COSMOS_FRONTEND_HOST" \
ALLOW_EMBED=true \
docker compose -f docker-compose.yaml --profile weaviate -p dify_$USER_ID up -d
if [ $PASSWORD ]; then
    dify_api_id=`docker ps | grep dify_${USER_ID}-api-1 | awk '{print $1}'`
    sleep 20
    # docker exec -it "$dify_api_id" flask create-tenant --email "$EMAIL" --name temp-user --language zh-Hans
    # docker exec -it "$dify_api_id" flask reset-password --email "$EMAIL" --new-password "$PASSWORD" --password-confirm "$PASSWORD"
    curl -X POST http://localhost:$HTTP_PORT/console/api/setup -H "Content-Type: application/json" -d '{"email":"'$EMAIL'","name":"lixj","password":"'$PASSWORD'"}'
fi
cd $cur_path

# 6. 等待服务启动
echo "等待DIFY服务启动..."
# sleep 10

# 7. 健康检查
echo ""
echo "服务健康检查..."
RETRY_COUNT=0
MAX_RETRIES=12

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    if curl -k https://localhost:$HTTPS_PORT > /dev/null 2>&1; then
        echo "  DIFY Web界面已就绪 (端口 $HTTPS_PORT)"
        break
    else
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "  等待Web服务启动... ($RETRY_COUNT/$MAX_RETRIES)"
        sleep 10
    fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
    echo "  DIFY Web服务启动超时"
    echo "容器状态："
    docker ps -f name="$CONTAINER_NAME"
    echo "容器日志："
    docker logs "$CONTAINER_NAME" --tail 20
    exit 1
fi

# 对于当前运行的容器，WebSocket服务将在用户首次访问MATLAB时启动

# 9. 最终验证
echo ""
echo "最终服务验证..."

if curl -s https://localhost:$HTTPS_PORT > /dev/null 2>&1; then
    echo "  Web服务正常"
else
    echo "  Web服务异常"
fi

# 10. 输出服务信息
echo ""
echo "DIFY容器部署完成！"
echo "======================================="
echo "用户信息："
echo "  用户ID: $USER_ID"
echo "  容器名称: $CONTAINER_NAME"
echo "  数据目录: $SHARED_DIR"
echo ""
echo "访问地址："
echo "  Web界面: https://localhost:$HTTPS_PORT"
echo ""
echo "管理命令："
echo "  查看状态: docker ps -f name=$CONTAINER_NAME"
echo "  查看日志: docker logs $CONTAINER_NAME"
echo "  停止容器: docker stop $CONTAINER_NAME"
echo "  删除容器: docker rm $CONTAINER_NAME"
echo ""
echo "容器已配置为自动重启"
