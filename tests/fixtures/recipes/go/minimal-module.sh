#!/usr/bin/env bash
# minimal-module.sh <project-dir> — the smallest Go module the capability recipes are proven
# against: one package, one passing test, committed. A committed tree means a plan reads a clean
# work target, and a rollback has real owner bytes it must leave alone.
#
# Only the module's own files are staged. The project also holds .nightshift, which never
# belongs in a work target's history.
set -euo pipefail
dir="${1:?usage: minimal-module.sh <project-dir>}"

cat >"$dir/go.mod" <<'EOF'
module example.test/nightshift/fixture

go 1.21
EOF

cat >"$dir/count.go" <<'EOF'
// Package fixture is the smallest module the Go capability recipes are proven against.
package fixture

// Count reports how many runes text holds.
func Count(text string) int {
	n := 0
	for range text {
		n++
	}
	return n
}
EOF

cat >"$dir/count_test.go" <<'EOF'
package fixture

import "testing"

func TestCount(t *testing.T) {
	if got := Count("night"); got != 5 {
		t.Fatalf("Count(night) = %d, want 5", got)
	}
}
EOF

git -C "$dir" add -- go.mod count.go count_test.go
git -C "$dir" commit -q -m "add the fixture module" -- go.mod count.go count_test.go
