#!/usr/bin/env bash
# already-configured.sh <project-dir> <capability-id> — a module whose history already carries
# the setup commit for <capability-id>. That commit is how the engine recognizes a capability it
# has provisioned before, so this is the fixture for "repository tooling wins": the plan reports
# alreadyProvisioned and the apply skips without running a command.
set -euo pipefail
dir="${1:?usage: already-configured.sh <project-dir> <capability-id>}"
cap="${2:?usage: already-configured.sh <project-dir> <capability-id>}"
here="$(cd "$(dirname "$0")" && pwd)"

bash "$here/minimal-module.sh" "$dir"
git -C "$dir" commit -q --allow-empty -m "chore(tooling): $cap"
