# Cursor stop payload capture

Official schema (https://cursor.com/docs/hooks): `status` is
`completed` | `aborted` | `error`.

Live Stop-button (Cursor 3.17.21, 2026-08-28): stdin JSON with
`hook_event_name` `stop` and `status` `aborted`. Same tell as the docs.
That is the owner interrupt — release, do not reinject, do not clock out
(Claude Escape equivalent). A natural turn end sends `completed`.

`stop-aborted.json` is that live shape with fixture ids and no private
fields. Re-capture only if a later Cursor build sends a different tell.
