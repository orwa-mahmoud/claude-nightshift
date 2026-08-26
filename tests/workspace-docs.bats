load helpers

ROOT="$BATS_TEST_DIRNAME/.."
DOC="$ROOT/docs/how-it-works.md"
LIB="$ROOT/plugins/nightshift/lib/lib.sh"
LINKER="$ROOT/plugins/nightshift/runtime/link-workspace.sh"

resolve_workspace() {
  bash -c '. "$1"; ns_workspace_root "$2"' _ "$LIB" "$1"
}

resolve_work_target() {
  bash -c '. "$1"; ns_work_target "$2"' _ "$LIB" "$1"
}

@test "workspace docs cover every supported and refused layout" {
  for heading in \
    'Repository root (supported)' \
    'Parent with one repository (supported)' \
    'Git worktree (supported)' \
    'Parent with several repositories (selection required)' \
    'Linked task root (explicit opt-in)'; do
    grep -qF "### $heading" "$DOC" || {
      echo "missing workspace example: $heading"
      return 1
    }
  done

  grep -qF '.nightshift/work-target' "$DOC"
  grep -qF 'plugins/<name>/' "$DOC"
  grep -qF 'Start refuses to arm' "$DOC"
  grep -qF 'Nightshift never selects the first directory silently' "$DOC"
}

@test "workspace docs state the link trust boundary" {
  contents="$(tr '\n' ' ' <"$DOC")"
  printf '%s' "$contents" | grep -qF 'This file is a trust boundary'
  printf '%s' "$contents" | grep -qF 'regular file—not a symlink'
  printf '%s' "$contents" | grep -qF 'exactly one absolute path'
  printf '%s' "$contents" | grep -qF 'targets without `.nightshift/`'
  printf '%s' "$contents" | grep -qF 'The link does not choose the code repository'
}

@test "documented repository and parent layouts match the resolver" {
  repo="$(new_project direct)"
  run resolve_work_target "$repo"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$repo" rev-parse --show-toplevel)" ]

  workspace="$(new_workspace parent)"
  run resolve_work_target "$workspace"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$workspace/repo" rev-parse --show-toplevel)" ]

  add_repo "$workspace" second
  run resolve_work_target "$workspace"
  [ "$status" -eq 2 ]

  bash -c '. "$1"; ns_record_work_target "$2" "$3"' \
    _ "$LIB" "$workspace" "$workspace/second"
  run resolve_work_target "$workspace"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$workspace/second" rev-parse --show-toplevel)" ]
}

@test "an opened worktree resolves to that worktree" {
  repo="$(new_project worktree-source)"
  worktree="$BATS_TEST_TMPDIR/feature-worktree"
  git -C "$repo" worktree add -q -b workspace-docs-test "$worktree"
  mkdir -p "$worktree/.nightshift"

  run resolve_work_target "$worktree"
  [ "$status" -eq 0 ]
  [ "$output" = "$(git -C "$worktree" rev-parse --show-toplevel)" ]
  [ -f "$worktree/.git" ]
}

@test "the explicit link resolves state without selecting the work target" {
  host="$(new_project host)"
  workspace="$(new_workspace linked)"
  bash "$LINKER" --host-root "$host" --workspace "$workspace" >/dev/null

  run resolve_workspace "$host"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cd -P "$workspace" && pwd)" ]
  [ ! -e "$workspace/.nightshift/work-target" ]

  printf 'relative/path\n' >"$host/.nightshift-link"
  run resolve_workspace "$host"
  [ "$status" -eq 2 ]
}
