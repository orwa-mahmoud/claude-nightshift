#!/usr/bin/env bash
# Transaction and baseline builders for tests/provision-recover.bats.
#
# These write the same documents runtime/provision.py writes: the pretty transaction at
# .nightshift/provision-transaction.json and the blob store beside it, keyed by the sha256 of
# the normalized relative path. Kept in a file so no test spells a state write as an inline
# command string, and so the native helper is read against real bytes rather than a hand-typed
# approximation.

recover_sha256_stdin() {
  local line
  if command -v sha256sum >/dev/null 2>&1; then
    line="$(sha256sum)"
  else
    line="$(shasum -a 256)"
  fi
  printf '%s' "${line%% *}"
}

recover_sha256_file() { recover_sha256_stdin <"$1"; }

# capture_baseline names each blob by the digest of the relative path it came from.
recover_blob_id() { printf '%s' "$1" | recover_sha256_stdin; }

recover_b64_file() { base64 <"$1" | tr -d '\n'; }

recover_store() { printf '%s' "$1/.nightshift/provision-baseline"; }

recover_tx_path() { printf '%s' "$1/.nightshift/provision-transaction.json"; }

# recover_reset — begin a fresh transaction description.
recover_reset() {
  RECOVER_ENTRIES=""
  RECOVER_TOUCHED=""
  RECOVER_CAPABILITY="fixture-recover"
}

# recover_keep <project> <target> <rel> <blob|content|both|orphan|none>
#
# Record <rel> as a file that existed when apply started, capturing its current bytes.
#   blob    the blob file, and a null content field
#   content the base64 content field, and a null blob field
#   both    what provision.py writes: the blob file and the content field
#   orphan  a blob id whose file is gone, plus the content field — a half-cleared store
#   none    neither, so nothing can be restored from the record
recover_keep() {
  local project="$1" target="$2" rel="$3" how="$4"
  local digest blob file content="" store entry
  file="$target/$rel"
  store="$(recover_store "$project")"
  digest="$(recover_sha256_file "$file")"
  blob="$(recover_blob_id "$rel")"
  case "$how" in
    blob | both)
      mkdir -p "$store"
      cp "$file" "$store/$blob"
      ;;
  esac
  case "$how" in
    content | both | orphan) content="$(recover_b64_file "$file")" ;;
  esac
  case "$how" in
    content | none) blob="" ;;
  esac
  entry="$(jq -nc --arg rel "$rel" --arg digest "$digest" --arg blob "$blob" \
    --arg content "$content" '{
      ($rel): {
        existed: true,
        digest: $digest,
        blob: (if $blob == "" then null else $blob end),
        content: (if $content == "" then null else $content end)
      }
    }')"
  RECOVER_ENTRIES="$RECOVER_ENTRIES$entry"
}

# recover_new <rel> — record <rel> as a path the install created.
recover_new() {
  local entry
  entry="$(jq -nc --arg rel "$1" \
    '{($rel): {existed: false, digest: null, blob: null, content: null}}')"
  RECOVER_ENTRIES="$RECOVER_ENTRIES$entry"
}

# recover_touch <rel> — add <rel> to the transaction's touched list.
recover_touch() {
  RECOVER_TOUCHED="$RECOVER_TOUCHED$1
"
}

# recover_write_tx <project> <target> <stage> <true|false> [recipe-path]
recover_write_tx() {
  local project="$1" target="$2" stage="$3" failed="$4" recipe="${5:-}"
  local baseline touched
  baseline="$(printf '%s' "$RECOVER_ENTRIES" | jq -sc 'add // {}')"
  touched="$(printf '%s' "$RECOVER_TOUCHED" | jq -Rsc 'split("\n") | map(select(length > 0))')"
  jq -n -S --indent 2 \
    --arg stage "$stage" \
    --arg cap "$RECOVER_CAPABILITY" \
    --arg target "$target" \
    --arg recipe "$recipe" \
    --argjson failed "$failed" \
    --argjson baseline "$baseline" \
    --argjson touched "$touched" '{
      schemaVersion: 1,
      stage: $stage,
      capabilityId: $cap,
      recipePath: (if $recipe == "" then null else $recipe end),
      recipeVersion: "1",
      workTarget: $target,
      allowedFiles: ($baseline | keys),
      baseline: $baseline,
      gitPorcelain: [],
      touched: $touched,
      failed: $failed,
      lastError: null,
      setupCommit: "",
      startedAt: "2026-09-02T00:00:00Z",
      updatedAt: "2026-09-02T00:00:00Z"
    }' >"$(recover_tx_path "$project")"
}
