#!/bin/bash
# Bash Scripts Manager - 极简专业版 v2.2
# 极客风格，简洁高效

set -eo pipefail

# ============================================
# 配置和路径
# ============================================

# 获取脚本真实路径
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}" 2> /dev/null || echo "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"
CONFIG_FILE="${SCRIPT_DIR}/scripts.yaml"
BACKUP_DIR="${SCRIPT_DIR}/backups"
BIN_DIR="${SCRIPT_DIR}/bin"
INIT_SCRIPT="${SCRIPT_DIR}/init.sh"
YQ="${BIN_DIR}/yq"
FZF_ENABLED=true
BASHRC="${HOME}/.bashrc"

# 编辑器优先级
if command -v nvim &> /dev/null; then
    DEFAULT_EDITOR="nvim"
elif command -v vim &> /dev/null; then
    DEFAULT_EDITOR="vim"
else
    DEFAULT_EDITOR="nano"
fi

# 分页配置
PAGE_SIZE=10
CURRENT_PAGE=1

# 状态历史，用于撤销
LAST_STATUS_CHANGE=""

# ============================================
# 极客风格颜色定义
# ============================================

# 主色调 - 深色背景亮色文字
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;37m'
DARK_GRAY='\033[1;30m'
NC='\033[0m'

# 主题颜色
TITLE_COLOR="${CYAN}${BOLD}"
HEADER_COLOR="${WHITE}"
SUCCESS_COLOR="${GREEN}"
WARNING_COLOR="${YELLOW}"
ERROR_COLOR="${RED}"
HIGHLIGHT_COLOR="${CYAN}"
MUTED_COLOR="${DARK_GRAY}"
ACCENT_COLOR="${PURPLE}"

# 样式
BOLD='\033[1m'
DIM='\033[2m'
INVERT='\033[7m'

# ============================================
# 工具函数
# ============================================

# 极简日志输出
log_info() { echo -e "${CYAN}▶${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# 带确认的提示
confirm() {
    local prompt="$1"
    local default="${2:-n}"

    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n]: "
    else
        prompt="$prompt [y/N]: "
    fi

    read -p "$(echo -e "${YELLOW}$prompt${NC}")" -r response
    response="${response:-$default}"

    [[ "$response" =~ ^[Yy]$ ]]
}

# 等待用户按键
pause() {
    echo -e "${MUTED_COLOR}↵ 继续${NC}"
    read -n1 -s
}

# 检查命令
check_command() { command -v "$1" &> /dev/null; }

# 检查 yq
check_yq() {
    if [[ ! -x "$YQ" ]]; then
        log_error "yq 未找到: $YQ"
        return 1
    fi
}

# 验证配置
validate_config() {
    "$YQ" e '.' "$CONFIG_FILE" > /dev/null 2>&1
}

# 获取配置值
get_config() {
    local key="$1"
    "$YQ" e "$key" "$CONFIG_FILE" 2> /dev/null
}

# 绘制分隔线
hline() {
    local width="${1:-50}"
    printf "${MUTED_COLOR}%${width}s${NC}\n" | tr ' ' '─'
}

# 显示标题
show_title() {
    clear
    echo -e "${TITLE_COLOR}"
    cat << "EOF"
╔═══════════════════════════════════════════╗
║  ██████╗ █████╗  ███████╗██╗  ██╗         ║
║  ██╔══██╗██╔══██╗██╔════╝██║  ██║         ║
║  ██████╔╝███████║███████╗███████║         ║
║  ██╔══██╗██╔══██║╚════██║██╔══██║         ║
║  ██████╔╝██║  ██║███████║██║  ██║         ║
║  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝         ║
║                                           ║
║  S C R I P T S   M A N A G E R   v2.2     ║
╚═══════════════════════════════════════════╝
EOF
    echo -e "${NC}"
    hline
    echo -e "${MUTED_COLOR}$(date +'%Y-%m-%d %H:%M:%S')${NC} ${MUTED_COLOR}|${NC} ${MUTED_COLOR}$(pwd)${NC}"
    hline
    echo
}

# 显示状态摘要
show_status_summary() {
    local startup_count=0 startup_enabled=0
    local tools_count=0 tools_enabled=0

    # 统计启动脚本
    local startup_scripts
    startup_scripts=$("$YQ" e '.scripts.startup[] | [.name, .enabled] | join(":")' "$CONFIG_FILE" 2> /dev/null || true)
    if [[ -n "$startup_scripts" ]]; then
        while IFS=':' read -r name enabled; do
            [[ -z "$name" ]] && continue
            startup_count=$((startup_count + 1))
            [[ "$enabled" == "true" ]] && startup_enabled=$((startup_enabled + 1))
        done <<< "$startup_scripts"
    fi

    # 统计工具脚本
    local tools_scripts
    tools_scripts=$("$YQ" e '.scripts.tools[] | [.name, .enabled] | join(":")' "$CONFIG_FILE" 2> /dev/null || true)
    if [[ -n "$tools_scripts" ]]; then
        while IFS=':' read -r name enabled; do
            [[ -z "$name" ]] && continue
            tools_count=$((tools_count + 1))
            [[ "$enabled" == "true" ]] && tools_enabled=$((tools_enabled + 1))
        done <<< "$tools_scripts"
    fi

    echo -e "${HEADER_COLOR}📊 状态摘要${NC}"
    echo -e "  ${CYAN}┌─────────────────────┬────────────────┐${NC}"
    echo -e "  ${CYAN}│ 类型                │ 状态           │${NC}"
    echo -e "  ${CYAN}├─────────────────────┼────────────────┤${NC}"
    echo -e "  ${CYAN}│ 启动脚本            │ ${startup_enabled}/${startup_count}\t\t │${NC}"
    echo -e "  ${CYAN}│ 工具脚本            │ ${tools_enabled}/${tools_count}\t\t │${NC}"
    echo -e "  ${CYAN}└─────────────────────┴────────────────┘${NC}"
    echo
}

# 获取所有脚本（统一编号）
get_all_scripts() {
    # 清空全局数组
    ALL_SCRIPTS=()
    SCRIPT_MAP=()

    local idx=1

    # 获取启动脚本
    local startup_scripts
    startup_scripts=$("$YQ" e '.scripts.startup[] | [.name, .enabled, .description, "startup"] | join(":")' "$CONFIG_FILE" 2> /dev/null || true)

    if [[ -n "$startup_scripts" ]]; then
        while IFS=':' read -r name enabled description script_type; do
            [[ -z "$name" ]] && continue
            ALL_SCRIPTS+=("$idx:$name:$enabled:$description:$script_type")
            idx=$((idx + 1))
        done <<< "$startup_scripts"
    fi

    # 获取工具脚本
    local tools_scripts
    tools_scripts=$("$YQ" e '.scripts.tools[] | [.name, .enabled, .description, "tools"] | join(":")' "$CONFIG_FILE" 2> /dev/null || true)

    if [[ -n "$tools_scripts" ]]; then
        while IFS=':' read -r name enabled description script_type; do
            [[ -z "$name" ]] && continue
            ALL_SCRIPTS+=("$idx:$name:$enabled:$description:$script_type")
            idx=$((idx + 1))
        done <<< "$tools_scripts"
    fi

    TOTAL_SCRIPTS=${#ALL_SCRIPTS[@]}
}

# 显示分页脚本列表
display_paginated_scripts() {
    local page="$1"
    local page_size="$2"

    # 计算起始和结束索引
    local start_idx=$(((page - 1) * page_size + 1))
    local end_idx=$((page * page_size))

    # 确保不超过总数
    if [[ $end_idx -gt $TOTAL_SCRIPTS ]]; then
        end_idx=$TOTAL_SCRIPTS
    fi

    # 计算总页数
    local total_pages=$(((TOTAL_SCRIPTS + page_size - 1) / page_size))

    # 显示分页信息
    echo -e "${MUTED_COLOR}页面: $page/$total_pages | 脚本: $start_idx-$end_idx/$TOTAL_SCRIPTS${NC}"
    hline
    echo

    # 显示当前页的脚本
    for ((i = start_idx; i <= end_idx; i++)); do
        local idx=$i
        local script_info="${ALL_SCRIPTS[$((i - 1))]}"

        IFS=':' read -r global_idx name enabled description script_type <<< "$script_info"

        # 确定图标和颜色
        local type_icon
        local type_color
        if [[ "$script_type" == "startup" ]]; then
            type_icon="🚀"
            type_color="${CYAN}"
        else
            type_icon="🛠️"
            type_color="${BLUE}"
        fi

        local status_icon
        [[ "$enabled" == "true" ]] && status_icon="${GREEN}●${NC}" || status_icon="${RED}○${NC}"

        # 显示脚本
        echo -e "  ${type_color}[${global_idx}]${NC} $type_icon $status_icon ${WHITE}${name}${NC}"
        echo -e "      ${MUTED_COLOR}${description}${NC}"
        echo
    done

    # 显示分页导航
    if [[ $total_pages -gt 1 ]]; then
        hline
        echo -e "${MUTED_COLOR}导航: n下一页, p上一页, g[数字]跳转${NC}"
    fi

    # 显示上次操作结果
    if [[ -n "$LAST_STATUS_CHANGE" ]]; then
        echo -e "${MUTED_COLOR}上次操作: $LAST_STATUS_CHANGE${NC}"
    fi
}

# 应用更改
apply_changes() {
    echo
    hline
    echo -e "${HEADER_COLOR}🔄 应用更改${NC}"
    hline

    if [[ ! -x "$INIT_SCRIPT" ]]; then
        log_error "初始化脚本不可执行"
        return 1
    fi

    echo -e "正在应用配置更改..."

    # 执行初始化脚本
    if bash "$INIT_SCRIPT"; then
        log_success "配置已应用"
        echo -e "${MUTED_COLOR}运行 'source ~/.bashrc' 使更改生效${NC}"
        LAST_STATUS_CHANGE="" # 清空上次操作记录
        return 0
    else
        log_error "应用更改失败"
        return 1
    fi
}

# 主菜单 - 统一脚本管理
main_menu() {
    while true; do
        show_title
        show_status_summary

        echo -e "${HEADER_COLOR}📋 主菜单${NC}"
        echo -e "  ${GREEN}1.${NC} 管理所有脚本"
        echo -e "  ${BLUE}2.${NC} 添加新脚本"
        echo -e "  ${PURPLE}3.${NC} 应用更改"
        echo -e "  ${YELLOW}4.${NC} 编辑配置"
        echo -e "  ${CYAN}5.${NC} 系统设置"
        echo -e "  ${RED}0.${NC} 退出"
        echo
        hline

        read -p "$(echo -e "${YELLOW}选择操作 [0-5]: ${NC}")" -r choice

        case "$choice" in
            1) manage_all_scripts ;;
            2) add_new_script ;;
            3)
                apply_changes
                pause
                ;;
            4) edit_config_file ;;
            5) system_settings ;;
            0)
                echo
                echo -e "${MUTED_COLOR}再见！ 🖖${NC}"
                echo
                exit 0
                ;;
            *)
                log_error "无效选择"
                pause
                ;;
        esac
    done
}

# 管理所有脚本（统一界面）
manage_all_scripts() {
    # 重置到第一页
    CURRENT_PAGE=1

    while true; do
        show_title

        echo -e "${HEADER_COLOR}🛠️  脚本管理${NC}"
        echo -e "${MUTED_COLOR}使用数字选择脚本，t切换状态，e编辑，d删除，q返回${NC}"

        # 获取所有脚本
        get_all_scripts

        if [[ $TOTAL_SCRIPTS -eq 0 ]]; then
            hline
            echo -e "${MUTED_COLOR}暂无脚本${NC}"
            hline
            echo -e "${MUTED_COLOR}按任意键返回${NC}"
            read -n1 -s
            return
        fi

        # 显示当前页
        display_paginated_scripts "$CURRENT_PAGE" "$PAGE_SIZE"

        hline
        echo -e "${MUTED_COLOR}输入: 数字+操作键 (如: 1t, 2e, 3d)${NC}"
        echo -e "${MUTED_COLOR}      n下一页, p上一页, g[页数]跳转, q返回${NC}"
        echo -e "${MUTED_COLOR}      u撤销上次状态切换${NC}"
        hline

        read -p "$(echo -e "${YELLOW}操作: ${NC}")" -r input

        if [[ "$input" == "q" ]]; then
            return
        fi

        # 处理撤销命令
        if [[ "$input" == "u" ]] && [[ -n "$LAST_STATUS_CHANGE" ]]; then
            undo_last_status_change
            continue
        fi

        # 处理翻页命令
        if [[ "$input" == "n" ]]; then
            local total_pages=$(((TOTAL_SCRIPTS + PAGE_SIZE - 1) / PAGE_SIZE))
            if [[ $CURRENT_PAGE -lt $total_pages ]]; then
                CURRENT_PAGE=$((CURRENT_PAGE + 1))
            fi
            continue
        elif [[ "$input" == "p" ]]; then
            if [[ $CURRENT_PAGE -gt 1 ]]; then
                CURRENT_PAGE=$((CURRENT_PAGE - 1))
            fi
            continue
        elif [[ "$input" =~ ^g([0-9]+)$ ]]; then
            local target_page="${BASH_REMATCH[1]}"
            local total_pages=$(((TOTAL_SCRIPTS + PAGE_SIZE - 1) / PAGE_SIZE))
            if [[ $target_page -ge 1 ]] && [[ $target_page -le $total_pages ]]; then
                CURRENT_PAGE=$target_page
            else
                log_error "无效页码: $target_page (1-$total_pages)"
                pause
            fi
            continue
        fi

        # 处理脚本操作命令
        if [[ "$input" =~ ^([0-9]+)([ted])$ ]]; then
            local script_num="${BASH_REMATCH[1]}"
            local action="${BASH_REMATCH[2]}"

            # 验证脚本编号
            if [[ $script_num -lt 1 ]] || [[ $script_num -gt $TOTAL_SCRIPTS ]]; then
                log_error "无效脚本编号: $script_num (1-$TOTAL_SCRIPTS)"
                pause
                continue
            fi

            # 获取脚本信息
            local script_info="${ALL_SCRIPTS[$((script_num - 1))]}"
            IFS=':' read -r global_idx script_name enabled description script_type <<< "$script_info"

            case "$action" in
                t) toggle_script_status "$script_name" "$script_type" ;;
                e) edit_script_file "$script_name" "$script_type" ;;
                d) delete_script "$script_name" "$script_type" ;;
            esac
        else
            log_error "格式错误: 使用 数字+操作键 (如: 1t) 或 n/p/g/q/u"
            pause
        fi
    done
}

# 切换脚本状态（直接切换，无需确认）
toggle_script_status() {
    local script_name="$1"
    local script_type="$2"

    # 获取当前状态
    local current_status
    current_status=$("$YQ" e ".scripts.$script_type[] | select(.name == \"$script_name\") | .enabled" "$CONFIG_FILE" 2> /dev/null)

    if [[ -z "$current_status" ]]; then
        log_error "脚本未找到"
        return 1
    fi

    local new_status
    local action_desc

    if [[ "$current_status" == "true" ]]; then
        new_status=false
        action_desc="禁用"
    else
        new_status=true
        action_desc="启用"
    fi

    # 保存状态历史以便撤销
    LAST_STATUS_CHANGE="$script_name: $([[ "$current_status" == "true" ]] && echo "启用→禁用" || echo "禁用→启用")"

    # 直接修改状态
    "$YQ" e "(.scripts.$script_type[] | select(.name == \"$script_name\") | .enabled) = $new_status" -i "$CONFIG_FILE"

    if validate_config; then
        log_success "已${action_desc}: $script_name"

        # 如果启用了自动应用，则立即应用
        if [[ "$(get_config '.settings.auto_apply')" == "true" ]]; then
            if apply_changes; then
                echo -e "${GREEN}✓${NC} 更改已自动应用"
            fi
        else
            echo -e "${MUTED_COLOR}提示: 使用'u'撤销此次操作，或主菜单中选择'应用更改'${NC}"
        fi
    else
        log_error "状态切换失败"
        return 1
    fi

    pause
}

# 撤销上次状态切换
undo_last_status_change() {
    if [[ -z "$LAST_STATUS_CHANGE" ]]; then
        log_error "没有可撤销的操作"
        return
    fi

    # 解析上次操作
    if [[ "$LAST_STATUS_CHANGE" =~ ^([^:]+):\ (.+)$ ]]; then
        local script_name="${BASH_REMATCH[1]}"
        local change="${BASH_REMATCH[2]}"

        # 查找脚本类型
        local script_type
        if "$YQ" e ".scripts.startup[] | select(.name == \"$script_name\")" "$CONFIG_FILE" > /dev/null 2>&1; then
            script_type="startup"
        elif "$YQ" e ".scripts.tools[] | select(.name == \"$script_name\")" "$CONFIG_FILE" > /dev/null 2>&1; then
            script_type="tools"
        else
            log_error "找不到脚本: $script_name"
            return
        fi

        # 获取当前状态
        local current_status
        current_status=$("$YQ" e ".scripts.$script_type[] | select(.name == \"$script_name\") | .enabled" "$CONFIG_FILE" 2> /dev/null)

        if [[ -z "$current_status" ]]; then
            log_error "获取当前状态失败"
            return
        fi

        # 撤销到相反状态
        local new_status
        if [[ "$current_status" == "true" ]]; then
            new_status=false
        else
            new_status=true
        fi

        "$YQ" e "(.scripts.$script_type[] | select(.name == \"$script_name\") | .enabled) = $new_status" -i "$CONFIG_FILE"

        if validate_config; then
            log_success "已撤销: $script_name 状态回滚"
            LAST_STATUS_CHANGE=""

            # 如果启用了自动应用，则立即应用
            if [[ "$(get_config '.settings.auto_apply')" == "true" ]]; then
                apply_changes
            fi
        else
            log_error "撤销失败"
        fi
    else
        log_error "无法解析上次操作记录"
    fi
}

# 编辑脚本文件
edit_script_file() {
    local script_name="$1"
    local script_type="$2"

    # 获取脚本路径
    local script_path
    script_path=$("$YQ" e ".scripts.$script_type[] | select(.name == \"$script_name\") | .path" "$CONFIG_FILE" 2> /dev/null)

    if [[ -z "$script_path" ]]; then
        log_error "未找到脚本路径"
        return 1
    fi

    # 构建完整路径
    local full_path="${SCRIPT_DIR}/${script_type}/${script_path}"

    if [[ ! -f "$full_path" ]]; then
        log_error "文件不存在: $full_path"
        return 1
    fi

    echo
    hline
    echo -e "${HEADER_COLOR}📝 编辑脚本${NC}"
    hline
    echo -e "脚本: ${WHITE}$script_name${NC}"
    echo -e "路径: ${MUTED_COLOR}$full_path${NC}"
    echo -e "编辑器: ${MUTED_COLOR}$DEFAULT_EDITOR${NC}"

    if confirm "使用 $DEFAULT_EDITOR 编辑？"; then
        "$DEFAULT_EDITOR" "$full_path"
        log_success "编辑完成"
    fi
}

# 删除脚本
delete_script() {
    local script_name="$1"
    local script_type="$2"

    echo
    hline
    echo -e "${ERROR_COLOR}⚠ 删除脚本${NC}"
    hline

    echo -e "脚本: ${WHITE}$script_name${NC}"
    echo -e "类型: ${MUTED_COLOR}$script_type${NC}"
    echo

    if confirm "${ERROR_COLOR}确认删除？此操作不可逆。${NC}"; then
        # 从配置中删除
        "$YQ" e "del(.scripts.$script_type[] | select(.name == \"$script_name\"))" -i "$CONFIG_FILE"

        if validate_config; then
            log_success "已删除: $script_name"

            if confirm "立即应用更改？"; then
                apply_changes
            fi
        else
            log_error "删除失败"
        fi
    else
        log_info "已取消"
    fi
}

# 添加新脚本（通过fzf选择文件）
add_new_script() {
    while true; do
        show_title

        echo -e "${HEADER_COLOR}➕ 添加新脚本${NC}"
        hline

        echo -e "${MUTED_COLOR}步骤 1/3: 选择脚本类型${NC}"
        echo -e "  ${GREEN}1.${NC} 启动脚本 (随终端启动)"
        echo -e "  ${BLUE}2.${NC} 工具脚本 (手动调用)"
        echo -e "  ${MUTED_COLOR}0. 返回${NC}"

        hline
        read -p "$(echo -e "${YELLOW}选择类型: ${NC}")" -r type_choice

        case "$type_choice" in
            1) script_type="startup" ;;
            2) script_type="tools" ;;
            0) return ;;
            *)
                log_error "无效选择"
                pause
                continue
                ;;
        esac

        # 步骤2: 选择文件
        echo
        echo -e "${MUTED_COLOR}步骤 2/3: 选择脚本文件${NC}"

        local script_dir="${SCRIPT_DIR}/${script_type}"
        if [[ ! -d "$script_dir" ]]; then
            log_error "目录不存在: $script_dir"
            pause
            continue
        fi

        # 使用fzf选择文件
        local selected_file
        if [[ "$FZF_ENABLED" == "true" ]] && check_command fzf; then
            selected_file=$(find "$script_dir" -name "*.sh" -type f 2> /dev/null |
                fzf --height=40% --border=rounded \
                    --prompt="🔍 选择脚本文件: " \
                    --header="使用 ↑↓ 键导航, Enter 选择, ESC 取消" \
                    --preview="echo '文件预览:'; echo ''; head -20 {}" \
                    --preview-window=right:60%:wrap \
                    --color=bg+:#2e3440,bg:#2e3440,spinner:#81a1c1,hl:#88c0d0 \
                    --color=fg:#d8dee9,header:#88c0d0,info:#5e81ac,pointer:#81a1c1 \
                    --color=marker:#81a1c1,fg+:#eceff4,prompt:#5e81ac,hl+:#88c0d0)
        else
            # 简单列表
            echo -e "可用的脚本文件:"
            local files=()
            while IFS= read -r -d $'\0' file; do
                files+=("$file")
                echo -e "  ${BLUE}[${#files[@]}]${NC} $(basename "$file")"
            done < <(find "$script_dir" -name "*.sh" -type f -print0 2> /dev/null)

            if [[ ${#files[@]} -eq 0 ]]; then
                log_error "未找到脚本文件"
                pause
                continue
            fi

            echo -e "  ${MUTED_COLOR}0. 返回${NC}"
            read -p "$(echo -e "${YELLOW}选择文件: ${NC}")" -r file_choice

            if [[ "$file_choice" == "0" ]]; then
                continue
            fi

            if [[ "$file_choice" =~ ^[0-9]+$ ]] && [[ "$file_choice" -le ${#files[@]} ]]; then
                selected_file="${files[$((file_choice - 1))]}"
            else
                log_error "无效选择"
                pause
                continue
            fi
        fi

        if [[ -z "$selected_file" ]]; then
            log_info "已取消"
            pause
            continue
        fi

        # 获取相对路径
        local relative_path="${selected_file#$script_dir/}"

        # 步骤3: 输入信息
        echo
        echo -e "${MUTED_COLOR}步骤 3/3: 输入脚本信息${NC}"

        local name description category enabled aliases_str

        # 自动生成名称（从文件名）
        local auto_name="$(basename "$selected_file" .sh)"
        read -p "$(echo -e "${YELLOW}脚本名称 [${auto_name}]: ${NC}")" -r name
        name="${name:-$auto_name}"

        read -p "$(echo -e "${YELLOW}脚本描述: ${NC}")" -r description

        if [[ "$script_type" == "tools" ]]; then
            read -p "$(echo -e "${YELLOW}别名 (逗号分隔): ${NC}")" -r aliases_str
        fi

        read -p "$(echo -e "${YELLOW}分类: ${NC}")" -r category

        if confirm "启用此脚本？"; then
            enabled=true
        else
            enabled=false
        fi

        # 添加到配置
        if [[ "$script_type" == "tools" ]]; then
            # 处理别名
            IFS=',' read -ra aliases_array <<< "$aliases_str"
            local aliases_json="["
            for alias in "${aliases_array[@]}"; do
                alias=$(echo "$alias" | xargs)
                [[ -n "$alias" ]] && aliases_json+="\"$alias\","
            done
            aliases_json="${aliases_json%,}]"
            [[ "$aliases_json" == "]" ]] && aliases_json="[]"

            "$YQ" e ".scripts.$script_type += {
                \"name\": \"$name\",
                \"description\": \"$description\",
                \"path\": \"$relative_path\",
                \"enabled\": $enabled,
                \"category\": \"$category\",
                \"aliases\": $aliases_json
            }" -i "$CONFIG_FILE"
        else
            "$YQ" e ".scripts.$script_type += {
                \"name\": \"$name\",
                \"description\": \"$description\",
                \"path\": \"$relative_path\",
                \"enabled\": $enabled,
                \"category\": \"$category\"
            }" -i "$CONFIG_FILE"
        fi

        if validate_config; then
            log_success "脚本 '$name' 已添加"

            if [[ "$enabled" == "true" ]] && confirm "立即应用更改？"; then
                apply_changes
            fi
        else
            log_error "添加失败，配置格式错误"
        fi

        pause
        break
    done
}

# 编辑配置文件
edit_config_file() {
    echo
    hline
    echo -e "${HEADER_COLOR}⚙️  编辑配置${NC}"
    hline

    echo -e "文件: ${MUTED_COLOR}$CONFIG_FILE${NC}"
    echo -e "编辑器: ${MUTED_COLOR}$DEFAULT_EDITOR${NC}"

    if confirm "打开编辑器？"; then
        # 备份
        local timestamp=$(date +"%Y%m%d_%H%M%S")
        local backup_path="${BACKUP_DIR}/config_${timestamp}.yaml"
        mkdir -p "$BACKUP_DIR"
        cp "$CONFIG_FILE" "$backup_path"
        log_success "配置已备份: $backup_path"

        "$DEFAULT_EDITOR" "$CONFIG_FILE"

        if validate_config; then
            log_success "配置验证成功"

            if confirm "应用更改？"; then
                apply_changes
            fi
        else
            log_error "配置格式错误"
        fi
    fi
}

# 系统设置
system_settings() {
    while true; do
        show_title

        echo -e "${HEADER_COLOR}⚙️  系统设置${NC}"
        hline

        # 获取当前设置
        local auto_apply=$(get_config '.settings.auto_apply')
        local fzf_ui=$(get_config '.settings.enable_fzf_ui')

        echo -e "  ${CYAN}1.${NC} 自动应用更改: $([[ "$auto_apply" == "true" ]] && echo "${GREEN}启用${NC}" || echo "${RED}禁用${NC}")"
        echo -e "  ${CYAN}2.${NC} FZF 界面: $([[ "$fzf_ui" == "true" ]] && echo "${GREEN}启用${NC}" || echo "${RED}禁用${NC}")"
        echo -e "  ${CYAN}3.${NC} 修复权限"
        echo -e "  ${CYAN}4.${NC} 导出配置"
        echo -e "  ${CYAN}5.${NC} 导入配置"
        echo -e "  ${MUTED_COLOR}0. 返回${NC}"

        hline
        read -p "$(echo -e "${YELLOW}选择: ${NC}")" -r choice

        case "$choice" in
            1)
                if [[ "$auto_apply" == "true" ]]; then
                    "$YQ" e '.settings.auto_apply = false' -i "$CONFIG_FILE"
                    log_success "已禁用自动应用"
                else
                    "$YQ" e '.settings.auto_apply = true' -i "$CONFIG_FILE"
                    log_success "已启用自动应用"
                fi
                ;;
            2)
                if [[ "$fzf_ui" == "true" ]]; then
                    "$YQ" e '.settings.enable_fzf_ui = false' -i "$CONFIG_FILE"
                    FZF_ENABLED=false
                    log_success "已禁用 FZF"
                else
                    "$YQ" e '.settings.enable_fzf_ui = true' -i "$CONFIG_FILE"
                    FZF_ENABLED=true
                    log_success "已启用 FZF"
                fi
                ;;
            3)
                fix_permissions
                ;;
            4)
                export_config
                ;;
            5)
                import_config
                ;;
            0)
                break
                ;;
            *)
                log_error "无效选择"
                ;;
        esac

        pause
    done
}

# 修复权限
fix_permissions() {
    echo
    hline
    echo -e "${HEADER_COLOR}🔧 修复权限${NC}"
    hline

    echo -e "正在修复文件权限..."

    # 修复脚本执行权限
    find "$SCRIPT_DIR" -name "*.sh" -type f -exec chmod +x {} \; 2> /dev/null

    # 修复 yq
    if [[ -f "$YQ" ]]; then
        chmod +x "$YQ"
    fi

    # 修复 bin 目录
    if [[ -d "$BIN_DIR" ]]; then
        find "$BIN_DIR" -type f -name "*.sh" -exec chmod +x {} \; 2> /dev/null
    fi

    log_success "权限修复完成"
}

# 导出配置
export_config() {
    echo
    hline
    echo -e "${HEADER_COLOR}📤 导出配置${NC}"
    hline

    local export_dir="${SCRIPT_DIR}/exports"
    mkdir -p "$export_dir"

    local timestamp=$(date +"%Y%m%d_%H%M%S")
    local export_path="${export_dir}/scripts_${timestamp}.yaml"

    cp "$CONFIG_FILE" "$export_path"

    if [[ $? -eq 0 ]]; then
        log_success "配置已导出: $export_path"
    else
        log_error "导出失败"
    fi
}

# 导入配置
import_config() {
    echo
    hline
    echo -e "${HEADER_COLOR}📥 导入配置${NC}"
    hline

    local import_dir="${SCRIPT_DIR}/exports"
    mkdir -p "$import_dir"

    echo -e "可用的配置文件:"
    local files=()
    while IFS= read -r -d $'\0' file; do
        files+=("$file")
        echo -e "  ${CYAN}[${#files[@]}]${NC} $(basename "$file")"
    done < <(find "$import_dir" -name "*.yaml" -type f -print0 2> /dev/null)

    if [[ ${#files[@]} -eq 0 ]]; then
        log_error "未找到配置文件"
        return
    fi

    echo -e "  ${MUTED_COLOR}0. 取消${NC}"
    read -p "$(echo -e "${YELLOW}选择文件: ${NC}")" -r choice

    if [[ "$choice" == "0" ]]; then
        return
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -le ${#files[@]} ]]; then
        local selected_file="${files[$((choice - 1))]}"

        echo
        echo -e "文件: ${MUTED_COLOR}$(basename "$selected_file")${NC}"

        if confirm "${ERROR_COLOR}⚠ 确认导入？将覆盖当前配置。${NC}"; then
            # 备份当前配置
            local timestamp=$(date +"%Y%m%d_%H%M%S")
            local backup_path="${BACKUP_DIR}/config_before_import_${timestamp}.yaml"
            cp "$CONFIG_FILE" "$backup_path"
            log_success "当前配置已备份: $backup_path"

            # 导入配置
            if cp "$selected_file" "$CONFIG_FILE" && validate_config; then
                log_success "配置导入成功"

                if confirm "立即应用更改？"; then
                    apply_changes
                fi
            else
                log_error "导入失败，配置格式错误"
            fi
        fi
    else
        log_error "无效选择"
    fi
}

# 初始化检查
init_check() {
    # 检查必需文件
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "配置文件不存在: $CONFIG_FILE"
        exit 1
    fi

    if [[ ! -x "$YQ" ]]; then
        log_error "yq 工具未找到: $YQ"
        exit 1
    fi

    if ! validate_config; then
        log_error "配置文件格式错误"
        exit 1
    fi

    # 检查 fzf
    if [[ "$(get_config '.settings.enable_fzf_ui')" == "true" ]] && ! check_command fzf; then
        log_warning "fzf 未安装，将使用简单菜单"
        FZF_ENABLED=false
    else
        FZF_ENABLED=$(get_config '.settings.enable_fzf_ui')
    fi

    # 创建必要目录
    mkdir -p "$BACKUP_DIR" "$BIN_DIR" "${SCRIPT_DIR}/exports" 2> /dev/null || true
}

# 主函数
main() {
    # 初始化检查
    init_check

    # 进入主菜单
    main_menu
}

# 程序入口
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    trap 'echo -e "\n${ERROR_COLOR}操作中断${NC}"; exit 130' INT
    main "$@"
fi
