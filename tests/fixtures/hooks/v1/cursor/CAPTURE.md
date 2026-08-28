# Cursor stop payload capture

Official schema (https://cursor.com/docs/hooks): `status` is
`completed` | `aborted` | `error`, plus common fields `conversation_id` /
`session_id`.

`stop-aborted.json` and siblings match that schema. A live Stop-button file was
not written during the first Cursor plugin shift (host denied `.cursor/` capture
paths). Observed behavior: pressing Stop reinjected the clock-out contract.

To replace fixtures with a real payload later: install a one-shot `stop` hook that
writes stdin to this directory, press Stop once, and commit the file.
