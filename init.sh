#!/bin/bash

# Bash Scripts Manager - Initialization Script
# 修正工具脚本查询

set -e

# 获取脚本目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/scripts.yaml"
BIN_DIR="${SCRIPT_DIR}/bin"
BASHRC_FILE="${HOME}/.bashrc"
YQ_PATH="${BIN_DIR}/yq"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
BOLD='\033[1m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 yq 是否存在
check_yq() {
    if [[ ! -x "$YQ_PATH" ]]; then
        log_error "yq 工具未找到或不可执行: $YQ_PATH"
        log_error "请确保 yq 二进制文件存在于 bin 目录中"
        exit 1
    fi
}

# 显示横幅
show_banner() {
    echo -e "${BOLD}${CYAN}"
    echo "╔══════════════════════════════════════════════════╗"
    echo "║   Bash Scripts Manager Initialization (v2.0)     ║"
    echo "╚══════════════════════════════════════════════════╝"
    echo ""
}

# 使用 yq 解析启动脚本
parse_startup_scripts() {
    local config_file="$1"
    
    "$YQ_PATH" e '.scripts.startup[] | select(.enabled == true) | [.name, .path, .description] | join(":")' "$config_file" 2>/dev/null
}

# 使用 yq 解析工具脚本
parse_tools_scripts() {
    local config_file="$1"
    
    # 使用与手动测试相同的查询
    "$YQ_PATH" e '.scripts.tools[] | select(.enabled == true) | [.name, .path, (.aliases | join(",")), .description] | join(":")' "$config_file" 2>/dev/null
}

# 清理.bashrc
cleanup_bashrc() {
    log_info "清理.bashrc中的旧配置..."
    
    if [[ ! -f "$BASHRC_FILE" ]]; then
        log_warning ".bashrc文件不存在: $BASHRC_FILE"
        return 0
    fi
    
    # 备份
    local backup_file="$BASHRC_FILE.bak.$(date +%Y%m%d%H%M%S)"
    cp "$BASHRC_FILE" "$backup_file" 2>/dev/null || true
    log_info "备份创建: $backup_file"
    
    # 移除旧配置
    if grep -q "# Added by Bash Scripts Manager" "$BASHRC_FILE" 2>/dev/null; then
        local temp_file
        temp_file=$(mktemp)
        
        awk '
        /# Added by Bash Scripts Manager/ { skip=1; next }
        /# End of Bash Scripts Manager/ { skip=0; next }
        skip == 0 { print }
        ' "$BASHRC_FILE" > "$temp_file"
        
        mv "$temp_file" "$BASHRC_FILE"
        log_success "已清理.bashrc中的旧配置"
    else
        log_info ".bashrc中没有找到旧配置"
    fi
}

# 清理bin目录
cleanup_bin() {
    log_info "清理bin目录: $BIN_DIR"
    
    if [[ -d "$BIN_DIR" ]]; then
        find "$BIN_DIR" -type l -delete 2>/dev/null || true
        log_success "已清理bin目录"
    else
        log_info "bin目录不存在，正在创建"
        mkdir -p "$BIN_DIR"
    fi
}

# 添加启动脚本
add_startup_script() {
    local name="$1"
    local path="$2"
    local description="$3"
    
    # 解析路径
    local full_path="$path"
    if [[ ! -f "$full_path" ]]; then
        # 尝试相对路径
        if [[ -f "$SCRIPT_DIR/startup/$path" ]]; then
            full_path="$SCRIPT_DIR/startup/$path"
        elif [[ -f "$SCRIPT_DIR/$path" ]]; then
            full_path="$SCRIPT_DIR/$path"
        else
            log_warning "启动脚本未找到: $path (尝试了: $SCRIPT_DIR/startup/$path 和 $SCRIPT_DIR/$path)"
            return 0
        fi
    fi
    
    local source_line="source \"$full_path\""
    
    # 使用grep检查，但不因grep失败而停止
    if ! grep -qF "$source_line" "$BASHRC_FILE" 2>/dev/null; then
        {
            echo ""
            echo "# Added by Bash Scripts Manager"
            echo "# Startup: $description"
            echo "$source_line"
            echo "# End of Bash Scripts Manager"
            echo ""
        } >> "$BASHRC_FILE" 2>/dev/null || {
            log_error "无法写入.bashrc文件"
            return 1
        }
        log_success "已添加启动脚本: $name"
    else
        log_info "启动脚本已存在: $name"
    fi
    
    return 0
}

# 创建工具脚本软链接
create_tool_symlink() {
    local name="$1"
    local path="$2"
    local alias="$3"
    local description="$4"
    
    # 解析路径
    local full_path="$path"
    if [[ ! -f "$full_path" ]]; then
        if [[ -f "$SCRIPT_DIR/tools/$path" ]]; then
            full_path="$SCRIPT_DIR/tools/$path"
        elif [[ -f "$SCRIPT_DIR/$path" ]]; then
            full_path="$SCRIPT_DIR/$path"
        else
            log_warning "工具脚本未找到: $path (尝试了: $SCRIPT_DIR/tools/$path 和 $SCRIPT_DIR/$path)"
            return 0
        fi
    fi
    
    local symlink_path="$BIN_DIR/$alias"
    
    # 移除现有软链接
    if [[ -L "$symlink_path" ]]; then
        rm -f "$symlink_path" 2>/dev/null || true
    fi
    
    # 创建新软链接
    if ln -sf "$full_path" "$symlink_path" 2>/dev/null; then
        chmod +x "$full_path" 2>/dev/null || true
        log_success "已创建软链接: $alias -> $name"
    else
        log_error "创建软链接失败: $alias -> $name"
        return 1
    fi
    
    return 0
}

# 添加bin目录到PATH
add_bin_to_path() {
    local path_line="export PATH=\"$BIN_DIR:\$PATH\""
    
    if ! grep -qF "$path_line" "$BASHRC_FILE" 2>/dev/null; then
        {
            echo ""
            echo "# Added by Bash Scripts Manager"
            echo "# Add bin directory to PATH"
            echo "$path_line"
            echo "# End of Bash Scripts Manager"
            echo ""
        } >> "$BASHRC_FILE" 2>/dev/null || {
            log_error "无法写入.bashrc文件"
            return 1
        }
        log_success "已添加bin目录到PATH"
    else
        log_info "bin目录已在PATH中"
    fi
    
    return 0
}

# 链接管理器脚本
link_manager_script() {
    local manager_script="$SCRIPT_DIR/bash_manager.sh"
    local symlink_path="$BIN_DIR/shmng"
    
    if [[ -f "$manager_script" ]]; then
        if [[ -L "$symlink_path" ]]; then
            rm -f "$symlink_path" 2>/dev/null || true
        fi
        
        if ln -sf "$manager_script" "$symlink_path" 2>/dev/null; then
            chmod +x "$manager_script" 2>/dev/null || true
            log_success "已创建管理器软链接: shmng"
        else
            log_error "创建管理器软链接失败"
        fi
    else
        log_warning "管理器脚本未找到: $manager_script"
    fi
    
    return 0
}

# 主函数
main() {
    show_banner
    check_yq
    
    # 创建目录
    mkdir -p "$BIN_DIR" "$SCRIPT_DIR/startup" "$SCRIPT_DIR/tools" 2>/dev/null || true
    
    # 清理
    cleanup_bashrc
    cleanup_bin
    
    # 检查配置文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "配置文件未找到: $CONFIG_FILE"
        exit 1
    fi
    
    log_info "解析配置文件: $CONFIG_FILE"
    
    # 解析配置
    local processed_startup=0
    local processed_tools=0
    local total_symlinks=0
    
    # 处理启动脚本
    while IFS=':' read -r name path description; do
        [[ -z "$name" ]] && continue
        log_info "处理启动脚本: $name"
        if add_startup_script "$name" "$path" "$description"; then
            processed_startup=$((processed_startup + 1))
        fi
    done < <(parse_startup_scripts "$CONFIG_FILE")
    
    # 处理工具脚本
    while IFS=':' read -r name path aliases description; do
        [[ -z "$name" ]] && continue
        log_info "处理工具脚本: $name"
        
        # 创建所有别名的软链接
        IFS=',' read -ra alias_array <<< "$aliases"
        for alias in "${alias_array[@]}"; do
            alias=$(echo "$alias" | xargs)
            if [[ -n "$alias" ]]; then
                if create_tool_symlink "$name" "$path" "$alias" "$description"; then
                    total_symlinks=$((total_symlinks + 1))
                fi
            fi
        done
        processed_tools=$((processed_tools + 1))
    done < <(parse_tools_scripts "$CONFIG_FILE")
    
    # 添加PATH
    add_bin_to_path
    
    # 链接管理器
    link_manager_script
    
    # 总结
    echo ""
    echo -e "${GREEN}${BOLD}✓ 初始化完成!${NC}"
    echo ""
    echo -e "${CYAN}${BOLD}总结:${NC}"
    echo -e "  ${BLUE}•${NC} 启动脚本处理: $processed_startup"
    echo -e "  ${BLUE}•${NC} 工具脚本处理: $processed_tools"
    echo -e "  ${BLUE}•${NC} 软链接创建: $total_symlinks"
    echo ""
    echo -e "${YELLOW}${BOLD}⚠ 下一步:${NC}"
    echo -e "  运行: ${CYAN}source $BASHRC_FILE${NC} 立即应用更改"
    echo ""
}

# 运行主函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
