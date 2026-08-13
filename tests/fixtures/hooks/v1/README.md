# Sanitized host-hook fixtures (v1)

Structural shapes only. No prompts, transcripts, repository content, credentials, or live
session identities. Session ids are the placeholder `fixture-session`. Replay these through the
shipped adapters in `tests/hook-replay.bats`; if a fixture no longer matches the runtime
contract, that test fails with the fixture path.
