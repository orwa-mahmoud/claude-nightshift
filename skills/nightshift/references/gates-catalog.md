# Gates Catalog

How `/nightshift:setup` proposes quality gates from a project's stack. **Detection only ever
proposes — the user decides**: accept, edit (any shell command is a valid gate), or decline (no
gates is a first-class answer; the shift runs with spot-check only). Explicit user config always
beats detection.

Three tiers, cheapest first:

- **spot-check** — every edit (a hook; instant syntax/lint). Always on, nothing to configure.
- **item gate** — runs ONCE per item, right before its commit; must be green to tick. Fast.
- **site inspection** — the heavier batch at an interval (every N items or every H hours); coverage,
  dead-code, Sonar.

## Detection table (first match wins; monorepo-aware — detect per top-level package dir)

| Signal | Item gate (every item, fast) | Site inspection (interval, heavy) |
|---|---|---|
| `package.json` + `tsconfig.json` | `eslint` + `tsc --noEmit` + unit tests | coverage delta, `knip`/`ts-prune` dead-code sweep |
| `pyproject.toml` / `requirements.txt` | `ruff` + `mypy` + `pytest` | coverage, `vulture` dead-code sweep |
| `go.mod` | `go vet` + `go test ./...` | `go test -race`, coverage |
| `Cargo.toml` | `cargo clippy` + `cargo test` | coverage (`tarpaulin`) |
| `Chart.yaml` / kustomize | `helm template \| kubeconform` (changed charts) | full catalog render |
| `Makefile` (fallback) | `make lint test` if those targets exist | — |
| nothing detected | — (spot-check only) | — |

## Site-inspection interval

Chosen at setup — every **N items** or every **H hours** (default: hourly). The inspection includes:

- **coverage as a tripwire, never a target** — no padding tests to move a number; an exclusion needs
  a written reason;
- **dead-code sweeps** (per the table);
- **Sonar-ready** (below).

## Sonar-ready

If `sonar-project.properties` exists AND a local or community SonarQube answers on its configured
host, run the batch scan at each site inspection and fix to **zero new issues** before resuming
items. Sonar is too slow to be an item gate — it is an inspection, never per-item (the proven
hourly-batch pattern). Coverage there is a tripwire (a gate on new code), never padded.

## Notes

- Zero-config holds: nothing detected → the tiers silently shrink to spot-check only, and declining
  the proposal shrinks them identically. Gates are opt-in, never a requirement.
- The `## Gates` block lives in `punch-list.md` and stays owner-editable between and during shifts;
  hooks and the skill re-read it, so an edit takes effect from the next item. Only the agent is
  barred from editing it.
