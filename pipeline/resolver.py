#!/usr/bin/env python3
"""
resolver.py: Homebrew Resolution Engine
Resolves application names to Homebrew formulae/casks
"""
import json
import sys
import subprocess
import argparse
from pathlib import Path

def get_brew_list():
    """Get list of available Homebrew formulae and casks"""
    try:
        formulae = set(subprocess.check_output(['brew', 'formulae'], text=True).strip().split('\n'))
        casks = set(subprocess.check_output(['brew', 'casks'], text=True).strip().split('\n'))
        return formulae | casks
    except:
        return set()

def normalize_name(name):
    """Normalize app name for matching"""
    return name.lower().replace(' ', '-').replace('_', '-')

def main():
    parser = argparse.ArgumentParser(description='Resolve apps to Homebrew packages')
    parser.add_argument('--apps-raw', required=True, help='Raw apps list file')
    parser.add_argument('--brew-state', required=True, help='Homebrew state JSON')
    parser.add_argument('--output', required=True, help='Output JSON file')
    args = parser.parse_args()

    brew_available = get_brew_list()
    
    resolved = []
    unresolved = []
    
    # Read raw apps
    if Path(args.apps_raw).exists():
        with open(args.apps_raw) as f:
            apps = [line.strip() for line in f if line.strip()]
        
        for app in apps:
            norm = normalize_name(app)
            if norm in brew_available:
                resolved.append({'app': app, 'command': norm})
            else:
                unresolved.append({'app': app, 'normalized': norm})
    
    output = {
        'brew_installable': resolved,
        'unresolved': unresolved
    }
    
    with open(args.output, 'w') as f:
        json.dump(output, f, indent=2)

if __name__ == '__main__':
    main()
