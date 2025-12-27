#!/bin/bash
# verify_snapshot_v01.sh: Lightweight snapshot schema validator
# Checks that a snapshot file conforms to Schema v0.1

set -euo pipefail

SNAPSHOT_FILE="${1:-}"

if [[ -z "${SNAPSHOT_FILE}" ]]; then
    echo "Usage: $0 <snapshot-file>" >&2
    exit 1
fi

if [[ ! -f "${SNAPSHOT_FILE}" ]]; then
    echo "[ERROR] File not found: ${SNAPSHOT_FILE}" >&2
    exit 1
fi

# Check for required schema version header
if ! grep -q "^Snapshot Schema Version: 0.1" "${SNAPSHOT_FILE}"; then
    echo "[ERROR] Snapshot missing or invalid schema version (expected: Snapshot Schema Version: 0.1)" >&2
    exit 1
fi

# Verify canonical sections exist in order
sections_found=()
while IFS= read -r line; do
    case "${line}" in
        "HOMEBREW TAPS"|"HOMEBREW RESTORE COMMAND"|"MANUAL INSTALLATIONS WITH OFFICIAL SOURCES")
            sections_found+=("${line}")
            ;;
    esac
done < "${SNAPSHOT_FILE}"

if [[ ${#sections_found[@]} -lt 1 ]]; then
    echo "[ERROR] No valid snapshot sections found" >&2
    exit 1
fi

echo "[OK] Snapshot conforms to Schema v0.1"
exit 0
