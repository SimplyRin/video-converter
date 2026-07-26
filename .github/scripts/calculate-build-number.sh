#!/usr/bin/env bash

set -euo pipefail

revision="${1:-HEAD}"
git rev-parse --verify "${revision}^{commit}" >/dev/null

LC_ALL=C git log "${revision}" --format=tformat: --numstat |
    awk '$1 ~ /^[0-9]+$/ { additions += $1 } END { print additions + 0 }'
