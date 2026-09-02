#!/usr/bin/env bash
# minimal-python-dead-code.sh <project-dir> — pip-venv tree with vulture on PATH for dead-code fixtures.
set -euo pipefail
dest="${1:?usage: minimal-python-dead-code.sh <project-dir>}"
here="$(cd "$(dirname "$0")" && pwd)"
bash "$here/../../python/make-project.sh" "$dest" pip-venv
ln -sf "$here/fake-vulture.sh" "$dest/.venv/bin/vulture"
chmod +x "$dest/.venv/bin/vulture"
