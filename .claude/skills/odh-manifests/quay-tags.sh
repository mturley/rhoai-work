#!/usr/bin/env bash
# Fetch and filter recent meaningful tags from a Quay repository.
# Usage: quay-tags.sh [repo] [limit]
#   repo:  quay.io repository path (default: opendatahub/odh-dashboard)
#   limit: max tags to fetch from API (default: 100)
# Outputs tab-separated: tag_name\tlast_modified
set -euo pipefail

REPO="${1:-opendatahub/odh-dashboard}"
LIMIT="${2:-100}"

curl -sf "https://quay.io/api/v1/repository/${REPO}/tag/?limit=${LIMIT}&onlyActiveTags=true" | python3 -c "
import json, sys, re

data = json.load(sys.stdin)
tags = data.get('tags', [])

skip_suffixes = ['.sig', '.sbom', '.att', '.src', '.dockerfile', '.git']
skip_patterns = [
    r'^sha256-',
    r'build-image',
    r'-linux-x86',
    r'-linux-aarch',
    r'^[0-9a-f]{40}$',
]

for t in tags:
    name = t.get('name', '')
    if any(name.endswith(s) for s in skip_suffixes):
        continue
    if any(re.search(p, name) for p in skip_patterns):
        continue
    modified = t.get('last_modified', '')
    print(f'{name}\t{modified}')
"
