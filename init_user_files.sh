#!/bin/bash
# 用户文件初始化/重置脚本
# 用于初始化或重置用户的DIFY文件

echo "DIFY用户文件初始化工具"
echo "============================="

# 检查参数
if [ $# -lt 1 ]; then
    echo "用法: $0 <用户ID|all> [--force]"
    echo ""
    echo "参数:"
    echo "  用户ID    - 初始化指定用户（1-100）"
    echo "  all       - 初始化所有已创建的用户目录"
    echo "  --force   - 强制重新初始化（覆盖现有文件）"
    echo ""
    echo "示例:"
    echo "  $0 1          # 初始化用户1"
    echo "  $0 all        # 初始化所有用户"
    echo "  $0 1 --force  # 强制重新初始化用户1"
    exit 1
fi

USER_SPEC=$1
FORCE_FLAG=$2

# 源目录
# TODO
# SOURCE_SCRIPTS="$HOME/matlab_shared/scripts"
# SOURCE_LIBRARY="$HOME/matlab_shared/matlab_library"
BASE_DIR="$HOME/dify_data"

# 检查源目录
# if [ ! -d "$SOURCE_SCRIPTS" ] && [ ! -d "$SOURCE_LIBRARY" ]; then
#     echo "错误: 源目录不存在"
#     echo "需要: $SOURCE_SCRIPTS 或 $SOURCE_LIBRARY"
#     exit 1
# fi

# 初始化单个用户的函数
init_user() {
    local user_id=$1
    local user_dir="$BASE_DIR/user_$user_id"
    
    echo ""
    echo "处理用户 $user_id..."
    
    # 检查用户目录是否存在
    if [ ! -d "$user_dir" ]; then
        echo "  用户目录不存在，创建中..."
        mkdir -p "$user_dir"
    fi
    
    # 检查是否需要初始化
    if [ -f "$user_dir/.initialized" ] && [ "$FORCE_FLAG" != "--force" ]; then
        echo "  用户已初始化，跳过（使用 --force 强制重新初始化）"
        return
    fi
    
    # 如果是强制模式，先备份现有文件
    if [ "$FORCE_FLAG" == "--force" ] && [ -f "$user_dir/.initialized" ]; then
        echo "  备份现有文件..."
        backup_dir="$user_dir.backup.$(date +%Y%m%d_%H%M%S)"
        cp -r "$user_dir" "$backup_dir"
        echo "  备份保存至: $backup_dir"
    fi
    
    # 复制matlab_library
    # if [ -d "$SOURCE_LIBRARY" ]; then
    #     echo "  复制matlab_library..."
    #     if [ "$FORCE_FLAG" == "--force" ]; then
    #         rm -rf "$user_dir/matlab_library"
    #     fi
    #     cp -r "$SOURCE_LIBRARY" "$user_dir/"
    #     echo "  matlab_library复制完成"
    # fi
    
    # # 复制scripts
    # if [ -d "$SOURCE_SCRIPTS" ]; then
    #     echo "  复制scripts..."
    #     if [ "$FORCE_FLAG" == "--force" ]; then
    #         rm -rf "$user_dir/scripts"
    #     fi
    #     cp -r "$SOURCE_SCRIPTS" "$user_dir/"
    #     echo "  scripts复制完成"
    # fi
    
    # # 确保其他必要目录存在
    # mkdir -p "$user_dir/commands"
    # mkdir -p "$user_dir/results"
    # mkdir -p "$user_dir/logs"
    # mkdir -p "$user_dir/command_queue"
    # mkdir -p "$user_dir/models"
    # mkdir -p "$user_dir/Documents/MATLAB"
    
    # 设置权限
    chmod -R 777 "$user_dir"
    
    # 创建/更新初始化标记
    echo "$(date)" > "$user_dir/.initialized"
    
    # 统计文件
    local file_count=$(find "$user_dir" -type f | wc -l)
    local size=$(du -sh "$user_dir" | cut -f1)
    
    echo "  统计: $file_count 个文件, 总大小: $size"
    echo "  用户 $user_id 初始化完成"
}

# 主逻辑
if [ "$USER_SPEC" == "all" ]; then
    echo "初始化所有用户..."
    
    # 查找所有已创建的用户目录
    user_count=0
    for user_dir in "$BASE_DIR"/user_*; do
        if [ -d "$user_dir" ]; then
            # 提取用户ID
            user_id=$(basename "$user_dir" | sed 's/user_//')
            if [[ "$user_id" =~ ^[0-9]+$ ]]; then
                init_user "$user_id"
                ((user_count++))
            fi
        fi
    done
    
    if [ $user_count -eq 0 ]; then
        echo ""
        echo "没有找到任何用户目录"
    else
        echo ""
        echo "完成！共初始化 $user_count 个用户"
    fi
    
elif [[ "$USER_SPEC" =~ ^[0-9]+$ ]]; then
    # 验证用户ID范围
    if [ "$USER_SPEC" -lt 1 ] || [ "$USER_SPEC" -gt 100 ]; then
        echo "错误: 用户ID必须在1-100之间"
        exit 1
    fi
    
    init_user "$USER_SPEC"
    echo ""
    echo "完成！"
    
else
    echo "错误: 无效的参数 '$USER_SPEC'"
    echo "请使用数字用户ID（1-100）或 'all'"
    exit 1
fi

# 显示总体统计
echo ""
echo "总体统计:"
if [ -d "$BASE_DIR" ]; then
    total_users=$(ls -d "$BASE_DIR"/user_* 2>/dev/null | wc -l)
    total_size=$(du -sh "$BASE_DIR" 2>/dev/null | cut -f1)
    echo "  用户目录数: $total_users"
    echo "  总占用空间: $total_size"
fi
