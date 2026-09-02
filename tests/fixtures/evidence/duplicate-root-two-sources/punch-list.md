# Punch List

## Items

- [x] **1. Break the orders<->customers import cycle in `src/app/imports.js` (f-lint-501,
  f-imp-502 — same root cause, flagged by both eslint and check-imports.sh).**
  - Verify: `npx eslint src/app/ && scripts/check-imports.sh src/app/`
  - Commit: `fix: extract shared order/customer types to break import cycle`
