#!/bin/bash

# Bash Scripts Manager - Initialization Script
# Description: Apply configuration from bash_manager.conf

set -euo pipefail

# Get the real path of the script
get_real_script_dir() {
    local source="${BASH_SOURCE[0]}"
    while [ -h "$source" ]; do
        local dir="$(cd -P "$(dirname "$source")" && pwd)"
        source="$(readlink "$source")"
        [[ $source != /* ]] && source="$dir/$source"
    done
    dir="$(cd -P "$(dirname "$source")" && pwd)"
    echo "$dir"
}

readonly SCRIPT_DIR="$(get_real_script_dir)"
readonly CONFIG_FILE="${SCRIPT_DIR}/scripts.conf"
readonly STARTUP_DIR="${SCRIPT_DIR}/startup"
readonly TOOLS_DIR="${SCRIPT_DIR}/tools"
readonly BIN_DIR="${SCRIPT_DIR}/bin"
readonly BASHRC_FILE="${HOME}/.bashrc"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Create necessary directories
create_directories() {
    mkdir -p "${BIN_DIR}" "${STARTUP_DIR}" "${TOOLS_DIR}" 2>/dev/null || true
}

# Clean up previous modifications from .bashrc
cleanup_bashrc() {
    log_info "Cleaning up previous modifications from ${BASHRC_FILE}..."
    
    if [[ ! -f "${BASHRC_FILE}" ]]; then
        log_warning "bashrc file not found: ${BASHRC_FILE}"
        return 0
    fi
    
    # Create backup
    cp "${BASHRC_FILE}" "${BASHRC_FILE}.bak.$(date +%Y%m%d%H%M%S)" 2>/dev/null || true
    
    # Remove all lines added by this manager
    # This includes startup script sources and PATH modifications
    if grep -q "Bash Scripts Manager" "${BASHRC_FILE}" 2>/dev/null; then
        # Use a temporary file for editing
        local temp_file
        temp_file=$(mktemp)
        
        # Remove all sections added by this script manager
        awk '
        /# Added by Bash Scripts Manager/ { skip=1; next }
        /# End of Bash Scripts Manager/ { skip=0; next }
        skip == 0 { print }
        ' "${BASHRC_FILE}" > "${temp_file}"
        
        # Replace the original file
        mv "${temp_file}" "${BASHRC_FILE}"
        log_success "Removed all script manager modifications from bashrc"
    else
        log_info "No existing script manager modifications found in bashrc"
    fi
}

# Clean up bin directory
cleanup_bin() {
    log_info "Cleaning up bin directory: ${BIN_DIR}"
    
    if [[ -d "${BIN_DIR}" ]]; then
        # Remove all symlinks in bin directory
        find "${BIN_DIR}" -type l -delete 2>/dev/null || true
        log_success "Cleaned bin directory"
    else
        log_info "Bin directory does not exist, creating it"
        mkdir -p "${BIN_DIR}"
    fi
}

# Parse configuration file
parse_config() {
    local config_lines=()
    
    if [[ ! -f "${CONFIG_FILE}" ]]; then
        log_error "Configuration file not found: ${CONFIG_FILE}"
        return 1
    fi
    
    # Read config file, skip comments and empty lines
    while IFS= read -r line; do
        line="${line%%#*}"  # Remove comments
        line="${line##*( )}" # Remove leading spaces
        line="${line%%*( )}" # Remove trailing spaces
        
        if [[ -n "${line}" ]] && [[ "${line}" =~ : ]]; then
            config_lines+=("${line}")
        fi
    done < "${CONFIG_FILE}"
    
    printf '%s\n' "${config_lines[@]}"
}

# Add startup script to .bashrc
add_startup_script() {
    local script_file="$1"
    local description="$2"
    
    if [[ ! -f "${script_file}" ]]; then
        log_warning "Startup script not found: ${script_file}"
        return 1
    fi
    
    local startup_line="# Startup: ${description}"
    local source_line="source \"${script_file}\""
    
    # Check if already added
    if ! grep -qF "${source_line}" "${BASHRC_FILE}"; then
        {
            echo ""
            echo "# Added by Bash Scripts Manager"
            echo "${startup_line}"
            echo "${source_line}"
            echo "# End of Bash Scripts Manager"
            echo ""
        } >> "${BASHRC_FILE}"
        log_success "Added startup script: $(basename "${script_file}")"
    else
        log_info "Startup script already exists: $(basename "${script_file}")"
    fi
}

# Create tool script symlink
create_tool_symlink() {
    local tool_file="$1"
    local alias_name="$2"
    local description="$3"
    
    if [[ ! -f "${tool_file}" ]]; then
        log_warning "Tool script not found: ${tool_file}"
        return 1
    fi
    
    local symlink_path="${BIN_DIR}/${alias_name}"
    
    # Remove existing symlink if it exists
    if [[ -L "${symlink_path}" ]]; then
        rm "${symlink_path}"
    fi
    
    # Create new symlink
    if ln -s "${tool_file}" "${symlink_path}"; then
        chmod +x "${tool_file}"  # Ensure script is executable
        log_success "Created symlink: ${alias_name} -> $(basename "${tool_file}")"
    else
        log_error "Failed to create symlink: ${alias_name}"
        return 1
    fi
}

# Add bin directory to PATH in .bashrc
add_bin_to_path() {
    local bin_path_comment="# Added by Bash Scripts Manager - Bin directory"
    local bin_path_line="export PATH=\"${BIN_DIR}:\$PATH\""
    
    # Check if already added
    if ! grep -qF "${bin_path_line}" "${BASHRC_FILE}"; then
        {
            echo ""
            echo "# Added by Bash Scripts Manager"
            echo "${bin_path_comment}"
            echo "${bin_path_line}"
            echo "# End of Bash Scripts Manager"
            echo ""
        } >> "${BASHRC_FILE}"
        log_success "Added ${BIN_DIR} to PATH in ${BASHRC_FILE}"
    else
        log_info "Bin directory already in PATH"
    fi
}

# Always link bash_manager.sh as shmng
link_manager_script() {
    local manager_script="${SCRIPT_DIR}/bash_manager.sh"
    local symlink_path="${BIN_DIR}/shmng"
    
    if [[ -f "${manager_script}" ]]; then
        # Remove existing symlink
        if [[ -L "${symlink_path}" ]]; then
            rm "${symlink_path}"
        fi
        
        # Create new symlink
        if ln -s "${manager_script}" "${symlink_path}"; then
            chmod +x "${manager_script}"
            log_success "Created manager symlink: shmng"
        else
            log_error "Failed to create manager symlink"
        fi
    else
        log_warning "Manager script not found: ${manager_script}"
    fi
}

# Main initialization function
main() {
    log_info "Starting Bash Scripts Manager initialization..."
    
    create_directories
    cleanup_bashrc
    cleanup_bin
    
    local config_lines
    config_lines=$(parse_config) || exit 1
    
    # Process each configuration line
    while IFS= read -r line; do
        # Skip empty lines
        [[ -z "${line}" ]] && continue
        
        IFS=':' read -r type status alias description filename <<< "${line}"
        
        # Remove leading/trailing whitespace
        type=$(echo "${type}" | xargs)
        status=$(echo "${status}" | xargs)
        alias=$(echo "${alias}" | xargs)
        description=$(echo "${description}" | xargs)
        filename=$(echo "${filename}" | xargs)
        
        if [[ "${status}" != "enable" ]]; then
            log_info "Skipping disabled script: ${filename}"
            continue
        fi
        
        case "${type}" in
            startup)
                local script_path="${STARTUP_DIR}/${filename}"
                if [[ -f "${script_path}" ]]; then
                    add_startup_script "${script_path}" "${description}"
                else
                    log_warning "Startup script file not found: ${script_path}"
                fi
                ;;
            tools)
                if [[ -n "${alias}" ]]; then
                    local script_path="${TOOLS_DIR}/${filename}"
                    if [[ -f "${script_path}" ]]; then
                        create_tool_symlink "${script_path}" "${alias}" "${description}"
                    else
                        log_warning "Tool script file not found: ${script_path}"
                    fi
                else
                    log_warning "Tools script must have an alias: ${filename}"
                fi
                ;;
            *)
                log_warning "Unknown script type: ${type} for ${filename}"
                ;;
        esac
    done <<< "${config_lines}"
    
    # Always add bin directory to PATH
    add_bin_to_path
    
    # Always create manager symlink
    link_manager_script
    
    log_success "Initialization completed successfully!"
    log_info "Please run: source ${BASHRC_FILE} to apply changes immediately"
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
