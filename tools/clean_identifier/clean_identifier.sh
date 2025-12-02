#!/bin/bash
# clean-zone-identifiers.sh
# 功能：递归删除指定目录中的所有 Zone.Identifier 文件
# 用法：./clean-zone-identifiers.sh [目录路径]

set -e  # 遇到错误时退出脚本

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 显示用法信息
show_usage() {
    echo -e "${BLUE}用法:${NC}"
    echo "  $0 [目录路径]"
    echo "  如果不指定目录路径，则默认清理当前目录"
    echo ""
    echo -e "${BLUE}示例:${NC}"
    echo "  $0                    # 清理当前目录"
    echo "  $0 ~/.config/nvim    # 清理指定目录"
    echo "  $0 /path/to/project  # 清理项目目录"
}

# 显示帮助信息
show_help() {
    echo -e "${BLUE}Zone.Identifier 文件清理脚本${NC}"
    echo ""
    echo "此脚本用于递归删除 Windows 系统生成的 Zone.Identifier 文件"
    echo "这些文件通常包含在从网络下载的文件中，用于标记文件来源"
    echo ""
    show_usage
    echo ""
    echo -e "${BLUE}选项:${NC}"
    echo "  -h, --help    显示此帮助信息"
    echo "  -v, --verbose 显示详细输出"
    echo "  -d, --dry-run 预览模式，不实际删除文件"
    echo "  -q, --quiet   静默模式，只显示错误"
}

# 初始化变量
TARGET_DIR="."
VERBOSE=0
DRY_RUN=0
QUIET=0

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=1
            shift
            ;;
        -q|--quiet)
            QUIET=1
            shift
            ;;
        -*)
            echo -e "${RED}错误: 未知选项 $1${NC}" >&2
            show_usage
            exit 1
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# 检查目录是否存在
if [ ! -d "$TARGET_DIR" ]; then
    echo -e "${RED}错误: 目录不存在: $TARGET_DIR${NC}" >&2
    exit 1
fi

# 获取绝对路径
TARGET_DIR=$(realpath "$TARGET_DIR")

# 显示开始信息
if [ $QUIET -eq 0 ]; then
    echo -e "${BLUE}开始扫描目录: $TARGET_DIR${NC}"
    
    if [ $DRY_RUN -eq 1 ]; then
        echo -e "${YELLOW}预览模式: 不会实际删除文件${NC}"
    fi
    echo ""
fi

# 查找所有 Zone.Identifier 文件
ZONE_FILES=$(find "$TARGET_DIR" -name "*:Zone.Identifier" -type f 2>/dev/null || true)

# 统计文件数量
FILE_COUNT=$(echo "$ZONE_FILES" | grep -c "^" || true)

if [ $FILE_COUNT -eq 0 ]; then
    if [ $QUIET -eq 0 ]; then
        echo -e "${GREEN}✅ 没有找到 Zone.Identifier 文件${NC}"
    fi
    exit 0
fi

if [ $QUIET -eq 0 ]; then
    echo -e "${YELLOW}找到 $FILE_COUNT 个 Zone.Identifier 文件:${NC}"
    
    # 显示文件列表（限制前20个，避免输出过多）
    if [ $VERBOSE -eq 1 ]; then
        echo "$ZONE_FILES" | head -n 20
        if [ $FILE_COUNT -gt 20 ]; then
            echo -e "${YELLOW}... 还有 $(($FILE_COUNT - 20)) 个文件未显示${NC}"
        fi
    else
        echo "$ZONE_FILES" | head -n 5
        if [ $FILE_COUNT -gt 5 ]; then
            echo -e "${YELLOW}... 还有 $(($FILE_COUNT - 5)) 个文件未显示${NC}"
            echo -e "${YELLOW}使用 -v 选项查看完整列表${NC}"
        fi
    fi
    echo ""
fi

# 如果不是预览模式，询问确认
if [ $DRY_RUN -eq 0 ] && [ $QUIET -eq 0 ]; then
    read -p "是否删除这 $FILE_COUNT 个文件？(y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}操作已取消${NC}"
        exit 0
    fi
fi

# 删除文件
DELETED_COUNT=0
ERROR_COUNT=0

if [ $DRY_RUN -eq 0 ]; then
    # 实际删除文件
    while IFS= read -r file; do
        if [ -n "$file" ]; then
            if rm -f "$file" 2>/dev/null; then
                DELETED_COUNT=$((DELETED_COUNT + 1))
                if [ $VERBOSE -eq 1 ]; then
                    echo -e "${GREEN}✅ 已删除: $file${NC}"
                fi
            else
                ERROR_COUNT=$((ERROR_COUNT + 1))
                if [ $QUIET -eq 0 ]; then
                    echo -e "${RED}❌ 删除失败: $file${NC}" >&2
                fi
            fi
        fi
    done <<< "$ZONE_FILES"
else
    # 预览模式，只计数
    DELETED_COUNT=$FILE_COUNT
fi

# 显示结果摘要
if [ $QUIET -eq 0 ]; then
    echo ""
    if [ $DRY_RUN -eq 1 ]; then
        echo -e "${BLUE}预览完成${NC}"
        echo -e "  找到文件: $FILE_COUNT 个"
        echo -e "  将会删除: $DELETED_COUNT 个"
    else
        if [ $ERROR_COUNT -eq 0 ]; then
            echo -e "${GREEN}✅ 清理完成！${NC}"
            echo -e "  找到文件: $FILE_COUNT 个"
            echo -e "  成功删除: $DELETED_COUNT 个"
        else
            echo -e "${YELLOW}⚠️  清理完成（有错误）${NC}"
            echo -e "  找到文件: $FILE_COUNT 个"
            echo -e "  成功删除: $DELETED_COUNT 个"
            echo -e "  删除失败: $ERROR_COUNT 个"
        fi
    fi
fi

# 根据错误计数设置退出码
if [ $ERROR_COUNT -gt 0 ]; then
    exit 1
else
    exit 0
fi
