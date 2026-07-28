#!/usr/bin/env bash
# release-notes.sh <version> <title-file> <notes-file>
#
# Pull one version's section out of CHANGELOG.md: the heading, minus its "## ", becomes the
# release title; the body becomes the notes. Exits non-zero when there is no such section.
#
# Both CI jobs read the changelog through here — the pull-request gate that demands an entry and
# the release job that publishes one — so they can never disagree about what counts as an entry.
set -eu

version="${1:?usage: release-notes.sh <version> <title-file> <notes-file>}"
title_out="${2:?usage: release-notes.sh <version> <title-file> <notes-file>}"
notes_out="${3:?usage: release-notes.sh <version> <title-file> <notes-file>}"
changelog="$(dirname "$0")/../CHANGELOG.md"

: >"$title_out"
awk -v v="$version" -v t="$title_out" '
  $0 ~ "^## v" v "([ \t]|$)" { on = 1; sub(/^## /, ""); print > t; next }
  on && /^## v/ { exit }
  on { print }
' "$changelog" >"$notes_out"

[ -s "$title_out" ] || {
  printf 'CHANGELOG.md has no "## v%s" section — add one before releasing %s\n' "$version" "$version" >&2
  exit 1
}

# Trim the blank line that follows every heading, so the notes open on real content.
awk 'NF { seen = 1 } seen' "$notes_out" >"$notes_out.trimmed"
mv "$notes_out.trimmed" "$notes_out"

[ -s "$notes_out" ] || {
  printf 'the "## v%s" section in CHANGELOG.md is empty\n' "$version" >&2
  exit 1
}
