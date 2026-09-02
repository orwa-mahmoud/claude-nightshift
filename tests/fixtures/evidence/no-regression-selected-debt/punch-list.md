# Punch List

## Items

- [x] **1. Fix f-typ-101: apply_discount receives a raw str instead of Decimal.**
  - Verify: `mypy src/billing/`
  - Commit: `fix: convert amount to Decimal before apply_discount`
