#!/bin/bash

################################################################################
# freshMac: System Snapshot & Restoration Tool
# Entry point for capturing complete macOS application and environment state
#
# Usage: ./export.sh
# Generates: output/freshmac_snapshot.txt
################################################################################

set -euo pipefail

# ============================================================================
# Configuration & Paths
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DATA_DIR="${ROOT_DIR}/output/tmp"
OUTPUT_DIR="${ROOT_DIR}/output"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
FINAL_OUTPUT="${OUTPUT_DIR}/freshmac_snapshot.txt"

# Temporary files for stage outputs
TMP_APPS_RAW="${DATA_DIR}/apps_raw.txt"
TMP_BREW_STATE="${DATA_DIR}/brew_state.json"
TMP_RESOLVED="${DATA_DIR}/resolved.json"
TMP_ENRICHED="${DATA_DIR}/enriched.json"

# ============================================================================
# Utility Functions
# ============================================================================

# Ensure output directories exist
mkdir -p "${DATA_DIR}" "${OUTPUT_DIR}"

log_info() {
    echo "[INFO] $*" >&2
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

cleanup_temp() {
    # Remove temporary data files but keep them for debugging if needed
    log_info "Cleanup: Temporary files available in ${DATA_DIR}/ for inspection"
}

trap cleanup_temp EXIT

# ============================================================================
# STEP 1: System Snapshot Metadata
# ============================================================================

collect_system_info() {
    log_step "STEP 1: Collecting system metadata"

    local device_name=""
    local macos_version=""
    local macos_build=""
    local cpu_arch=""
    local snapshot_date=""
    local brew_version=""

    # Device name
    device_name=$(scutil --get ComputerName 2>/dev/null || echo "Unknown")

    # macOS version and build
    macos_version=$(sw_vers -productVersion 2>/dev/null || echo "Unknown")
    macos_build=$(sw_vers -buildVersion 2>/dev/null || echo "Unknown")

    # CPU architecture
    cpu_arch=$(uname -m)

    # Snapshot timestamp
    snapshot_date=$(date "+%Y-%m-%d %H:%M:%S %Z")

    # Homebrew version (optional, may not be installed)
    if command -v brew &>/dev/null; then
        brew_version=$(brew --version 2>/dev/null | head -1 || echo "Unknown")
    else
        brew_version="Not installed"
    fi

    log_info "Device: $device_name"
    log_info "macOS: $macos_version (Build: $macos_build)"
    log_info "CPU: $cpu_arch"
    log_info "Snapshot Date: $snapshot_date"
    log_info "Homebrew: $brew_version"

    cat > "${DATA_DIR}/system_info.txt" <<EOF
Device Name: $device_name
macOS Version: $macos_version
macOS Build: $macos_build
CPU Architecture: $cpu_arch
Snapshot Date: $snapshot_date
Homebrew Version: $brew_version
EOF
}

# ============================================================================
# STEP 2: Homebrew State Collection
# ============================================================================

collect_homebrew_state() {
    log_step "STEP 2: Collecting Homebrew state"

    if ! command -v brew &>/dev/null; then
        log_info "Homebrew not installed, skipping"
        # Ensure complete JSON schema even when Homebrew is absent
        echo '{"taps": [], "formulae": [], "casks": [], "brew_installable": [], "unresolved": []}' > "${TMP_BREW_STATE}"
        return 0
    fi

    local taps=()
    local formulae=()
    local casks=()

    # Collect taps using bash 3.2-compatible while/IFS read (no mapfile)
    log_info "Collecting Homebrew taps..."
    if command -v brew tap &>/dev/null; then
        while IFS= read -r tap; do
            [[ -n "$tap" ]] && taps+=("$tap")
        done < <(brew tap 2>/dev/null || true)
    fi

    # Collect formulae (regular packages) using bash 3.2-compatible while/IFS read
    log_info "Collecting installed Homebrew formulae..."
    if command -v brew list &>/dev/null; then
        while IFS= read -r formula; do
            [[ -n "$formula" ]] && formulae+=("$formula")
        done < <(brew list --formulae 2>/dev/null || true)
    fi

    # Collect casks using bash 3.2-compatible while/IFS read
    log_info "Collecting installed Homebrew casks..."
    if command -v brew list &>/dev/null; then
        while IFS= read -r cask; do
            [[ -n "$cask" ]] && casks+=("$cask")
        done < <(brew list --casks 2>/dev/null || true)
    fi

    log_info "Found ${#taps[@]} taps, ${#formulae[@]} formulae, ${#casks[@]} casks"

    # Collect first, write once - single Python invocation for better performance
    # Pass arrays separated by markers so Python can reconstruct them
    python3 - "${TMP_BREW_STATE}" "${taps[@]:-}" "@FORMULAE_SEP@" "${formulae[@]:-}" "@CASKS_SEP@" "${casks[@]:-}" <<'PYTHON_EOF'
import json
import sys

brew_state_file = sys.argv[1]
args = sys.argv[2:]

# Parse args: taps, @FORMULAE_SEP@, formulae, @CASKS_SEP@, casks
taps = []
formulae = []
casks = []
current_list = taps

for arg in args:
    if arg == "@FORMULAE_SEP@":
        current_list = formulae
    elif arg == "@CASKS_SEP@":
        current_list = casks
    else:
        current_list.append(arg)

# Filter out empty strings
taps = [t for t in taps if t]
formulae = [f for f in formulae if f]
casks = [c for c in casks if c]

# Create complete JSON schema with all required keys
# Include brew_installable and unresolved (will be filled by enrichment)
brew_state = {
    "taps": taps,
    "formulae": formulae,
    "casks": casks,
    "brew_installable": [],
    "unresolved": []
}

with open(brew_state_file, 'w') as f:
    json.dump(brew_state, f, indent=2)
PYTHON_EOF

    log_info "Homebrew state saved to ${TMP_BREW_STATE}"
}

# ============================================================================
# STEP 3: Language Ecosystems
# ============================================================================

collect_language_ecosystems() {
    log_step "STEP 3: Collecting language ecosystem information"

    local node_version=""
    local node_packages=()
    local python_version=""
    local python_packages=()
    local java_versions=()

    # Node.js & npm
    if command -v node &>/dev/null; then
        node_version=$(node --version 2>/dev/null || echo "Unknown")
        if command -v npm &>/dev/null; then
            # Use while/IFS read instead of mapfile (bash 3.2 compatibility)
            # npm may legitimately have no global packages - guard against error exit
            while IFS= read -r pkg; do
                [[ -n "$pkg" && "$pkg" != "npm" ]] && node_packages+=("$pkg")
            done < <(npm list -g --depth=0 2>/dev/null | grep -v "npm" | grep -v "^$" || true)
        fi
        log_info "Node: $node_version, Packages: ${#node_packages[@]}"
    else
        log_info "Node.js not installed"
    fi

    # Python
    if command -v python3 &>/dev/null; then
        python_version=$(python3 --version 2>/dev/null || echo "Unknown")
        if command -v pip3 &>/dev/null; then
            # Guard pip3 which may have no user packages but still exits cleanly
            # Use while/IFS read instead of mapfile (bash 3.2 compatibility)
            while IFS= read -r pkg; do
                [[ -n "$pkg" ]] && python_packages+=("$pkg")
            done < <(pip3 list --user 2>/dev/null | tail -n +3 | awk '{print $1}' || true)
        fi
        log_info "Python: $python_version, Packages: ${#python_packages[@]}"
    else
        log_info "Python 3 not installed"
    fi

    # Java JDKs - improved detection with /usr/libexec/java_home fallback
    local java_home_output
    if java_home_output=$(/usr/libexec/java_home -V 2>&1 | tail -n +2 | awk '{print $NF}') && [[ -n "$java_home_output" ]]; then
        # java_home returned JDK info
        while IFS= read -r jdk; do
            [[ -n "$jdk" ]] && java_versions+=("$jdk")
        done < <(echo "$java_home_output")
    elif [[ -d "/Library/Java/JavaVirtualMachines" ]]; then
        # Fallback to directory listing
        while IFS= read -r jdk; do
            [[ -n "$jdk" ]] && java_versions+=("$jdk")
        done < <(ls /Library/Java/JavaVirtualMachines 2>/dev/null || true)
    fi
    [[ ${#java_versions[@]} -gt 0 ]] && log_info "Java JDKs: ${#java_versions[@]}" || log_info "No Java JDKs found"

    # Store in text file for inspection
    cat > "${DATA_DIR}/ecosystems.txt" <<EOF
Node.js Version: $node_version
Node.js Global Packages: ${#node_packages[@]}
$(printf '%s\n' "${node_packages[@]}" | head -20)

Python Version: $python_version
Python User Packages: ${#python_packages[@]}
$(printf '%s\n' "${python_packages[@]}" | head -20)

Java JDKs:
$(printf '%s\n' "${java_versions[@]}")
EOF
}

# ============================================================================
# STEP 4: Application Discovery
# ============================================================================

collect_applications() {
    log_step "STEP 4: Discovering installed applications"

    : > "${TMP_APPS_RAW}"  # Clear the file

    local app_count=0

    log_info "Scanning /Applications directory..."
    while IFS= read -r -d '' app_path; do
        local app_name
        app_name=$(basename "$app_path" .app)
        echo "$app_name" >> "${TMP_APPS_RAW}"
        ((app_count++))
    done < <(find /Applications -maxdepth 1 -type d -name "*.app" -print0 2>/dev/null || true)

    log_info "Found $app_count applications"
    log_info "Raw app list written to ${TMP_APPS_RAW}"
}

# ============================================================================
# STEP 5: Brew Resolution (Python)
# ============================================================================

resolve_with_brew() {
    log_step "STEP 5: Resolving applications with Homebrew"

    if [[ ! -f "${TMP_APPS_RAW}" ]]; then
        log_error "Raw app list not found at ${TMP_APPS_RAW}"
        return 1
    fi

    local resolver_path="${ROOT_DIR}/pipeline/resolver.py"
    if [[ ! -f "${resolver_path}" ]]; then
        log_error "resolver.py not found at ${resolver_path}"
        return 1
    fi

    # Pass paths and brew state to resolver
    python3 "${resolver_path}" \
        --apps-raw "${TMP_APPS_RAW}" \
        --brew-state "${TMP_BREW_STATE}" \
        --output "${TMP_RESOLVED}"

    if [[ ! -f "${TMP_RESOLVED}" ]]; then
        log_error "Resolver failed to produce output"
        return 1
    fi

    log_info "Brew resolution complete. Output: ${TMP_RESOLVED}"
}

# ============================================================================
# STEP 6: Manual Enrichment (Python)
# ============================================================================

enrich_unresolved() {
    log_step "STEP 6: Enriching unresolved applications with vendor sources"

    if [[ ! -f "${TMP_RESOLVED}" ]]; then
        log_error "Resolved JSON not found at ${TMP_RESOLVED}"
        return 1
    fi

    local enrich_path="${ROOT_DIR}/pipeline/enrich.py"
    if [[ ! -f "${enrich_path}" ]]; then
        log_error "enrich.py not found at ${enrich_path}"
        return 1
    fi

    python3 "${enrich_path}" \
        --resolved "${TMP_RESOLVED}" \
        --output "${TMP_ENRICHED}"

    if [[ ! -f "${TMP_ENRICHED}" ]]; then
        log_error "Enrichment failed to produce output"
        return 1
    fi

    log_info "Enrichment complete. Output: ${TMP_ENRICHED}"
}

# ============================================================================
# Final Output Generation
# ============================================================================

generate_final_output() {
    log_step "STEP 7: Generating final snapshot file"

    : > "${FINAL_OUTPUT}"  # Clear the file

    cat >> "${FINAL_OUTPUT}" <<EOF
================================================================================
                         freshMac System Snapshot
================================================================================
Generated: $(date "+%Y-%m-%d %H:%M:%S")
Tool Version: 1.0

This file contains a complete snapshot of your macOS system's applications
and development environment. Use restore.sh to rebuild your system after reset.

================================================================================
SYSTEM INFORMATION
================================================================================
EOF

    if [[ -f "${DATA_DIR}/system_info.txt" ]]; then
        cat "${DATA_DIR}/system_info.txt" >> "${FINAL_OUTPUT}"
    fi

    # Consolidate all JSON extraction into a single Python call for efficiency
    python3 - "${TMP_BREW_STATE}" "${TMP_ENRICHED}" >> "${FINAL_OUTPUT}" <<'PYTHON_EOF'
import json
import sys
import os

brew_state_file = sys.argv[1]
enriched_file = sys.argv[2]

# Load brew state
brew_state = {}
if os.path.exists(brew_state_file):
    try:
        with open(brew_state_file, 'r') as f:
            brew_state = json.load(f)
    except:
        brew_state = {"taps": [], "formulae": [], "casks": [], "brew_installable": [], "unresolved": []}
else:
    brew_state = {"taps": [], "formulae": [], "casks": [], "brew_installable": [], "unresolved": []}

# Load enriched data
enriched_data = {}
if os.path.exists(enriched_file):
    try:
        with open(enriched_file, 'r') as f:
            enriched_data = json.load(f)
    except:
        enriched_data = {"brew_installable": [], "unresolved": []}
else:
    enriched_data = {"brew_installable": [], "unresolved": []}

# Output HOMEBREW TAPS section
print("\n================================================================================")
print("HOMEBREW TAPS")
print("================================================================================")
taps = brew_state.get('taps', [])
if taps:
    for tap in taps:
        print(tap)
else:
    print("(No taps found)")

# Output BREW-INSTALLABLE APPLICATIONS section
print("\n================================================================================")
print("BREW-INSTALLABLE APPLICATIONS & TOOLS")
print("================================================================================")
brew_installable = enriched_data.get('brew_installable', [])
if brew_installable:
    for item in brew_installable:
        command = item.get('command', '')
        if command:
            print(f"  {command}")
else:
    print("(No brew-installable apps found)")

# Output HOMEBREW RESTORE COMMAND section
print("\n================================================================================")
print("HOMEBREW RESTORE COMMAND (All-in-one)")
print("================================================================================")
formulae = brew_state.get('formulae', [])
casks = brew_state.get('casks', [])

if formulae:
    print(f"brew install {' '.join(formulae)}")
if casks:
    print(f"brew install --cask {' '.join(casks)}")

if not formulae and not casks:
    print("(No brew packages or casks to install)")

# Output MANUAL INSTALLATIONS section
print("\n================================================================================")
print("MANUAL INSTALLATIONS WITH OFFICIAL SOURCES")
print("================================================================================")
unresolved = enriched_data.get('unresolved', [])
if unresolved:
    for item in unresolved:
        app_name = item.get('app', 'Unknown')
        url = item.get('official_download_url', 'Not found')
        confidence = item.get('confidence', 'low')
        print(f"\n{app_name}")
        print(f"  Source: {url}")
        print(f"  Confidence: {confidence}")
else:
    print("(No unresolved applications)")
PYTHON_EOF

    cat >> "${FINAL_OUTPUT}" <<EOF

================================================================================
LANGUAGE ECOSYSTEMS
================================================================================
EOF

    if [[ -f "${DATA_DIR}/ecosystems.txt" ]]; then
        cat "${DATA_DIR}/ecosystems.txt" >> "${FINAL_OUTPUT}"
    fi

    cat >> "${FINAL_OUTPUT}" <<EOF

================================================================================
SNAPSHOT METADATA
================================================================================
Data Directory: ${DATA_DIR}
Output File: ${FINAL_OUTPUT}
Generated: $(date "+%Y-%m-%d %H:%M:%S %Z")

For restoration instructions, see restore.sh
================================================================================
EOF

    log_info "Final snapshot generated: ${FINAL_OUTPUT}"
}

# ============================================================================
# Main Execution
# ============================================================================

main() {
    log_step "Starting freshMac System Snapshot"
    log_info "Output directory: ${OUTPUT_DIR}"
    log_info "Data directory: ${DATA_DIR}"

    # Verify Python is available
    if ! command -v python3 &>/dev/null; then
        log_error "Python 3 is required but not found"
        exit 1
    fi

    # Execute critical steps in sequence
    collect_system_info || { log_error "Failed to collect system info"; exit 1; }
    collect_homebrew_state || { log_error "Failed to collect Homebrew state"; exit 1; }
    
    # Non-critical collection steps (continue even if fails)
    collect_language_ecosystems || log_info "Warning: Some language ecosystem data may be incomplete"
    collect_applications || { log_error "Failed to discover applications"; exit 1; }
    
    # Enrichment steps
    resolve_with_brew || { log_error "Failed to resolve with Homebrew"; exit 1; }
    enrich_unresolved || { log_error "Failed to enrich unresolved apps"; exit 1; }
    
    # Final output generation
    generate_final_output || { log_error "Failed to generate final output"; exit 1; }

    log_step "✓ Snapshot Complete"
    echo ""
    echo "Snapshot saved to: ${FINAL_OUTPUT}"
    echo ""
    echo "Next steps:"
    echo "  1. Review the snapshot file: cat ${FINAL_OUTPUT}"
    echo "  2. Use restore.sh to rebuild your system after reset"
    echo ""
}

main "$@"
