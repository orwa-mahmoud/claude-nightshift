#!/usr/bin/env bash
# red-module.sh <project-dir> — the same module with real findings in it: count.go is indented
# with spaces where gofmt wants tabs, and the test asserts a total the code does not produce.
# `gofmt -l`, `go vet` and `go test` all have something to say about this module, which is the
# red baseline the engine counts as a working capability.
#
# The module still compiles. A type error would stop `go build` before it could report anything,
# so the typecheck red baseline is driven by the scripted toolchain instead.
set -euo pipefail
dir="${1:?usage: red-module.sh <project-dir>}"

cat >"$dir/go.mod" <<'EOF'
module example.test/nightshift/fixture

go 1.21
EOF

cat >"$dir/count.go" <<'EOF'
// Package fixture is the smallest module the Go capability recipes are proven against.
package fixture

import "fmt"

// Count reports how many runes text holds.
func Count(text string) int {
    n := 0
    for range text {
        n++
    }
    return n
}

// Describe prints the count. The verb does not match the argument, which is what go vet reads.
func Describe(text string) {
    fmt.Printf("%d\n", text)
}
EOF

cat >"$dir/count_test.go" <<'EOF'
package fixture

import "testing"

func TestCount(t *testing.T) {
	if got := Count("night"); got != 6 {
		t.Fatalf("Count(night) = %d, want 6", got)
	}
}
EOF

git -C "$dir" add -- go.mod count.go count_test.go
git -C "$dir" commit -q -m "add the fixture module" -- go.mod count.go count_test.go
