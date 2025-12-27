#!/bin/bash

################################################################################
# restore.sh: System Restoration Script
#
# Purpose:
#   Parse the freshMac snapshot file and guide/execute restoration of
#   applications and tools to a freshly reset macOS system.
#
# Usage:
#   ./restore.sh <snapshot_file>
#   ./restore.sh --help
#
# This script is INTENTIONALLY NON-DESTRUCTIVE by default.
# It provides commands to execute, requiring manual confirmation.
################################################################################

# Use -u to catch undefined variables, but NOT -e
# (we handle errors explicitly to prevent one failed package stopping the entire restore)
set -uo pipefail

# ============================================================================
# Configuration & Constants
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SNAPSHOT_FILE="${1:-}"
DRY_RUN=${DRY_RUN:-true}  # Default to dry-run (safe mode)
VERBOSE=${VERBOSE:-false}

# Section header constants - avoid duplicated magic strings
SECTION_TAPS="HOMEBREW TAPS"
SECTION_RESTORE_CMD="HOMEBREW RESTORE COMMAND"
SECTION_MANUAL="MANUAL INSTALLATIONS WITH OFFICIAL SOURCES"

# Tracking variables for error reporting
FAILED_PACKAGES=()
FAILED_TAPS=()
SKIPPED_PACKAGES=()
RESTORE_WARNINGS=()

# ============================================================================
# Utility Functions
# ============================================================================

log_info() {
    echo "[INFO] $*" >&2
}

log_warn() {
    echo "[WARN] $*" >&2
}

log_error() {
    echo "[ERROR] $*" >&2
}

log_step() {
    echo "" >&2
    echo "========================================" >&2
    echo "$*" >&2
    echo "========================================" >&2
}

show_help() {
    cat <<EOF
freshMac System Restoration

Usage:
  ./restore.sh <snapshot_file>
  ./restore.sh --help

Environment Variables:
  DRY_RUN=false     Execute commands (default: true for safety)
  VERBOSE=true      Show all command details

Examples:
  # Preview restoration steps (safe, shows what would happen)
  ./restore.sh output/freshmac_snapshot.txt

  # Actually execute restoration (CAUTION!)
  DRY_RUN=false ./restore.sh output/freshmac_snapshot.txt

  # Verbose mode
  VERBOSE=true ./restore.sh output/freshmac_snapshot.txt

Notes:
  - Always review with DRY_RUN=true first
  - This script does NOT uninstall existing apps
  - It only installs missing packages and apps
  - Manual installation required for apps not in Homebrew

EOF
}

validate_snapshot_file() {
    if [[ -z "$SNAPSHOT_FILE" ]]; then
        log_error "No snapshot file provided"
        show_help
        exit 1
    fi

    if [[ ! -f "$SNAPSHOT_FILE" ]]; then
        log_error "Snapshot file not found: $SNAPSHOT_FILE"
        exit 1
    fi

    log_info "Using snapshot file: $SNAPSHOT_FILE"
}

# ============================================================================
# Homebrew Validation
# ============================================================================

validate_homebrew() {
    log_step "Checking Homebrew installation"

    if ! command -v brew &>/dev/null; then
        log_warn "Homebrew is not installed"
        log_info "Install Homebrew from: https://brew.sh/"
        log_info "  /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\""
        return 1
    fi

    local brew_version
    brew_version=$(brew --version 2>/dev/null || echo "unknown")
    log_info "Homebrew found: $brew_version"
    return 0
}

# ============================================================================
# Snapshot Parsing (Robust & Case-Insensitive)
# ============================================================================

extract_section() {
    local section_name="$1"
    local snapshot_file="$2"
    local in_section=0
    local found=0
    local skip_next_equals=0
    
    # Read file line by line for robust matching
    # The snapshot file format is:
    # ====================================
    # SECTION NAME
    # ====================================
    # content
    # ====================================
    while IFS= read -r line; do
        # If we found the section header on the previous iteration,
        # skip the next line of equals and start capturing content
        if [ $skip_next_equals -eq 1 ]; then
            if echo "$line" | grep -q "^==*$"; then
                skip_next_equals=0
                in_section=1
                continue
            fi
        fi
        
        # Check if this line is exactly (or case-insensitively) the section name
        if [ "$(echo "$line" | tr '[:lower:]' '[:upper:]')" = "$(echo "$section_name" | tr '[:lower:]' '[:upper:]')" ]; then
            found=1
            skip_next_equals=1
            continue
        fi
        
        # If we're in a section, check for section end (line of equals)
        if [ $in_section -eq 1 ]; then
            if echo "$line" | grep -q "^==*$"; then
                break
            fi
            
            # Print non-empty lines
            if [ -n "$line" ]; then
                echo "$line"
            fi
        fi
    done < "$snapshot_file"
    
    # Return 0 if found, 1 if not found
    [ $found -eq 1 ] && return 0 || return 1
}

extract_brew_taps() {
    local snapshot_file="$1"
    
    # Use the section constant and handle missing sections gracefully
    extract_section "$SECTION_TAPS" "$snapshot_file" 2>/dev/null | grep -v "^$" || true
    
    # Return 0 even if no taps found (not an error condition)
    return 0
}

extract_brew_restore_command() {
    local snapshot_file="$1"
    local cmd
    
    # Extract the restore command from the section
    cmd=$(extract_section "$SECTION_RESTORE_CMD" "$snapshot_file" 2>/dev/null | head -1 || true)
    
    # Validate that extracted command starts with 'brew'
    if [[ -n "$cmd" ]]; then
        if ! [[ "$cmd" =~ ^brew ]]; then
            RESTORE_WARNINGS+=("Invalid restore command (doesn't start with 'brew'): $cmd")
            return 1
        fi
        echo "$cmd"
        return 0
    fi
    
    return 0
}

extract_manual_installs() {
    local snapshot_file="$1"
    
    # Extract manual installations section
    extract_section "$SECTION_MANUAL" "$snapshot_file" 2>/dev/null || true
}

# ============================================================================
# Restoration Steps
# ============================================================================

restore_homebrew_taps() {
    log_step "Restoring Homebrew Taps"

    if ! validate_homebrew; then
        log_warn "Homebrew required for tap restoration, skipping"
        return 0
    fi

    # Read taps into array (bash 4.0 compatible, works with mapfile or read loop)
    local taps=()
    while IFS= read -r tap; do
        [[ -n "$tap" ]] && taps+=("$tap")
    done < <(extract_brew_taps "$SNAPSHOT_FILE")

    if [[ ${#taps[@]} -eq 0 ]]; then
        log_info "No taps to restore"
        return 0
    fi

    log_info "Found ${#taps[@]} taps to restore"

    local success_count=0
    local skip_count=0
    
    for tap in "${taps[@]}"; do
        [[ -z "$tap" ]] && continue

        local cmd="brew tap $tap"
        
        # Check if tap is already installed to avoid redundant calls
        if brew tap-info "$tap" &>/dev/null; then
            if [[ "$VERBOSE" == "true" ]]; then
                log_info "[SKIP] Tap already installed: $tap"
            fi
            ((skip_count++))
            continue
        fi
        
        if [[ "$VERBOSE" == "true" ]]; then
            log_info "Tap command: $cmd"
        fi

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] Would run: $cmd"
            ((success_count++))
        else
            log_info "Installing tap: $tap"
            if eval "$cmd" 2>&1 | sed 's/^/  /'; then
                log_info "✓ Tap installed: $tap"
                ((success_count++))
            else
                log_warn "Failed to install tap: $tap"
                FAILED_TAPS+=("$tap")
            fi
        fi
    done

    if [[ $skip_count -gt 0 ]]; then
        log_info "($skip_count taps were already installed)"
    fi
    
    # Report tap failures if any
    if [[ ${#FAILED_TAPS[@]} -gt 0 ]]; then
        log_warn "Failed to install ${#FAILED_TAPS[@]} tap(s): ${FAILED_TAPS[*]}"
        return 1
    fi
    
    return 0
}

restore_homebrew_packages() {
    log_step "Restoring Homebrew Packages & Casks"

    if ! validate_homebrew; then
        log_warn "Homebrew required for package restoration, skipping"
        return 0
    fi

    local brew_command
    brew_command=$(extract_brew_restore_command "$SNAPSHOT_FILE")

    if [[ -z "$brew_command" ]]; then
        # Check if we got a validation error
        if [[ ${#RESTORE_WARNINGS[@]} -gt 0 ]]; then
            log_warn "Issue extracting restore command: ${RESTORE_WARNINGS[0]}"
        else
            log_info "No Homebrew packages to restore"
        fi
        return 0
    fi

    # Additional validation: ensure command starts with 'brew'
    if ! [[ "$brew_command" =~ ^brew ]]; then
        log_error "Invalid brew restore command (doesn't start with 'brew'): $brew_command"
        return 1
    fi

    log_info "Brew restore command found"

    if [[ "$VERBOSE" == "true" ]]; then
        log_info "Command: $brew_command"
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would run: $brew_command"
        return 0
    fi

    log_warn "This may take a long time. Installation starting..."
    
    # Execute brew command with output redirection
    # Do NOT use 'set -e' here - we want to continue even if one package fails
    if eval "$brew_command" 2>&1 | sed 's/^/  /'; then
        log_info "✓ Homebrew packages restored successfully"
        return 0
    else
        # Capture the exit code from the brew command
        local exit_code=${PIPESTATUS[0]}
        log_warn "Homebrew installation completed with status $exit_code"
        log_warn "Some packages may have failed. Check output above."
        # Do not return failure - continue to manual installs
        FAILED_PACKAGES+=("Some brew packages failed")
        return 0  # Return 0 to continue execution
    fi
}

restore_manual_installs() {
    log_step "Manual Application Installations"

    local manuals
    manuals=$(extract_manual_installs "$SNAPSHOT_FILE")

    if [[ -z "$manuals" || "$manuals" == "(No unresolved applications)" ]]; then
        log_info "No manual installations required"
        return 0
    fi

    log_warn "The following applications require manual installation:"
    echo "" >&2
    echo "$manuals" >&2
    echo "" >&2

    log_info "Installation steps:"
    log_info "1. Review each source URL above"
    log_info "2. Download from official sources only"
    log_info "3. Install following each vendor's instructions"
    log_info "4. Verify installation success"
}

# ============================================================================
# Summary & Guidance
# ============================================================================

print_snapshot_summary() {
    log_step "Snapshot Information"

    log_info "File: $SNAPSHOT_FILE"
    log_info "Size: $(du -h "$SNAPSHOT_FILE" | cut -f1)"
    log_info "Modified: $(stat -f "%Sm" "$SNAPSHOT_FILE" 2>/dev/null || echo "unknown")"

    echo "" >&2
    cat "$SNAPSHOT_FILE" | head -50 | sed 's/^/  /' >&2
    echo "" >&2
}

print_execution_summary() {
    log_step "Restoration Summary"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE - No changes were made"
        log_info "To execute restoration, run:"
        log_info "  DRY_RUN=false $0 $SNAPSHOT_FILE"
    else
        log_info "Restoration execution complete"
        
        # Report any failures that occurred
        if [[ ${#FAILED_TAPS[@]} -gt 0 ]]; then
            log_warn "⚠ ${#FAILED_TAPS[@]} tap(s) failed to install:"
            for tap in "${FAILED_TAPS[@]}"; do
                log_warn "  - $tap"
            done
        fi
        
        if [[ ${#FAILED_PACKAGES[@]} -gt 0 ]]; then
            log_warn "⚠ Some Homebrew packages may have failed to install"
            log_info "Review the installation output above for details"
        fi
        
        if [[ ${#RESTORE_WARNINGS[@]} -gt 0 ]]; then
            log_warn "⚠ The following warnings occurred:"
            for warning in "${RESTORE_WARNINGS[@]}"; do
                log_warn "  - $warning"
            done
        fi
        
        # Only suggest review if there were actual issues
        if [[ ${#FAILED_TAPS[@]} -eq 0 && ${#FAILED_PACKAGES[@]} -eq 0 && ${#RESTORE_WARNINGS[@]} -eq 0 ]]; then
            log_info "✓ All restoration steps completed successfully"
        else
            log_info "Review the warnings and errors above for any manual remediation"
        fi
    fi

    echo "" >&2
    log_info "Next steps:"
    log_info "1. Review manual installations section below"
    log_info "2. Install applications from official sources"
    log_info "3. Verify all tools are working correctly"
    log_info "4. Restore user data and settings manually"
    echo "" >&2
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    # Parse arguments
    case "${1:-}" in
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            validate_snapshot_file
            ;;
    esac

    log_step "Starting freshMac System Restoration"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_warn "DRY RUN MODE: Showing what would be done (no changes made)"
    else
        log_warn "LIVE EXECUTION MODE: Making actual changes to your system"
    fi

    echo "" >&2

    # Print snapshot summary
    print_snapshot_summary

    # Execute restoration steps
    restore_homebrew_taps
    restore_homebrew_packages
    restore_manual_installs

    # Print summary
    print_execution_summary
}

main "$@"
