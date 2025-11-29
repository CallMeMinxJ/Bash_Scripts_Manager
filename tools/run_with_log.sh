#!/usr/bin/env bash

# 脚本名称: run_with_log.sh
# 功能描述: 包装其他脚本运行，记录带时间戳的日志，支持灵活配置输出

# ------------------------------- 帮助信息函数 --------------------------------
show_help() {
    cat << EOF
用法: ${0##*/} [选项] <目标脚本> [目标脚本参数...]

选项:
  -h, --help            显示此帮助信息并退出
  --no-timestamp        关闭日志文件中的时间戳（默认启用）
  --silent              关闭终端输出（仅输出到日志文件，默认开启）

核心功能:
  1. 自动捕获目标脚本的所有输出（stdout/stderr）
  2. 日志文件默认带时间戳，存储于 ~/logs 目录
  3. 终端输出保持原始内容（无时间戳）
  4. 支持灵活配置时间戳和终端输出开关
  5. 自动生成规范的日志文件名（脚本名_日期时间.log）

示例:
  # 基础用法（带时间戳，终端+日志输出）
  ${0##*/} build.sh

  # 无时间戳日志（终端+日志输出）
  ${0##*/} --no-timestamp test.sh arg1 arg2

  # 仅日志输出（带时间戳）
  ${0##*/} --silent install.sh

  # 无时间戳且仅日志输出
  ${0##*/} --no-timestamp --silent demo.sh
EOF
}

# ------------------------------- 参数解析函数 --------------------------------
parse_arguments() {
    # 初始化默认值
    TIMESTAMP_ENABLED="true"
    SILENT_MODE="false"
    TARGET_SCRIPT=""
    TARGET_ARGS=()

    # 参数解析循环
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            --no-timestamp)
                TIMESTAMP_ENABLED="false"
                shift
                ;;
            --silent)
                SILENT_MODE="true"
                shift
                ;;
            --)  # 选项结束符
                shift
                TARGET_SCRIPT="$1"
                shift
                TARGET_ARGS=("$@")
                break
                ;;
            -*)
                echo "错误: 未知选项 '$1'" >&2
                exit 1
                ;;
            *)  # 第一个非选项参数为目标脚本
                TARGET_SCRIPT="$1"
                shift
                TARGET_ARGS=("$@")
                break
                ;;
        esac
    done
}

# ------------------------------- 验证函数 ------------------------------------
validate_inputs() {
    # 检查目标脚本是否提供
    if [[ -z "$TARGET_SCRIPT" ]]; then
        echo "错误: 未指定目标脚本，请提供要运行的脚本路径" >&2
        show_help
        exit 1
    fi

    # 检查目标脚本是否存在
    if [[ ! -f "$TARGET_SCRIPT" ]]; then
        echo "错误: 目标脚本 '$TARGET_SCRIPT' 不存在" >&2
        exit 1
    fi

    # 检查目标脚本是否可执行
    if [[ ! -x "$TARGET_SCRIPT" ]]; then
        echo "错误: 目标脚本 '$TARGET_SCRIPT' 不可执行，请检查权限" >&2
        exit 1
    fi

    # 创建日志目录（如果不存在）
    LOG_DIR="$HOME/logs/compiles"
    if ! mkdir -p "$LOG_DIR"; then
        echo "错误: 无法创建日志目录 '$LOG_DIR'" >&2
        exit 1
    fi
}

# ------------------------------- 日志生成函数 --------------------------------
generate_log_name() {
    local script_basename=$(basename "$TARGET_SCRIPT")
    local timestamp=$(date +%Y%m%d_%H%M%S)
    echo "${LOG_DIR}/${script_basename}_${timestamp}.log"
}

# ------------------------------- 输出处理函数 --------------------------------
process_output() {
    awk -v ts_enabled="$TIMESTAMP_ENABLED" '
    BEGIN {
        # 兼容检查：旧版本awk可能不支持strftime
        if (ts_enabled == "true" && strftime("%Y") == "") {
            print "警告: 当前awk版本不支持strftime，时间戳功能将失效" > "/dev/stderr"
            ts_enabled = "false"
        }
    }
    ts_enabled == "true" {
        # 格式化时间戳（精确到秒）
        printf "[%s] %s\n", strftime("%Y-%m-%d %H:%M:%S"), $0
        next
    }
    { print }  # 无时间戳时直接输出原行
    '
}

# ------------------------------- 主执行流程 ----------------------------------
main() {
    # 解析命令行参数
    parse_arguments "$@"
    
    # 验证输入有效性
    validate_inputs
    
    # 生成日志文件路径
    LOG_FILE=$(generate_log_name)
    
    # 输出运行前配置信息（美观格式化）
    echo "===== 脚本运行配置 ====="
    printf "%-20s %s
" "目标脚本路径:" "$TARGET_SCRIPT"
    printf "%-20s %s
" "日志文件路径:" "$LOG_FILE"
    printf "%-20s %s
" "时间戳启用:" "$TIMESTAMP_ENABLED"
    printf "%-20s %s
" "终端输出:" "${SILENT_MODE:+关闭（仅日志）:-开启（终端+日志）}"
    echo "========================="

    # 执行目标脚本并处理输出
    echo "▶ 开始运行目标脚本: $TARGET_SCRIPT"
    exit_code=0
    
    if [[ "$SILENT_MODE" == "true" ]]; then
        # 静默模式：仅输出到日志文件
        {
            "$TARGET_SCRIPT" "${TARGET_ARGS[@]}" 2>&1
            exit_code=$?
        } | process_output > "$LOG_FILE"
    else
        # 标准模式：输出到终端（原始）和日志文件（处理后）
        {
            "$TARGET_SCRIPT" "${TARGET_ARGS[@]}" 2>&1
            exit_code=$?
        } | tee >(process_output > "$LOG_FILE")
    fi

    # 输出完成信息
    echo "✔ 目标脚本运行完成（退出码: $exit_code）"
    echo "   日志文件已保存至: $LOG_FILE"
    
    # 返回目标脚本的退出码
    exit $exit_code
}

# 启动主流程
main "$@"
