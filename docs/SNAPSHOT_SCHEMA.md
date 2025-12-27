# Snapshot Schema v0.1

**Status:** Frozen (format stable, implementation in alpha)  
**Effective:** 2025

---

## Format Overview

FreshMac snapshots are plain-text, human-readable files that capture system state for restoration after macOS reset.

- **Encoding:** UTF-8
- **Line Endings:** Unix (LF)
- **Structure:** Plain text with section separators and key-value pairs

---

## Header (Required)

Every snapshot begins with metadata:

```
================================================================================
freshMac Snapshot
Generated: YYYY-MM-DD HH:MM:SS
Tool Version: 1.0
Snapshot Schema Version: 0.1

Device: <device name>
macOS: <version>
CPU: <architecture>
Homebrew: <version or "Not installed">
================================================================================
```

---

## Canonical Sections

Snapshots contain exactly these sections in order:

### 1. HOMEBREW TAPS

```
================================================================================
HOMEBREW TAPS
================================================================================
<tap1>
<tap2>
...
```

Required Homebrew taps, one per line. If no taps: `(No taps found)`

---

### 2. HOMEBREW RESTORE COMMAND

```
================================================================================
HOMEBREW RESTORE COMMAND
================================================================================
brew install <formula1> <formula2> ...
brew install --cask <cask1> <cask2> ...
```

Executable Homebrew restore commands. If no packages: `(No packages to install)`

---

### 3. MANUAL INSTALLATIONS WITH OFFICIAL SOURCES

```
================================================================================
MANUAL INSTALLATIONS WITH OFFICIAL SOURCES
================================================================================

App: <name>
Source: <URL or "Not found">
Reason: <explanation>

App: <name>
Source: <URL>
Reason: <explanation>
```

Applications not available via Homebrew. If none: `(No manual installations required)`

---

## Validation Rules

**export.sh must:**
- Emit all mandatory header fields
- Include all three canonical sections in order
- Use 80 equals signs for separators
- Sort all lists alphabetically

**restore.sh must:**
- Validate schema version exactly matches `0.1`
- Only execute `brew install` or `brew install --cask` commands
- Treat manual installation sources as informational (no auto-download)
- Default to DRY_RUN (safe preview mode)

---

## Example Snapshot

```
================================================================================
freshMac Snapshot
Generated: 2025-12-26 22:57:54
Tool Version: 1.0
Snapshot Schema Version: 0.1

Device: John's MacBook Air
macOS: 14.2.1
CPU: arm64
Homebrew: Homebrew 4.2.0
================================================================================

================================================================================
HOMEBREW TAPS
================================================================================
mongodb/brew

================================================================================
HOMEBREW RESTORE COMMAND
================================================================================
brew install git node python
brew install --cask visual-studio-code

================================================================================
MANUAL INSTALLATIONS WITH OFFICIAL SOURCES
================================================================================

App: Adobe Photoshop
Source: https://www.adobe.com/downloads/photoshop
Reason: Not available in Homebrew

App: Microsoft Office
Source: https://www.microsoft.com/office/download
Reason: Not available in Homebrew
```

---

## Validation

To validate a snapshot file:

```bash
./bin/verify_snapshot_v01.sh output/freshmac_snapshot.txt
```

This checks:
- Schema version is exactly `0.1`
- Required sections are present

---

## Notes

- This schema is frozen for v0.1 and will not change
- Future versions (v0.2, v1.0) will have new version strings
- No auto-upgrade path exists; users must understand which schema version they have
