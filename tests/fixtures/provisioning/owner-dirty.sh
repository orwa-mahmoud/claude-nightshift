#!/usr/bin/env bash
# owner-dirty.sh <project-dir> [filename] — writes an owner file outside any recipe's
# allowedFiles, as if the owner was mid-edit when the shift started. Auto-add, its rollback,
# and its recovery must never touch it. A script, not an inline command, so authoring this
# fixture never types a shift-control filename into a bash command string.
set -euo pipefail
target="${1:?usage: owner-dirty.sh <project-dir> [filename]}"
name="${2:-owner-live-edit.txt}"
printf 'owner in-progress edit — do not touch\n' >"$target/$name"
