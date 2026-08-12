CAT="$BATS_TEST_DIRNAME/../plugins/nightshift/skills/nightshift/references/gates-catalog.md"

@test "proposes the TypeScript toolchain for a package.json + tsconfig.json project" {
  grep -q 'package.json' "$CAT"
  grep -q 'tsconfig.json' "$CAT"
  grep -qE 'eslint.*tsc.*(test|noEmit)' "$CAT"
}

@test "proposes the Python toolchain for a pyproject/requirements project" {
  grep -qE 'pyproject.toml|requirements.txt' "$CAT"
  grep -qE 'ruff.*mypy.*pytest' "$CAT"
}

@test "covers Go, Rust, Helm, and a Makefile fallback" {
  grep -q 'go.mod' "$CAT"
  grep -q 'Cargo.toml' "$CAT"
  grep -qiE 'chart.yaml|kustomize' "$CAT"
  grep -q 'Makefile' "$CAT"
}

@test "states that detection only proposes and the user decides" {
  grep -qiE 'propose|user decides|opt-in' "$CAT"
}

@test "is Sonar-ready and keeps coverage a tripwire" {
  grep -qi 'sonar' "$CAT"
  grep -qi 'tripwire' "$CAT"
}
