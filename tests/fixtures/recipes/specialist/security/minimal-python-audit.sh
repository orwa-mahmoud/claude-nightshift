#!/usr/bin/env bash
# minimal-python-audit.sh <project-dir> — pip-venv tree with pip-audit on PATH for security fixtures.
set -euo pipefail
dest="${1:?usage: minimal-python-audit.sh <project-dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../../python/make-project.sh" "$dest" pip-venv
ln -sf "$here/fake-pip-audit.sh" "$dest/.venv/bin/pip-audit"
chmod +x "$dest/.venv/bin/pip-audit"
