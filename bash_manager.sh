#!/bin/bash
# Bash Scripts Manager - Interactive Management Tool
# 优雅美观的 bash 脚本管理工具

set -eo pipefail

# ============================================
# 配置和路径
# ============================================

# 获取脚本真实路径（支持软链接）
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONFIG_FILE="${SCRIPT_DIR}/scripts.yaml"
BACKUP_DIR="${SCRIPT_DIR}/backups"
BIN_DIR="${SCRIPT_DIR}/bin"
INIT_SCRIPT="${SCRIPT_DIR}/init.sh"
YQ="${BIN_DIR}/yq"
FZF_ENABLED=true
BASHRC="${HOME}/.bashrc"

# ============================================
# 颜色和样式定义
# ============================================

# 颜色代码
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 样式
BOLD='\033[1m'
DIM='\033[2m'
ITALIC='\033[3m'
UNDERLINE='\033[4m'
BLINK='\033[5m'
INVERT='\033[7m'

# 主题颜色
TITLE_COLOR="${CYAN}${BOLD}"
HEADER_COLOR="${BLUE}${BOLD}"
SUCCESS_COLOR="${GREEN}"
WARNING_COLOR="${YELLOW}"
ERROR_COLOR="${RED}"
HIGHLIGHT_COLOR="${PURPLE}"
MUTED_COLOR="${DIM}"
NC_COLOR="${NC}"

# ============================================
# 工具函数
# ============================================

# 带颜色的日志输出
log() {
    echo -e "$1"
}

info() {
    log "${BLUE}[INFO]${NC} $1"
}

warn() {
    log "${YELLOW}[WARNING]${NC} $1"
}

success() {
    log "${GREEN}[SUCCESS]${NC} $1"
}

error() {
    log "${RED}[ERROR]${NC} $1"
}

# 带格式的输出
title() {
    echo -e "\n${TITLE_COLOR}$1${NC_COLOR}"
    echo -e "${DIM}════════════════════════════════════════════════════════${NC_COLOR}"
}

section() {
    echo -e "\n${HEADER_COLOR}▶ $1${NC_COLOR}"
}

bullet() {
    echo -e "  ${GREEN}●${NC} $1"
}

# 带确认的提示
confirm() {
    local prompt="$1"
    local default="${2:-y}"
    
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi
    
    read -p "$(echo -e "${YELLOW}$prompt${NC}")" -r response
    response="${response:-$default}"
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# 获取用户输入
prompt() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local required="${4:-false}"
    
    while true; do
        if [[ -n "$default" ]]; then
            read -p "$(echo -e "${YELLOW}$prompt${NC} [${MUTED_COLOR}$default${NC}]: ")" -r response
        else
            read -p "$(echo -e "${YELLOW}$prompt${NC}: ")" -r response
        fi
        
        response="${response:-$default}"
        
        if [[ "$required" == "true" && -z "$response" ]]; then
            error "此字段为必填项，请重新输入"
        else
            eval "$var_name=\"\$response\""
            break
        fi
    done
}

# 等待用户按键
pause() {
    echo -e "\n${MUTED_COLOR}按任意键继续...${NC}"
    read -n1 -s
}

# 检查命令是否存在
check_command() {
    command -v "$1" &> /dev/null
}

# 检查 fzf
check_fzf() {
    if ! check_command fzf && [[ "$FZF_ENABLED" == "true" ]]; then
        warn "fzf 未安装，将使用简单菜单"
        FZF_ENABLED=false
    fi
}

# 检查 yq
check_yq() {
    if [[ ! -x "$YQ" ]]; then
        error "yq 工具未找到或不可执行: $YQ"
        error "请确保 yq 二进制文件存在于 bin 目录中"
        return 1
    fi
}

# 备份配置文件
backup_config() {
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local backup_path="${BACKUP_DIR}/scripts_${timestamp}.yaml"
    
    mkdir -p "$BACKUP_DIR"
    cp "$CONFIG_FILE" "$backup_path"
    success "配置已备份到: $backup_path"
}

# 验证 YAML
validate_config() {
    if ! "$YQ" e '.' "$CONFIG_FILE" > /dev/null 2>&1; then
        error "YAML 配置文件格式错误"
        return 1
    fi
}

# 获取配置值
get_config() {
    local key="$1"
    "$YQ" e "$key" "$CONFIG_FILE" 2>/dev/null
}

# 显示横幅
show_banner() {
    clear
    echo -e "${TITLE_COLOR}"
    cat << "EOF"
╔══════════════════════════════════════════════════════════╗
║   ██████╗  █████╗ ███████╗██╗  ██╗                       ║
║   ██╔══██╗██╔══██╗██╔════╝██║  ██║                       ║
║   ██████╔╝███████║███████╗███████║                       ║
║   ██╔══██╗██╔══██║╚════██║██╔══██║                       ║
║   ██████╔╝██║  ██║███████║██║  ██║                       ║
║   ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝                       ║
║                                                          ║
║   ███████╗ ██████╗██████╗ ██╗██████╗ ███████╗██████╗     ║
║   ██╔════╝██╔════╝██╔══██╗██║██╔══██╗██╔════╝██╔══██╗    ║
║   ███████╗██║     ██████╔╝██║██████╔╝█████╗  ██████╔╝    ║
║   ╚════██║██║     ██╔═══╝ ██║██╔═══╝ ██╔══╝  ██╔══██╗    ║
║   ███████║╚██████╗██║     ██║██║     ███████╗██║  ██║    ║
║   ╚══════╝ ╚═════╝╚═╝     ╚═╝╚═╝     ╚══════╝╚═╝  ╚═╝    ║
║                                                          ║
║                                                          ║
╚══════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC_COLOR}"
    echo -e "${DIM}项目目录: $SCRIPT_DIR${NC}"
    echo -e "${DIM}配置文件: $CONFIG_FILE${NC}\n"
}

# 显示当前配置状态
show_status() {
    section "📊 当前配置状态"
    
    # 从配置文件中获取信息
    local version=$(get_config '.version')
    local auto_apply=$(get_config '.settings.auto_apply')
    local fzf_ui=$(get_config '.settings.enable_fzf_ui')
    
    echo -e "  ${BLUE}▪${NC} 配置文件版本: ${HIGHLIGHT_COLOR}$version${NC}"
    echo -e "  ${BLUE}▪${NC} 自动应用修改: ${HIGHLIGHT_COLOR}$auto_apply${NC}"
    echo -e "  ${BLUE}▪${NC} FZF 界面: ${HIGHLIGHT_COLOR}$fzf_ui${NC}"
    
    # 启动脚本状态
    echo -e "\n  ${GREEN}🚀 启动脚本:${NC}"
    local startup_count=0
    local startup_enabled=0
    
    # 修复：使用正确的yq查询语法
    local startup_scripts
    startup_scripts=$("$YQ" e '.scripts.startup[] | [.name, .enabled, .description] | join(":")' "$CONFIG_FILE" 2>/dev/null || true)
    
    if [[ -n "$startup_scripts" ]]; then
        while IFS=':' read -r name enabled description; do
            [[ -z "$name" ]] && continue
            startup_count=$((startup_count + 1))
            if [[ "$enabled" == "true" ]]; then
                startup_enabled=$((startup_enabled + 1))
                echo -e "    ${GREEN}✓${NC} $name: $description"
            else
                echo -e "    ${RED}✗${NC} $name: $description"
            fi
        done <<< "$startup_scripts"
    else
        echo -e "    ${MUTED_COLOR}暂无启动脚本${NC}"
    fi
    
    # 工具脚本状态
    echo -e "\n  ${BLUE}🛠️  工具脚本:${NC}"
    local tools_count=0
    local tools_enabled=0
    
    # 修复：使用正确的yq查询语法
    local tools_scripts
    tools_scripts=$("$YQ" e '.scripts.tools[] | [.name, .enabled, .description] | join(":")' "$CONFIG_FILE" 2>/dev/null || true)
    
    if [[ -n "$tools_scripts" ]]; then
        while IFS=':' read -r name enabled description; do
            [[ -z "$name" ]] && continue
            tools_count=$((tools_count + 1))
            if [[ "$enabled" == "true" ]]; then
                tools_enabled=$((tools_enabled + 1))
                echo -e "    ${GREEN}✓${NC} $name: $description"
            else
                echo -e "    ${RED}✗${NC} $name: $description"
            fi
        done <<< "$tools_scripts"
    else
        echo -e "    ${MUTED_COLOR}暂无工具脚本${NC}"
    fi
    
    # 统计信息
    echo -e "\n  ${PURPLE}📈 统计信息:${NC}"
    echo -e "    ${BLUE}▪${NC} 启动脚本: $startup_enabled/$startup_count 已启用"
    echo -e "    ${BLUE}▪${NC} 工具脚本: $tools_enabled/$tools_count 已启用"
    echo -e "    ${BLUE}▪${NC} 总计脚本: $((startup_count + tools_count)) 个"
}

# 通过 fzf 选择脚本
select_script_fzf() {
    local script_type="$1"
    
    # 修复：使用正确的yq查询语法构建选项
    local options
    if [[ "$script_type" == "startup" ]]; then
        options=$("$YQ" e '.scripts.startup[] | [.name, (if .enabled then "✓" else "✗" end), .description, .path, .category] | join(":")' "$CONFIG_FILE" 2>/dev/null)
    else
        options=$("$YQ" e '.scripts.tools[] | [.name, (if .enabled then "✓" else "✗" end), .description, .path, .category] | join(":")' "$CONFIG_FILE" 2>/dev/null)
    fi
    
    if [[ -z "$options" ]]; then
        warn "没有找到 $script_type 类型的脚本"
        return 1
    fi
    
    # 构建 fzf 预览界面
    local preview_cmd="
    echo '脚本详情:'; 
    echo '名称: \$(echo {} | cut -d: -f1)'; 
    echo '状态: \$(echo {} | cut -d: -f2)'; 
    echo '描述: \$(echo {} | cut -d: -f3)'; 
    echo '路径: \$(echo {} | cut -d: -f4)'; 
    echo '分类: \$(echo {} | cut -d: -f5)';
    "
    
    # 使用 fzf 选择
    local selected
    selected=$(echo "$options" | fzf \
        --height=40% \
        --border=rounded \
        --prompt="🔍 选择脚本: " \
        --header="使用 ↑↓ 键导航, Enter 选择, ESC 取消" \
        --preview="$preview_cmd" \
        --preview-window=right:60%:wrap \
        --color=bg+:#4c566a,bg:#2e3440,spinner:#81a1c1,hl:#88c0d0 \
        --color=fg:#d8dee9,header:#88c0d0,info:#5e81ac,pointer:#81a1c1 \
        --color=marker:#81a1c1,fg+:#eceff4,prompt:#5e81ac,hl+:#88c0d0 \
        --ansi)
    
    if [[ -n "$selected" ]]; then
        echo "$(echo "$selected" | cut -d: -f1)"
    else
        echo ""
    fi
}

# 通过简单菜单选择脚本
select_script_simple() {
    local script_type="$1"
    
    echo -e "\n${HEADER_COLOR}📁 选择脚本:${NC}"
    
    local idx=1
    declare -A scripts
    
    # 修复：使用正确的yq查询语法获取脚本列表
    local script_list
    if [[ "$script_type" == "startup" ]]; then
        script_list=$("$YQ" e '.scripts.startup[] | [.name, .enabled, .description] | join(":")' "$CONFIG_FILE" 2>/dev/null || true)
    else
        script_list=$("$YQ" e '.scripts.tools[] | [.name, .enabled, .description] | join(":")' "$CONFIG_FILE" 2>/dev/null || true)
    fi
    
    if [[ -z "$script_list" ]]; then
        warn "没有找到 $script_type 类型的脚本"
        return 1
    fi
    
    while IFS=':' read -r name enabled description; do
        [[ -z "$name" ]] && continue
        local status
        [[ "$enabled" == "true" ]] && status="${GREEN}✓${NC}" || status="${RED}✗${NC}"
        echo -e "  ${BLUE}$idx${NC}. $status $name: $description"
        scripts["$idx"]="$name"
        idx=$((idx + 1))
    done <<< "$script_list"
    
    [[ $idx -eq 1 ]] && {
        warn "没有找到 $script_type 类型的脚本"
        return 1
    }
    
    echo -e "  ${MUTED_COLOR}0. 返回${NC}"
    
    while true; do
        echo -ne "\n${YELLOW}请输入选择 (0-$((idx-1))): ${NC}"
        read -r choice
        
        if [[ "$choice" == "0" ]]; then
            return 1
        elif [[ -n "${scripts[$choice]}" ]]; then
            echo "${scripts[$choice]}"
            return 0
        else
            error "无效的选择"
        fi
    done
}

# 切换脚本状态
toggle_script() {
    local script_name="$1"
    local script_type="$2"
    
    # 修复：获取当前状态
    local current_status
    current_status=$("$YQ" e ".scripts.$script_type[] | select(.name == \"$script_name\") | .enabled" "$CONFIG_FILE" 2>/dev/null)
    
    if [[ -z "$current_status" ]]; then
        error "未找到脚本: $script_name"
        return 1
    fi
    
    local new_status
    if [[ "$current_status" == "true" ]]; then
        new_status=false
        "$YQ" e "(.scripts.$script_type[] | select(.name == \"$script_name\") | .enabled) = $new_status" -i "$CONFIG_FILE"
        success "已禁用脚本: $script_name"
    else
        new_status=true
        "$YQ" e "(.scripts.$script_type[] | select(.name == \"$script_name\") | .enabled) = $new_status" -i "$CONFIG_FILE"
        success "已启用脚本: $script_name"
    fi
    
    validate_config
    
    # 询问是否立即应用
    if [[ "$(get_config '.settings.auto_apply')" == "true" ]]; then
        apply_changes
    else
        if confirm "是否立即应用更改？"; then
            apply_changes
        else
            info "更改已保存，但尚未应用。请在主菜单中选择'应用更改'来应用。"
        fi
    fi
}

# 添加新脚本
add_new_script() {
    section "➕ 添加新脚本"
    
    local script_type
    echo -e "${HEADER_COLOR}选择脚本类型:${NC}"
    echo -e "  ${BLUE}1.${NC} 🚀 启动脚本 (随终端启动)"
    echo -e "  ${BLUE}2.${NC} 🛠️  工具脚本 (手动调用)"
    echo -e "  ${MUTED_COLOR}0. 返回${NC}"
    
    read -p "$(echo -e "\n${YELLOW}请选择: ${NC}")" -r type_choice
    
    case "$type_choice" in
        1) script_type="startup" ;;
        2) script_type="tools" ;;
        0) return ;;
        *) error "无效选择"; return 1 ;;
    esac
    
    # 收集脚本信息
    echo -e "\n${HEADER_COLOR}请输入脚本信息:${NC}"
    
    local name description path category enabled aliases_str
    prompt "脚本名称" "" "name" true
    prompt "脚本描述" "" "description" true
    prompt "脚本路径 (相对于 $script_type/ 目录)" "" "path" true
    
    if [[ "$script_type" == "tools" ]]; then
        prompt "别名 (逗号分隔，如: sf,syncf)" "" "aliases_str"
    fi
    
    prompt "分类" "" "category"
    
    if confirm "是否启用此脚本？"; then
        enabled=true
    else
        enabled=false
    fi
    
    # 备份并添加配置
    backup_config
    
    # 构建 yq 命令
    if [[ "$script_type" == "tools" ]]; then
        # 处理别名数组
        IFS=',' read -ra aliases_array <<< "$aliases_str"
        local aliases_json="["
        for alias in "${aliases_array[@]}"; do
            alias=$(echo "$alias" | xargs)
            [[ -n "$alias" ]] && aliases_json+="\"$alias\","
        done
        aliases_json="${aliases_json%,}]"
        [[ "$aliases_json" == "]" ]] && aliases_json="[]"
        
        # 添加新条目
        "$YQ" e ".scripts.$script_type += {
            \"name\": \"$name\",
            \"description\": \"$description\",
            \"path\": \"$path\",
            \"enabled\": $enabled,
            \"category\": \"$category\",
            \"aliases\": $aliases_json
        }" -i "$CONFIG_FILE"
    else
        # 添加新条目
        "$YQ" e ".scripts.$script_type += {
            \"name\": \"$name\",
            \"description\": \"$description\",
            \"path\": \"$path\",
            \"enabled\": $enabled,
            \"category\": \"$category\"
        }" -i "$CONFIG_FILE"
    fi
    
    if validate_config; then
        success "脚本 '$name' 已成功添加！"
        
        if [[ "$enabled" == "true" ]] && confirm "是否立即应用更改？"; then
            apply_changes
        fi
    else
        error "添加脚本失败，配置格式错误"
        return 1
    fi
}

# 应用更改
apply_changes() {
    section "🔄 应用更改"
    
    if [[ ! -x "$INIT_SCRIPT" ]]; then
        error "初始化脚本不存在或不可执行: $INIT_SCRIPT"
        return 1
    fi
    
    echo -e "${HEADER_COLOR}正在应用更改...${NC}"
    
    # 显示进度动画
    for i in {1..10}; do
        local percent=$((i * 10))
        local width=50
        local filled=$((width * percent / 100))
        local empty=$((width - filled))
        
        printf "["
        printf "%${filled}s" | tr " " "█"
        printf "%${empty}s" | tr " " "░"
        printf "] %3d%%" "$percent"
        printf "\r"
        sleep 0.05
    done
    echo
    
    # 执行初始化脚本
    if bash "$INIT_SCRIPT"; then
        success "更改已成功应用！"
        success "请运行 ${HIGHLIGHT_COLOR}source ~/.bashrc${NC} 或重新启动终端使更改生效。"
    else
        error "应用更改时出错"
        return 1
    fi
}

# 编辑脚本
edit_script() {
    local script_name="$1"
    local script_type="$2"
    
    # 修复：获取脚本路径
    local script_path
    script_path=$("$YQ" e ".scripts.$script_type[] | select(.name == \"$script_name\") | .path" "$CONFIG_FILE" 2>/dev/null)
    
    if [[ -z "$script_path" ]]; then
        error "未找到脚本路径"
        return 1
    fi
    
    # 构建完整路径
    local full_path="${SCRIPT_DIR}/${script_type}/${script_path}"
    
    if [[ ! -f "$full_path" ]]; then
        error "脚本文件不存在: $full_path"
        return 1
    fi
    
    # 使用系统编辑器
    local editor="${EDITOR:-nano}"
    
    echo -e "\n${HEADER_COLOR}编辑脚本: $script_name${NC}"
    echo -e "${MUTED_COLOR}路径: $full_path${NC}"
    echo -e "${MUTED_COLOR}编辑器: $editor${NC}\n"
    
    if confirm "使用 $editor 编辑文件？"; then
        "$editor" "$full_path"
        success "脚本编辑完成"
    fi
}

# 删除脚本
remove_script() {
    local script_name="$1"
    local script_type="$2"
    
    if confirm "${ERROR_COLOR}⚠ 警告：确定要删除脚本 '$script_name' 吗？${NC}"; then
        backup_config
        
        # 从配置中删除
        "$YQ" e "del(.scripts.$script_type[] | select(.name == \"$script_name\"))" -i "$CONFIG_FILE"
        
        if validate_config; then
            success "脚本 '$script_name' 已删除"
            
            if confirm "是否立即应用更改？"; then
                apply_changes
            fi
        else
            error "删除脚本失败"
            return 1
        fi
    else
        info "已取消删除操作"
    fi
}

# 显示脚本详情
show_script_detail() {
    local script_name="$1"
    local script_type="$2"
    
    section "📄 脚本详情: $script_name"
    
    # 修复：获取脚本信息
    local info_json
    info_json=$("$YQ" e ".scripts.$script_type[] | select(.name == \"$script_name\")" "$CONFIG_FILE" 2>/dev/null)
    
    if [[ -z "$info_json" ]]; then
        error "未找到脚本信息"
        return 1
    fi
    
    # 解析并显示信息
    local name enabled description path category aliases
    name=$(echo "$info_json" | "$YQ" e '.name' -)
    enabled=$(echo "$info_json" | "$YQ" e '.enabled' -)
    description=$(echo "$info_json" | "$YQ" e '.description' -)
    path=$(echo "$info_json" | "$YQ" e '.path' -)
    category=$(echo "$info_json" | "$YQ" e '.category // "未分类"' -)
    aliases=$(echo "$info_json" | "$YQ" e '.aliases[]?' - 2>/dev/null | tr '\n' ',' | sed 's/,$//')
    
    # 显示信息
    echo -e "  ${BLUE}▪${NC} 名称: ${HIGHLIGHT_COLOR}$name${NC}"
    echo -e "  ${BLUE}▪${NC} 状态: $([[ "$enabled" == "true" ]] && echo "${GREEN}已启用${NC}" || echo "${RED}已禁用${NC}")"
    echo -e "  ${BLUE}▪${NC} 描述: $description"
    echo -e "  ${BLUE}▪${NC} 路径: $path"
    echo -e "  ${BLUE}▪${NC} 分类: $category"
    [[ -n "$aliases" ]] && echo -e "  ${BLUE}▪${NC} 别名: $aliases"
    
    # 检查文件是否存在
    local full_path="${SCRIPT_DIR}/${script_type}/${path}"
    if [[ -f "$full_path" ]]; then
        echo -e "  ${BLUE}▪${NC} 文件状态: ${GREEN}存在${NC}"
        
        # 显示文件信息
        local size file_type
        size=$(du -h "$full_path" 2>/dev/null | cut -f1 || echo "未知")
        file_type=$(file -b "$full_path" 2>/dev/null || echo "未知")
        echo -e "  ${BLUE}▪${NC} 文件大小: $size"
        echo -e "  ${BLUE}▪${NC} 文件类型: $file_type"
    else
        echo -e "  ${BLUE}▪${NC} 文件状态: ${RED}不存在${NC}"
    fi
}

# 管理特定类型的脚本
manage_scripts_of_type() {
    local script_type="$1"
    local type_display
    [[ "$script_type" == "startup" ]] && type_display="🚀 启动脚本" || type_display="🛠️  工具脚本"
    
    while true; do
        clear
        show_banner
        
        echo -e "${HEADER_COLOR}$type_display 管理${NC}"
        
        # 显示脚本列表
        local idx=1
        declare -A scripts
        
        # 修复：使用正确的yq查询语法获取脚本列表
        local script_list
        if [[ "$script_type" == "startup" ]]; then
            script_list=$("$YQ" e '.scripts.startup[] | [.name, .enabled, .description] | join(":")' "$CONFIG_FILE" 2>/dev/null || true)
        else
            script_list=$("$YQ" e '.scripts.tools[] | [.name, .enabled, .description] | join(":")' "$CONFIG_FILE" 2>/dev/null || true)
        fi
        
        if [[ -z "$script_list" ]]; then
            echo -e "  ${MUTED_COLOR}没有找到任何脚本${NC}"
        else
            while IFS=':' read -r name enabled description; do
                [[ -z "$name" ]] && continue
                local status
                [[ "$enabled" == "true" ]] && status="${GREEN}✓${NC}" || status="${RED}✗${NC}"
                echo -e "  ${BLUE}$idx${NC}. $status $name: $description"
                scripts["$idx"]="$name"
                idx=$((idx + 1))
            done <<< "$script_list"
        fi
        
        echo -e "\n${HEADER_COLOR}操作:${NC}"
        echo -e "  ${BLUE}s${NC}. 选择脚本"
        echo -e "  ${BLUE}r${NC}. 刷新"
        echo -e "  ${MUTED_COLOR}0. 返回${NC}"
        
        read -p "$(echo -e "\n${YELLOW}请选择: ${NC}")" -r choice
        
        case "$choice" in
            [sS])
                local script_name
                if [[ "$FZF_ENABLED" == "true" ]]; then
                    script_name=$(select_script_fzf "$script_type")
                else
                    script_name=$(select_script_simple "$script_type")
                fi
                
                [[ -n "$script_name" ]] && manage_single_script "$script_name" "$script_type"
                ;;
            [rR])
                continue
                ;;
            0)
                break
                ;;
            [1-9]|[1-9][0-9]*)
                if [[ -n "${scripts[$choice]}" ]]; then
                    manage_single_script "${scripts[$choice]}" "$script_type"
                else
                    error "无效选择"
                    pause
                fi
                ;;
            *)
                error "无效选择"
                pause
                ;;
        esac
    done
}

# 管理单个脚本
manage_single_script() {
    local script_name="$1"
    local script_type="$2"
    
    while true; do
        clear
        show_banner
        
        # 显示脚本详情
        show_script_detail "$script_name" "$script_type"
        
        echo -e "\n${HEADER_COLOR}操作:${NC}"
        echo -e "  ${BLUE}1.${NC} 🔄 切换启用状态"
        echo -e "  ${BLUE}2.${NC} 📝 编辑脚本"
        echo -e "  ${BLUE}3.${NC} ✏️  编辑配置"
        echo -e "  ${BLUE}4.${NC} 🗑️  删除脚本"
        echo -e "  ${BLUE}5.${NC} 🔄 应用更改"
        echo -e "  ${MUTED_COLOR}0. 返回${NC}"
        
        read -p "$(echo -e "\n${YELLOW}请选择: ${NC}")" -r choice
        
        case "$choice" in
            1) 
                if toggle_script "$script_name" "$script_type"; then
                    pause
                fi
                ;;
            2) 
                edit_script "$script_name" "$script_type"
                pause
                ;;
            3) 
                edit_config_file
                pause
                ;;
            4) 
                remove_script "$script_name" "$script_type"
                break
                ;;
            5) 
                apply_changes
                pause
                ;;
            0) 
                break
                ;;
            *) 
                error "无效选择"
                pause
                ;;
        esac
    done
}

# 编辑配置文件
edit_config_file() {
    section "📝 编辑配置文件"
    
    local editor="${EDITOR:-nano}"
    echo -e "${MUTED_COLOR}配置文件: $CONFIG_FILE${NC}"
    echo -e "${MUTED_COLOR}编辑器: $editor${NC}\n"
    
    if confirm "编辑配置文件？"; then
        backup_config
        "$editor" "$CONFIG_FILE"
        
        if validate_config; then
            success "配置文件验证成功"
            
            if confirm "是否应用更改？"; then
                apply_changes
            fi
        else
            error "配置文件格式错误，请检查 YAML 语法"
        fi
    fi
}

# 修复权限
fix_permissions() {
    section "🔧 修复权限"
    
    echo -e "正在修复文件权限..."
    
    # 修复脚本执行权限
    find "$SCRIPT_DIR" -name "*.sh" -type f -exec chmod +x {} \; 2>/dev/null
    
    # 修复 yq
    if [[ -f "$YQ" ]]; then
        chmod +x "$YQ"
    fi
    
    # 修复 bin 目录中的软链接
    if [[ -d "$BIN_DIR" ]]; then
        find "$BIN_DIR" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null
    fi
    
    success "权限修复完成！"
    pause
}

# 导出配置
export_config() {
    section "📤 导出配置"
    
    local export_dir="${SCRIPT_DIR}/exports"
    mkdir -p "$export_dir"
    
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local export_path="${export_dir}/scripts_export_${timestamp}.yaml"
    
    cp "$CONFIG_FILE" "$export_path"
    
    if [[ $? -eq 0 ]]; then
        success "配置已导出到: $export_path"
    else
        error "导出配置失败"
    fi
    
    pause
}

# 导入配置
import_config() {
    section "📥 导入配置"
    
    echo -e "${WARNING_COLOR}警告: 导入配置将覆盖当前配置！${NC}"
    
    if confirm "是否继续？"; then
        local import_dir="${SCRIPT_DIR}/exports"
        mkdir -p "$import_dir"
        
        echo -e "\n可用的配置文件:"
        local idx=1
        declare -A configs
        
        for file in "$import_dir"/*.yaml "$import_dir"/*.yml; do
            [[ -f "$file" ]] || continue
            echo -e "  ${BLUE}$idx${NC}. $(basename "$file")"
            configs["$idx"]="$file"
            idx=$((idx + 1))
        done
        
        if [[ $idx -eq 1 ]]; then
            error "没有找到配置文件"
            pause
            return
        fi
        
        echo -e "  ${MUTED_COLOR}0. 取消${NC}"
        
        read -p "$(echo -e "\n${YELLOW}请选择配置文件: ${NC}")" -r choice
        
        if [[ "$choice" == "0" ]]; then
            return
        elif [[ -n "${configs[$choice]}" ]]; then
            local selected_config="${configs[$choice]}"
            
            # 备份当前配置
            backup_config
            
            # 导入配置
            if cp "$selected_config" "$CONFIG_FILE" && validate_config; then
                success "配置导入成功！"
                
                if confirm "是否立即应用更改？"; then
                    apply_changes
                fi
            else
                error "导入的配置文件格式错误"
            fi
        else
            error "无效选择"
        fi
    fi
    
    pause
}

# 脚本管理菜单
script_management_menu() {
    while true; do
        clear
        show_banner
        
        echo -e "${HEADER_COLOR}📁 脚本管理${NC}"
        echo -e "  ${BLUE}1.${NC} 🚀 管理启动脚本"
        echo -e "  ${BLUE}2.${NC} 🛠️  管理工具脚本"
        echo -e "  ${BLUE}3.${NC} ➕ 添加新脚本"
        echo -e "  ${BLUE}4.${NC} 🔄 应用更改"
        echo -e "  ${BLUE}5.${NC} 📊 查看状态"
        echo -e "  ${BLUE}0.${NC} ↩️  返回主菜单"
        
        read -p "$(echo -e "\n${YELLOW}请选择: ${NC}")" -r choice
        
        case "$choice" in
            1) manage_scripts_of_type "startup" ;;
            2) manage_scripts_of_type "tools" ;;
            3) add_new_script ;;
            4) apply_changes; pause ;;
            5) show_status; pause ;;
            0) break ;;
            *) error "无效选择"; pause ;;
        esac
    done
}

# 设置菜单
settings_menu() {
    while true; do
        clear
        show_banner
        
        echo -e "${HEADER_COLOR}⚙️  设置${NC}"
        
        # 获取当前设置
        local auto_apply=$(get_config '.settings.auto_apply')
        local fzf_ui=$(get_config '.settings.enable_fzf_ui')
        
        echo -e "  ${BLUE}1.${NC} 自动应用更改: $([[ "$auto_apply" == "true" ]] && echo "${GREEN}启用${NC}" || echo "${RED}禁用${NC}")"
        echo -e "  ${BLUE}2.${NC} FZF 交互界面: $([[ "$fzf_ui" == "true" ]] && echo "${GREEN}启用${NC}" || echo "${RED}禁用${NC}")"
        echo -e "  ${BLUE}3.${NC} 📁 打开项目目录"
        echo -e "  ${BLUE}4.${NC} 🔧 修复权限"
        echo -e "  ${BLUE}5.${NC} 📤 导出配置"
        echo -e "  ${BLUE}6.${NC} 📥 导入配置"
        echo -e "  ${MUTED_COLOR}0. 返回${NC}"
        
        read -p "$(echo -e "\n${YELLOW}请选择: ${NC}")" -r choice
        
        case "$choice" in
            1)
                if [[ "$auto_apply" == "true" ]]; then
                    "$YQ" e '.settings.auto_apply = false' -i "$CONFIG_FILE"
                    success "已禁用自动应用更改"
                else
                    "$YQ" e '.settings.auto_apply = true' -i "$CONFIG_FILE"
                    success "已启用自动应用更改"
                fi
                pause
                ;;
            2)
                if [[ "$fzf_ui" == "true" ]]; then
                    "$YQ" e '.settings.enable_fzf_ui = false' -i "$CONFIG_FILE"
                    FZF_ENABLED=false
                    success "已禁用 FZF 交互界面"
                else
                    "$YQ" e '.settings.enable_fzf_ui = true' -i "$CONFIG_FILE"
                    FZF_ENABLED=true
                    success "已启用 FZF 交互界面"
                fi
                pause
                ;;
            3)
                if [[ -d "$SCRIPT_DIR" ]]; then
                    if command -v xdg-open &> /dev/null; then
                        xdg-open "$SCRIPT_DIR" 2>/dev/null || true
                    elif command -v open &> /dev/null; then
                        open "$SCRIPT_DIR" 2>/dev/null || true
                    fi
                    echo -e "${GREEN}✓${NC} 已尝试打开项目目录"
                else
                    error "项目目录不存在: $SCRIPT_DIR"
                fi
                pause
                ;;
            4)
                fix_permissions
                ;;
            5)
                export_config
                ;;
            6)
                import_config
                ;;
            0)
                break
                ;;
            *)
                error "无效选择"
                pause
                ;;
        esac
    done
}

# 主菜单
main_menu() {
    while true; do
        clear
        show_banner
        show_status
        
        echo -e "\n${HEADER_COLOR}📋 主菜单${NC}"
        echo -e "  ${GREEN}1.${NC} 📁 管理脚本"
        echo -e "  ${BLUE}2.${NC} 🔄 应用更改"
        echo -e "  ${YELLOW}3.${NC} ⚙️  设置"
        echo -e "  ${PURPLE}4.${NC} 📝 编辑配置"
        echo -e "  ${CYAN}5.${NC} 🔧 修复权限"
        echo -e "  ${RED}6.${NC} 🚪 退出"
        
        read -p "$(echo -e "\n${YELLOW}请选择: ${NC}")" -r choice
        
        case "$choice" in
            1) script_management_menu ;;
            2) apply_changes; pause ;;
            3) settings_menu ;;
            4) edit_config_file; pause ;;
            5) fix_permissions; pause ;;
            6) 
                echo -e "\n${SUCCESS_COLOR}感谢使用 Bash Scripts Manager！${NC}"
                echo -e "${MUTED_COLOR}再见！👋${NC}\n"
                exit 0
                ;;
            *) 
                error "无效选择"
                pause
                ;;
        esac
    done
}

# 初始化检查
init_check() {
    # 检查必需文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi
    
    if [[ ! -x "$YQ" ]]; then
        error "yq 工具未找到或不可执行: $YQ"
        error "请确保 yq 二进制文件存在于 bin 目录中"
        exit 1
    fi
    
    if ! validate_config; then
        error "配置文件格式错误，请检查 YAML 语法"
        exit 1
    fi
    
    # 检查 fzf
    check_fzf
    
    # 创建必要目录
    mkdir -p "$BACKUP_DIR" "${SCRIPT_DIR}/exports" 2>/dev/null || true
    
    # 设置 FZF_ENABLED
    FZF_ENABLED=$(get_config '.settings.enable_fzf_ui')
    if [[ "$FZF_ENABLED" != "true" ]]; then
        FZF_ENABLED=false
    fi
}

# 主函数
main() {
    # 初始化检查
    init_check
    
    # 显示欢迎信息
    show_banner
    
    # 检查是否需要立即应用
    if [[ "$(get_config '.settings.auto_apply')" == "true" ]] && confirm "自动应用已启用，是否立即应用当前配置？"; then
        apply_changes
        pause
    fi
    
    # 进入主菜单
    main_menu
}

# 程序入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'echo -e "\n${ERROR_COLOR}操作被用户中断${NC}"; exit 130' INT
    main "$@"
fi
