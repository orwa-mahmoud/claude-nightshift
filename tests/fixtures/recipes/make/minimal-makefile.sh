#!/usr/bin/env bash
# minimal-makefile.sh <project-dir> — Makefile with test, lint, typecheck, and docs targets.
set -euo pipefail
dest="${1:?usage: minimal-makefile.sh <project-dir>}"
cat >"$dest/Makefile" <<'EOF'
.PHONY: test lint typecheck docs linkcheck
test:
	@printf 'ok\n'
lint:
	@printf 'ok\n'
typecheck:
	@printf 'ok\n'
docs:
	@mkdir -p build/docs
	@printf 'docs\n' >build/docs/index.html
linkcheck: docs
	@test -f build/docs/index.html
EOF
git -C "$dest" add Makefile
git -C "$dest" -c user.email=dev@example.com -c user.name=tester commit -q -m "add Makefile"
