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
    echo "  syncf -zg <name>                : 自动打包git改动文件
    echo "  syncf -uz <package>             : 解包并同步文件到本地"
    echo "  syncf -l                        : 列出同步目录中的文件"
    echo "  syncf -h                        : 显示帮助信息"
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
    
    # 创建新的文件列表
    local processed_files=0
    while IFS= read -r line || [[ -n "$line" ]]; do
        # 跳过空行和注释行
        if [[ -z "$line" || "$line" == \#* ]]; then
            continue
        fi
        
        # 处理相对路径
        local item=$(realpath -s --relative-to="$(pwd)" "$line" 2>/dev/null)
        
        if [ -z "$item" ]; then
            echo "警告: 跳过无效路径 '$line'"
            continue
        fi
        
        # 检查文件/目录是否存在
        if [ ! -e "$item" ]; then
            echo "警告: 路径 '$item' 不存在，跳过"
            continue
        fi
        
        # 复制文件到临时目录
        local dest_dir="$files_dir/$(dirname "$item")"
        mkdir -p "$dest_dir"
        
        if [ -d "$item" ]; then
            echo "├─ 添加目录: $item"
            cp -r "$item" "$dest_dir/"
            # 记录目录中的所有文件
            find "$item" -type f -print >> "$temp_work_dir/$new_filelist"
            processed_files=$((processed_files + $(find "$item" -type f | wc -l)))
        else
            echo "├─ 添加文件: $item"
            cp -r "$item" "$dest_dir/"
            echo "$item" >> "$temp_work_dir/$new_filelist"
            processed_files=$((processed_files + 1))
        fi
    done < "$abs_filelist"
    
    if [ $processed_files -eq 0 ]; then
        echo "错误: 没有找到有效的文件进行打包"
        rm -rf "$temp_work_dir"
        exit 1
    fi
    
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
        if [$# -ne 2]; then
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
