#!/usr/bin/env python3
"""
enrich.py: Vendor Enrichment Engine
Enriches unresolved apps with official vendor download sources
"""
import json
import sys
import argparse
from pathlib import Path

# Minimal vendor mapping for common apps
VENDOR_MAP = {
    'github-desktop': 'https://desktop.github.com',
    'visual-studio-code': 'https://code.visualstudio.com',
    'chrome': 'https://www.google.com/chrome',
    'firefox': 'https://www.mozilla.org/firefox',
    'vlc': 'https://www.videolan.org',
    'discord': 'https://discord.com/download',
    'telegram': 'https://telegram.org',
    'whatsapp': 'https://www.whatsapp.com/download',
    'slack': 'https://slack.com/downloads',
    'zoom': 'https://zoom.us/download',
}

def main():
    parser = argparse.ArgumentParser(description='Enrich unresolved apps with vendor sources')
    parser.add_argument('--resolved', required=True, help='Resolved JSON from resolver')
    parser.add_argument('--output', required=True, help='Output enriched JSON')
    args = parser.parse_args()

    unresolved = []
    
    if Path(args.resolved).exists():
        with open(args.resolved) as f:
            data = json.load(f)
        
        unresolved = data.get('unresolved', [])
        
        # Enrich with vendor sources
        for item in unresolved:
            norm = item.get('normalized', '').lower()
            if norm in VENDOR_MAP:
                item['official_download_url'] = VENDOR_MAP[norm]
                item['confidence'] = 'high'
            else:
                item['official_download_url'] = 'Not found'
                item['confidence'] = 'low'
    
    output = {'unresolved': sorted(unresolved, key=lambda x: x.get('app', ''))}
    
    with open(args.output, 'w') as f:
        json.dump(output, f, indent=2)

if __name__ == '__main__':
    main()
