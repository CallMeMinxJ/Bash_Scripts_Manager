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
    echo "  2. 以'!'开头的行是排除规则(支持类gitignore模式)"
    echo "  3. 支持的模式规则:"
    echo "     - *.txt       匹配当前目录下的txt文件"
    echo "     - **/*.txt    匹配所有子目录中的txt文件"
    echo "     - /dist       只匹配根目录下的dist文件/目录"
    echo "     - dir/        匹配dir目录及其所有内容"
    echo "     - !*.log      排除所有log文件"
    echo "     - !**/*.tmp   排除所有子目录中的tmp文件"
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

# 将gitignore模式转换为正则表达式
pattern_to_regex() {
    local pattern="$1"
    
    # 如果模式以!开头，去掉!并标记为排除
    local exclude_flag=0
    if [[ "$pattern" == \!* ]]; then
        pattern="${pattern:1}"
        exclude_flag=1
    fi
    
    # 去除首尾空格
    pattern="$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    
    # 如果是空模式，返回
    [ -z "$pattern" ] && return
    
    # 转义正则特殊字符（除了*和?）
    pattern=$(echo "$pattern" | sed 's/\./\\./g; s/\[/\\[/g; s/\]/\\]/g; s/\+/\\+/g; s/\^/\\^/g; s/\$/\\$/g')
    
    # 处理特殊模式
    local regex=""
    
    # 如果模式以/开头，表示从根目录开始匹配
    if [[ "$pattern" == /* ]]; then
        pattern="${pattern:1}"
        regex="^"
    else
        regex="(^|/)"
    fi
    
    # 将模式分割为多个部分
    local parts=()
    IFS='/' read -ra parts <<< "$pattern"
    
    for i in "${!parts[@]}"; do
        local part="${parts[i]}"
        
        if [ $i -gt 0 ]; then
            regex="${regex}/"
        fi
        
        # 处理**通配符
        if [ "$part" = "**" ]; then
            regex="${regex}([^/]+/)*"
            continue
        fi
        
        # 处理普通的*和?
        local processed_part=""
        local len=${#part}
        
        for ((j=0; j<len; j++)); do
            local char="${part:$j:1}"
            
            if [ "$char" = "*" ]; then
                # 处理**
                if [ $j -lt $((len-1)) ] && [ "${part:$((j+1)):1}" = "*" ]; then
                    processed_part="${processed_part}.*"
                    ((j++))  # 跳过第二个*
                else
                    # 单个*，不匹配/
                    processed_part="${processed_part}[^/]*"
                fi
            elif [ "$char" = "?" ]; then
                processed_part="${processed_part}[^/]"
            else
                processed_part="${processed_part}$char"
            fi
        done
        
        regex="${regex}${processed_part}"
    done
    
    # 如果模式以/结尾，表示匹配目录
    if [[ "$pattern" == */ ]]; then
        regex="${regex}($|/.*)"
    else
        regex="${regex}$"
    fi
    
    # 返回结果
    if [ $exclude_flag -eq 1 ]; then
        echo "!$regex"
    else
        echo "$regex"
    fi
}

# 检查路径是否匹配模式
match_pattern() {
    local path="$1"
    local pattern_regex="$2"
    
    # 处理排除标记
    local exclude_flag=0
    if [[ "$pattern_regex" == \!* ]]; then
        pattern_regex="${pattern_regex:1}"
        exclude_flag=1
    fi
    
    # 检查是否匹配
    if [[ "$path" =~ $pattern_regex ]]; then
        return 0  # 匹配
    else
        return 1  # 不匹配
    fi
}

# 检查路径是否应该排除
should_exclude() {
    local path="$1"
    shift
    local exclude_patterns=("$@")
    
    for pattern in "${exclude_patterns[@]}"; do
        # 跳过空模式
        if [ -z "$pattern" ]; then
            continue
        fi
        
        # 将模式转换为正则表达式
        local regex_pattern=$(pattern_to_regex "$pattern")
        
        # 检查匹配
        if match_pattern "$path" "$regex_pattern"; then
            return 0  # 应该排除
        fi
    done
    
    return 1  # 不应该排除
}

# 使用find命令收集文件，应用排除规则
collect_files_with_excludes() {
    local base_dir="$1"
    local filelist="$2"
    local output_file="$3"
    
    # 读取文件列表，分离包含和排除规则
    local include_patterns=()
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
            # 包含模式
            local pattern="$line"
            # 移除可能的空格
            pattern=$(echo "$pattern" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
            if [ -n "$pattern" ]; then
                include_patterns+=("$pattern")
            fi
        fi
    done < "$filelist"
    
    # 如果没有包含模式，报错
    if [ ${#include_patterns[@]} -eq 0 ]; then
        echo "错误: 文件列表中没有包含任何文件或目录"
        return 1
    fi
    
    # 临时文件存储find结果
    local temp_filelist=$(mktemp)
    
    # 处理每个包含模式
    for pattern in "${include_patterns[@]}"; do
        # 将模式转换为正则表达式
        local regex_pattern=$(pattern_to_regex "$pattern")
        
        # 判断是否是排除模式
        local is_exclude=0
        if [[ "$regex_pattern" == \!* ]]; then
            regex_pattern="${regex_pattern:1}"
            is_exclude=1
        fi
        
        # 如果模式以/结尾，表示是目录模式
        if [[ "$pattern" == */ ]]; then
            # 去掉结尾的/
            local dir_pattern="${pattern%/}"
            
            # 处理目录模式
            if [ -d "$dir_pattern" ]; then
                # 使用find查找目录下的所有文件
                find "$dir_pattern" -type f 2>/dev/null | while read -r file; do
                    # 获取相对于基础目录的路径
                    local rel_path="${file#$base_dir/}"
                    
                    # 跳过空路径
                    [ -z "$rel_path" ] && continue
                    
                    # 检查是否应该排除
                    if should_exclude "$rel_path" "${exclude_patterns[@]}"; then
                        continue
                    fi
                    
                    # 记录文件
                    echo "$rel_path" >> "$temp_filelist"
                done
            fi
        elif [[ "$pattern" == /* ]]; then
            # 以/开头的模式，匹配根目录
            local file_path="${pattern:1}"
            if [ -e "$file_path" ]; then
                if [ -d "$file_path" ]; then
                    find "$file_path" -type f 2>/dev/null | while read -r file; do
                        local rel_path="${file#$base_dir/}"
                        [ -z "$rel_path" ] && continue
                        
                        if should_exclude "$rel_path" "${exclude_patterns[@]}"; then
                            continue
                        fi
                        echo "$rel_path" >> "$temp_filelist"
                    done
                else
                    local rel_path="${file_path#$base_dir/}"
                    [ -z "$rel_path" ] && continue
                    
                    if should_exclude "$rel_path" "${exclude_patterns[@]}"; then
                        continue
                    fi
                    echo "$rel_path" >> "$temp_filelist"
                fi
            fi
        else
            # 使用find查找所有文件，然后用模式匹配
            find . -type f 2>/dev/null | while read -r file; do
                # 获取相对于基础目录的路径
                local rel_path="${file#./}"
                
                # 跳过空路径
                [ -z "$rel_path" ] && continue
                
                # 检查是否匹配包含模式
                if match_pattern "$rel_path" "$regex_pattern"; then
                    # 检查是否应该排除
                    if should_exclude "$rel_path" "${exclude_patterns[@]}"; then
                        continue
                    fi
                    
                    echo "$rel_path" >> "$temp_filelist"
                fi
            done
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
    echo "├─ 解析包含/排除规则..."
    
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
