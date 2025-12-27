# FreshMac

A macOS system snapshot and restore assistant.

## Overview

FreshMac captures and restores macOS system state: installed Homebrew packages, environment configurations, and user preferences. Useful for backup, system migration, or documenting current configuration.

## Status

**Alpha.** Tested on Apple Silicon (M1+) and Intel Macs running recent macOS. Do not rely on this for critical data without independent verification.

## Usage

### Snapshot
```bash
./bin/export.sh
```
Generates `output/freshmac_snapshot.txt` containing package list and configuration state.

### Preview Changes
```bash
DRY_RUN=1 ./bin/export.sh
```
Show snapshot without writing to file.

### Restore
```bash
./bin/restore.sh --snapshot output/freshmac_snapshot.txt
```
Installs packages and restores configurations from snapshot.

## Structure

- `bin/` - Snapshot export and restore scripts
- `pipeline/` - Package resolution and vendor enrichment utilities
- `docs/` - Technical specifications (SNAPSHOT_SCHEMA.md)
- `output/` - Snapshot files and working data

## Snapshot Format

See [docs/SNAPSHOT_SCHEMA.md](docs/SNAPSHOT_SCHEMA.md) for schema definition (v0.1).

## Limitations

- Homebrew-only (no macOS system settings)
- Snapshots capture installed packages, not configurations
- Vendor enrichment is best-effort (may fail for private packages)
- No support for cask or mas package managers

## Requirements

- macOS 10.15+
- Homebrew installed
- Python 3.8+
- Bash 3.2+

- **Snapshots** your installed Homebrew packages and taps
- **Resolves** discovered applications to Homebrew packages where available
- **Enriches** unresolved applications with official vendor download sources
- **Guides** safe restoration after a macOS reset

## What it does not do

- No uninstalling or cleanup of your system
- No automatic installation of manually-tracked applications
- No system modifications by default (dry-run safe)
- No guarantees of full automation; manual review and intervention remain necessary

## Quick Start

```bash
# Generate a snapshot of your system
./bin/export.sh

# Preview restoration (safe, non-destructive)
DRY_RUN=true ./bin/restore.sh output/freshmac_snapshot.txt

# Execute restoration (only after reviewing preview)
DRY_RUN=false ./bin/restore.sh output/freshmac_snapshot.txt

# Validate snapshot schema (optional)
./bin/verify_snapshot_v01.sh output/freshmac_snapshot.txt
```

## Snapshot Format

Snapshots are plain-text, version-controlled files with a frozen schema.

**Schema Version:** v0.1 (frozen)

**Canonical Sections:**
1. HOMEBREW TAPS — Required taps for your formulae
2. HOMEBREW RESTORE COMMAND — One or two `brew install` commands
3. MANUAL INSTALLATIONS WITH OFFICIAL SOURCES — Apps not in Homebrew

Snapshots are human-readable and can be version-controlled. See [docs/SNAPSHOT_SCHEMA.md](docs/SNAPSHOT_SCHEMA.md) for the complete specification.

## Safety Model

- **DRY_RUN defaults to true** — Preview mode shows what restore would do, with no changes
- **Only `brew install` and `brew install --cask` are executed** — No arbitrary shell commands
- **Manual installs are informational only** — Vendor download links are provided; you decide whether to install
- **Deterministic outputs** — Same inputs always produce identical snapshots

## Requirements

- macOS 10.13 or later
- Bash 3.2+ (system default)
- Python 3.6+ (optional, for app resolution and enrichment)
- Homebrew (optional, for package restore)

## Architecture

- **bin/export.sh** — Collects system state and generates snapshot
- **bin/restore.sh** — Validates snapshot and guides restoration
- **bin/verify_snapshot_v01.sh** — Lightweight schema validator
- **pipeline/resolver.py** — Resolves app names to Homebrew packages
- **pipeline/enrich.py** — Enriches unresolved apps with vendor sources

## Project Status

**Alpha** — Schema v0.1 is frozen and stable; implementation continues to improve.

Not yet v1.0. Behavior may refine in minor updates without changing the schema contract.

## Documentation

- [docs/SNAPSHOT_SCHEMA.md](docs/SNAPSHOT_SCHEMA.md) — Snapshot format specification
