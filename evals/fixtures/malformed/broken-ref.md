# Broken ref — finite — points at a file that does not exist

Use when testing broken-reference detection.

Supported on any repository.

```text
- [ ] **Broken reference contract.**
  - Discovery: read `$NIGHTSHIFT_PLUGIN_ROOT/skills/nightshift/references/does-not-exist.md`.
  - Never invent sources.
  - Ends when the validator reports the missing file.
  - Verify: evals/validate.sh fails.
```
