#!/bin/bash

# 同步文件存储目录
SYNC_DIR="$HOME/.sync_files"
TEMP_DIR="$SYNC_DIR/.tmp"

# 确保目录存在
mkdir -p "$SYNC_DIR" "$TEMP_DIR"

# 显示帮助信息
show_help() {
    echo "syncf - 服务器与本地文件同步工具"
    echo "用法:"
    echo "  syncf -z <filelist> <name>      : 打包文件/文件夹到同步目录"
    echo "  syncf -zg <name>                : 自动打包git改动文件"
    echo "  syncf -uz <package>             : 解包并同步文件到本地"
    echo "  syncf -l                        : 列出同步目录中的文件"
    echo "  syncf -h                        : 显示帮助信息"
    echo ""
    echo "文件列表格式说明:"
    echo "  1. 以'#'开头的行是注释"
    echo "  2. 以'!'开头的行是排除规则(支持正则表达式)"
    echo "  3. 支持类似gitignore的匹配规则:"
    echo "     - *.txt      匹配所有txt文件"
    echo "     - /dist      匹配名为dist的文件或目录"
    echo "     - node_modules/ 匹配node_modules目录及其内容"
    echo "     - *.log      匹配所有log文件"
    echo "     - !*.txt     排除所有txt文件(优先于包含规则)"
    echo "     - !/dist     排除名为dist的文件或目录"
    echo ""
    echo "示例:"
    echo "  syncf -z filelist.txt myproject  # 打包filelist.txt中的文件"
    echo "  syncf -uz myproject_20250930_1230.tar.gz  # 解包并同步文件"
    echo ""
    echo "说明:"
    echo "  1. filelist文件包含要同步的文件/文件夹路径（相对当前目录）"
    echo "  2. 打包文件存储在: $SYNC_DIR"
    echo "  3. 解包时文件将恢复到当前目录的对应位置"
}

# 列出同步目录中的文件
list_files() {
    echo "同步目录内容 ($SYNC_DIR):"
    if [ -z "$(ls -A "$SYNC_DIR")" ]; then
        echo "  (空目录)"
    else
        ls -lh "$SYNC_DIR" | grep -v '^total' | grep -v '.tmp'
    fi
}

# 检查路径是否匹配排除规则
should_exclude() {
    local path="$1"
    shift
    local exclude_patterns=("$@")
    
    for pattern in "${exclude_patterns[@]}"; do
        # 跳过空模式
        if [ -z "$pattern" ]; then
            continue
        fi
        
        # 将gitignore风格模式转换为find -path模式
        local find_pattern="$pattern"
        
        # 处理目录匹配: 如果以/结尾，匹配目录及其内容
        if [[ "$find_pattern" == */ ]]; then
            find_pattern="${find_pattern}*"
        fi
        
        # 处理以/开头的模式: 匹配从当前目录开始的路径
        if [[ "$find_pattern" == /* ]]; then
            find_pattern=".${find_pattern}"
        fi
        
        # 处理通配符: 将*转换为find可识别的通配符
        find_pattern=$(echo "$find_pattern" | sed 's/\*/[^\/]*/g')
        
        # 检查是否匹配
        if [[ "$path" =~ $find_pattern ]] || [[ "$path" == "$pattern" ]]; then
            return 0  # 匹配排除规则
        fi
    done
    
    return 1  # 不匹配任何排除规则
}

# 使用find命令收集文件，应用排除规则
collect_files_with_excludes() {
    local base_dir="$1"
    local filelist="$2"
    local output_file="$3"
    
    # 读取文件列表，分离包含和排除规则
    local include_items=()
    local exclude_patterns=()
    
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释行
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        
        # 排除规则以!开头
        if [[ "$line" == \!* ]]; then
            # 去掉开头的!，保留剩余部分作为排除模式
            local pattern="${line:1}"
            # 移除可能的空格
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$pattern" ]; then
                exclude_patterns+=("$pattern")
            fi
        else
            # 包含项目
            local item="$line"
            # 移除可能的空格
            item=$(echo "$item" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$item" ]; then
                include_items+=("$item")
            fi
        fi
    done < "$filelist"
    
    # 如果没有包含项目，报错
    if [ ${#include_items[@]} -eq 0 ]; then
        echo "错误: 文件列表中没有包含任何文件或目录"
        return 1
    fi
    
    # 临时文件存储find结果
    local temp_filelist=$(mktemp)
    
    # 处理每个包含项目
    for item in "${include_items[@]}"; do
        # 检查项目是否存在
        if [ ! -e "$item" ]; then
            echo "警告: 路径 '$item' 不存在，跳过"
            continue
        fi
        
        if [ -d "$item" ]; then
            # 对于目录，使用find获取所有文件
            find "$item" -type f | while read -r file; do
                # 获取相对于基础目录的路径
                local rel_path="${file#$base_dir/}"
                
                # 检查是否应该排除
                if should_exclude "$rel_path" "${exclude_patterns[@]}"; then
                    continue
                fi
                
                # 记录文件
                echo "$rel_path" >> "$temp_filelist"
            done
        else
            # 对于单个文件
            local rel_path="${item#$base_dir/}"
            
            # 检查是否应该排除
            if should_exclude "$rel_path" "${exclude_patterns[@]}"; then
                continue
            fi
            
            echo "$rel_path" >> "$temp_filelist"
        fi
    done
    
    # 去重排序
    sort -u "$temp_filelist" > "$output_file"
    
    # 清理临时文件
    rm -f "$temp_filelist"
    
    return 0
}

# 打包文件
pack_files() {
    local filelist="$1"
    local name="$2"
    local timestamp=$(date +%Y%m%d_%H%M)
    local package="${name}_${timestamp}.tar.gz"
    local new_filelist="${name}_filelist"
    local abs_filelist=$(realpath "$filelist")
    
    # 检查文件列表是否存在
    if [ ! -f "$abs_filelist" ]; then
        echo "错误: 文件列表 '$filelist' 不存在"
        exit 1
    fi
    
    # 创建临时工作目录
    local temp_work_dir=$(mktemp -d)
    local files_dir="$temp_work_dir/files"
    mkdir -p "$files_dir"
    
    echo "开始打包操作..."
    echo "├─ 工作目录: $(pwd)"
    echo "├─ 文件列表: $abs_filelist"
    echo "├─ 包名称: $package"
    echo "├─ 解析排除规则..."
    
    # 创建新的文件列表，应用排除规则
    local processed_files=0
    local temp_new_filelist=$(mktemp)
    
    if ! collect_files_with_excludes "$(pwd)" "$abs_filelist" "$temp_new_filelist"; then
        echo "错误: 收集文件失败"
        rm -rf "$temp_work_dir"
        rm -f "$temp_new_filelist"
        exit 1
    fi
    
    # 统计文件数量
    processed_files=$(wc -l < "$temp_new_filelist")
    
    if [ $processed_files -eq 0 ]; then
        echo "错误: 没有找到有效的文件进行打包"
        rm -rf "$temp_work_dir"
        rm -f "$temp_new_filelist"
        exit 1
    fi
    
    echo "├─ 找到 $processed_files 个文件"
    echo "├─ 复制文件..."
    
    # 读取文件列表并复制文件
    while IFS= read -r rel_path || [[ -n "$rel_path" ]]; do
        if [ -z "$rel_path" ]; then
            continue
        fi
        
        local src="$rel_path"
        local dest="$files_dir/$rel_path"
        local dest_dir=$(dirname "$dest")
        
        # 确保目标目录存在
        mkdir -p "$dest_dir"
        
        if [ -f "$src" ]; then
            echo "│   ├─ 添加文件: $rel_path"
            cp -r "$src" "$dest"
        fi
    done < "$temp_new_filelist"
    
    # 将文件列表移到临时工作目录
    mv "$temp_new_filelist" "$temp_work_dir/$new_filelist"
    
    # 创建压缩包
    echo "├─ 创建压缩包..."
    tar -czf "$SYNC_DIR/$package" -C "$temp_work_dir" .
    
    # 清理临时文件
    rm -rf "$temp_work_dir"
    
    echo "└─ 完成! 创建包: $SYNC_DIR/$package ($(du -h "$SYNC_DIR/$package" | cut -f1))"
}

# -zg Git 自动打包
pack_from_git(){
  local name=$1
  local tmp_list=$(mktemp)

  git rev-parse --git-dir >/dev/null 2>&1 || {
    echo "错误：当前目录不是 Git 仓库"; exit 1; }

  # 生成文件清单（已修改/新增/暂存）
  git status -z | awk 'BEGIN{RS="\0"} {print substr($0,4)}' > "$tmp_list"

  [[ -s $tmp_list ]] || {
    echo "Git 未检测到任何改动，无需打包"; rm -f "$tmp_list"; exit 0; }

  echo "Git 检测到以下文件将被自动打包："
  cat "$tmp_list" | tr '\0' '\n'

  pack_files "$tmp_list" "$name"
  rm -f "$tmp_list"
}

# 解包并同步文件
unpack_files() {
    local package="$1"
    local package_path="$SYNC_DIR/$package"
    
    # 检查包是否存在
    if [ ! -f "$package_path" ]; then
        echo "错误: 包 '$package' 不存在于 $SYNC_DIR"
        exit 1
    fi
    
    echo "开始解包操作..."
    echo "├─ 工作目录: $(pwd)"
    echo "├─ 包文件: $package_path"
    
    # 清理临时目录
    rm -rf "$TEMP_DIR"/*
    
    # 解压到临时目录
    echo "├─ 解压文件..."
    tar -xzf "$package_path" -C "$TEMP_DIR"
    
    # 查找文件列表
    local filelist=$(find "$TEMP_DIR" -name '*_filelist' | head -n1)
    if [ -z "$filelist" ]; then
        echo "错误: 在包中找不到文件列表"
        exit 1
    fi
    
    echo "├─ 使用文件列表: $(basename "$filelist")"
    
    # 记录原始文件权限
    declare -A file_permissions
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释行
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        
        # 检查文件是否存在并记录权限
        if [ -e "$line" ]; then
            local perms=$(stat -c "%a" "$line")
            file_permissions["$line"]=$perms
        fi
    done < "$filelist"
    
    # 复制文件到目标位置
    local files_dir="$TEMP_DIR/files"
    local files_copied=0
    
    echo "├─ 同步文件..."
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释行
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        
        local src="$files_dir/$line"
        local dest="$line"
        local dest_dir=$(dirname "$dest")
        
        # 确保目标目录存在
        mkdir -p "$dest_dir"
        
        if [ -f "$src" ]; then
            echo "│   ├─ 同步: $line"
            cp -f "$src" "$dest"
            files_copied=$((files_copied + 1))
            
            # 恢复原始权限（如果存在）
            if [ -n "${file_permissions[$line]}" ]; then
                chmod "${file_permissions[$line]}" "$dest"
            fi
        fi
    done < "$filelist"
    
    # 清理临时文件
    rm -rf "$TEMP_DIR"/*
    
    echo "└─ 完成! 同步了 $files_copied 个文件"
}

# 主程序
if [ $# -eq 0 ]; then
    show_help
    exit 0
fi

case $1 in
    -z)
        if [ $# -ne 3 ]; then
            echo "用法: syncf -z <filelist> <name>"
            exit 1
        fi
        pack_files "$2" "$3"
        ;;
    -zg)
        if [ $# -ne 2 ]; then
            echo "用法: syncf -zg <name>"
            exit 1
        fi
        pack_from_git "$2"
        ;;
    -uz)
        if [ $# -ne 2 ]; then
            echo "用法: syncf -uz <package>"
            exit 1
        fi
        unpack_files "$2"
        ;;
    -l)
        list_files
        ;;
    -h|--help)
        show_help
        ;;
    *)
        echo "错误: 无效选项 '$1'"
        echo "使用 syncf -h 查看帮助"
        exit 1
        ;;
esac
