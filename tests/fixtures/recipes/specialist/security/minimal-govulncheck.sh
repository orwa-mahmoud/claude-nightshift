#!/usr/bin/env bash
# minimal-govulncheck.sh <project-dir> — smallest Go module for govulncheck fixtures.
set -euo pipefail
dest="${1:?usage: minimal-govulncheck.sh <project-dir>}"
bash "$(cd "$(dirname "$0")" && pwd)/../../go/minimal-module.sh" "$dest"
