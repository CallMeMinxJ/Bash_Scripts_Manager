#!/bin/bash

# Bash Scripts Manager - Interactive Manager
# Description: Interactive tool to manage bash scripts configuration

set -euo pipefail

# Get the correct script directory (handles both direct execution and symlink)
if [[ -L "${BASH_SOURCE[0]}" ]]; then
    # If called via symlink, resolve the symlink to get the real path
    readonly SCRIPT_DIR="$(cd -P "$(dirname "$(readlink "${BASH_SOURCE[0]}")")" && pwd)"
else
    # If called directly
    readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi

readonly CONFIG_FILE="${SCRIPT_DIR}/scripts.conf"
readonly INIT_SCRIPT="${SCRIPT_DIR}/init.sh"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# Text formatting
readonly BOLD='\033[1m'
readonly UNDERLINE='\033[4m'

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Global arrays for storing configuration
declare -a CONFIG_LINES
declare -a SCRIPT_TYPES
declare -a SCRIPT_STATUS
declare -a SCRIPT_ALIASES
declare -a SCRIPT_DESCRIPTIONS
declare -a SCRIPT_FILENAMES
TOTAL_SCRIPTS=0

# Parse configuration and store in arrays
parse_config() {
    log_info "Starting to parse configuration file: ${CONFIG_FILE}"

    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        return 1
    fi

    if [[ ! -r "${CONFIG_FILE}" ]]; then
        log_error "Configuration file is not readable: ${CONFIG_FILE}"
        return 1
    fi

    CONFIG_LINES=()
    SCRIPT_TYPES=()
    SCRIPT_STATUS=()
    SCRIPT_ALIASES=()
    SCRIPT_DESCRIPTIONS=()
    SCRIPT_FILENAMES=()

    local index=0
    local line_num=0

    while IFS= read -r line || [[ -n "${line}" ]]; do
        ((line_num++))

        line="${line%%#*}"
        line="${line#"${line%%[![:space:]]*}"}"
        line="${line%"${line##*[![:space:]]}"}"

        [[ -z "${line}" ]] && continue

        if [[ "${line}" =~ ^[^:]+:[^:]+:[^:]+:[^:]+:[^:]+ ]]; then
            CONFIG_LINES+=("${line}")
            log_info "Parsing line ${line_num}: ${line}"

            IFS=':' read -r type status alias description filename <<< "${line}"

            SCRIPT_TYPES[index]=$(echo "${type}" | xargs)
            SCRIPT_STATUS[index]=$(echo "${status}" | xargs)
            SCRIPT_ALIASES[index]=$(echo "${alias}" | xargs)
            SCRIPT_DESCRIPTIONS[index]=$(echo "${description}" | xargs)
            SCRIPT_FILENAMES[index]=$(echo "${filename}" | xargs)

            ((index++))
        else
            log_warning "Skipping malformed line ${line_num}: ${line}"
        fi
    done < "${CONFIG_FILE}"

    TOTAL_SCRIPTS="${index}"
    log_info "Successfully parsed ${TOTAL_SCRIPTS} scripts from configuration"

    if [[ "${TOTAL_SCRIPTS}" -eq 0 ]]; then
        log_warning "No valid scripts found in configuration file"
    fi

    return 0
}

# Display current configuration
show_config() {
    echo -e "\n${BOLD}${UNDERLINE}Current Bash Scripts Configuration:${NC}\n"

    printf "%-2s %-8s %-12s %-15s %s\n" "#" "Type" "Status" "Alias/File" "Description"
    echo "----------------------------------------------------------------"

    for ((i = 0; i < TOTAL_SCRIPTS; i++)); do
        local status_indicator=" "
        if [[ "${SCRIPT_STATUS[i]}" == "enable" ]]; then
            status_indicator="*"
        fi

        local alias_or_file="${SCRIPT_ALIASES[i]}"
        if [[ -z "${alias_or_file}" ]]; then
            alias_or_file="${SCRIPT_FILENAMES[i]}"
        fi

        printf "[%1s] %-8s %-12s %-15s %s\n" \
            "${status_indicator}" \
            "${SCRIPT_TYPES[i]}" \
            "${SCRIPT_STATUS[i]}" \
            "${alias_or_file}" \
            "${SCRIPT_DESCRIPTIONS[i]}"
    done

    echo -e "\n${BOLD}Legend:${NC} [*] = Enabled"
    echo
}

# Toggle script status
toggle_script() {
    local script_num="$1"

    if [[ "${script_num}" -lt 0 || "${script_num}" -ge "${TOTAL_SCRIPTS}" ]]; then
        log_error "Invalid script number: ${script_num}"
        return 1
    fi

    local current_status="${SCRIPT_STATUS[script_num]}"
    local new_status="disable"

    if [[ "${current_status}" == "disable" ]]; then
        new_status="enable"
    fi

    # Update the configuration line
    local old_line="${CONFIG_LINES[script_num]}"
    local new_line="${SCRIPT_TYPES[script_num]}:${new_status}:${SCRIPT_ALIASES[script_num]}:${SCRIPT_DESCRIPTIONS[script_num]}:${SCRIPT_FILENAMES[script_num]}"

    if sed -i.tmp "s|^${old_line}$|${new_line}|" "${CONFIG_FILE}" && rm -f "${CONFIG_FILE}.tmp"; then
        log_success "Script ${SCRIPT_FILENAMES[script_num]} is now ${new_status}d"
    else
        log_error "Failed to update configuration file"
        return 1
    fi
}

# Apply configuration changes
apply_changes() {
    log_info "Applying configuration changes..."

    if [[ ! -x "${INIT_SCRIPT}" ]]; then
        chmod +x "${INIT_SCRIPT}"
    fi

    if "${INIT_SCRIPT}"; then
        log_success "Configuration applied successfully!"
    else
        log_error "Failed to apply configuration changes"
        return 1
    fi
}

# Show main menu
show_menu() {
    echo -e "\n${BOLD}${CYAN}Bash Scripts Manager${NC}"
    echo "============================================================"
    echo "1) Show current configuration"
    echo "2) Toggle script status"
    echo "3) Exit"
    echo "============================================================"
    echo
    read -p "Select option [1-4]: " choice
}

# Interactive menu
interactive_menu() {
    while true; do
        show_menu

        case "${choice}" in
            1)
                show_config
                ;;
            2)
                show_config
                if [[ "${TOTAL_SCRIPTS}" -eq 0 ]]; then
                    log_warning "No scripts configured"
                    continue
                fi

                read -p "Enter script number to toggle (0-$((TOTAL_SCRIPTS - 1))): " script_num
                if [[ "${script_num}" =~ ^[0-9]+$ ]] &&
                    [[ "${script_num}" -ge 0 ]] &&
                    [[ "${script_num}" -lt "${TOTAL_SCRIPTS}" ]]; then
                    if toggle_script "${script_num}"; then
                        log_info "Script toggled successfully, now reloading configuration..."
                        if parse_config; then
                            log_info "Configuration reloaded successfully, now applying changes..."
                            apply_changes
                        else
                            log_error "Failed to reload configuration after toggling script"
                        fi
                    else
                        log_error "Failed to toggle script"
                    fi
                else
                    log_error "Invalid script number"
                fi
                ;;
            3)
                log_info "Goodbye!"
                exit 0
                ;;
            *)
                log_error "Invalid option"
                ;;
        esac

        read -p "Press Enter to continue..."
    done
}

# Command line interface
command_line_interface() {
    case "${1:-}" in
        "list" | "show")
            show_config
            ;;
        "toggle")
            if [[ -z "${2:-}" ]]; then
                log_error "Please specify script number"
                exit 1
            fi
            toggle_script "$2"
            apply_changes
            ;;
        "apply")
            apply_changes
            ;;
        "help" | "-h" | "--help")
            echo -e "${BOLD}Usage:${NC}"
            echo "  $0 [command]"
            echo
            echo "${BOLD}Commands:${NC}"
            echo "  list/show  - Display current configuration"
            echo "  toggle N   - Toggle script number N and apply changes"
            echo "  apply      - Apply configuration changes"
            echo "  help       - Show this help message"
            echo "  (no args)  - Interactive mode"
            ;;
        *)
            interactive_menu
            ;;
    esac
}

# Main function
main() {
    if ! parse_config; then
        exit 1
    fi

    command_line_interface "$@"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
