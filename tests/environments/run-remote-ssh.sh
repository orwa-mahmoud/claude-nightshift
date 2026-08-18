#!/usr/bin/env bash
# Cross an actual SSH transport, disconnect, reconnect, and emit one sanitized receipt.
set -euo pipefail

TARGET="${1:-}"
ROOT="${2:-$PWD}"
[ -n "$TARGET" ] || {
  printf 'usage: run-remote-ssh.sh SSH_TARGET [REMOTE_REPOSITORY_ROOT]\n' >&2
  exit 2
}
for command_name in ssh jq base64 tr; do
  command -v "$command_name" >/dev/null 2>&1 || {
    printf 'remote SSH fixture: missing prerequisite: %s\n' "$command_name" >&2
    exit 1
  }
done

encode() { printf '%s' "$1" | base64 | tr -d '\n'; }
root_b64="$(encode "$ROOT")"
fixture="$(ssh "$TARGET" 'mktemp -d /tmp/nightshift-environment.XXXXXX')"
fixture_b64="$(encode "$fixture")"

remote_helper() {
  ssh "$TARGET" \
    env "NIGHTSHIFT_ACTION=$1" "NIGHTSHIFT_ROOT_B64=$root_b64" \
      "NIGHTSHIFT_FIXTURE_B64=$fixture_b64" bash -s <<'REMOTE'
set -eu
root="$(printf '%s' "$NIGHTSHIFT_ROOT_B64" | base64 -d)"
fixture="$(printf '%s' "$NIGHTSHIFT_FIXTURE_B64" | base64 -d)"
exec bash "$root/tests/environments/disconnect-watchman.sh" \
  "$NIGHTSHIFT_ACTION" "$root" "$fixture"
REMOTE
}

cleanup_best_effort() { remote_helper cleanup >/dev/null 2>&1 || true; }
trap cleanup_best_effort EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

receipt="$(ssh "$TARGET" env "NIGHTSHIFT_ROOT_B64=$root_b64" bash -s <<'REMOTE'
set -eu
root="$(printf '%s' "$NIGHTSHIFT_ROOT_B64" | base64 -d)"
cd "$root"
exec tests/environments/probe.sh remote-ssh "$PWD"
REMOTE
)"

# `start` returns after nohup has detached the watchman. The command's SSH connection then closes;
# `verify` runs over a new connection and proves that the same remote process is still in place.
remote_helper start
remote_helper verify
remote_helper cleanup
trap - EXIT INT TERM

printf '%s' "$receipt" | jq '.checks.transportDisconnect = "pass"'
