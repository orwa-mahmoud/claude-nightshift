# SEO audit fixture

## Executive summary

The local fixture page is missing a title and uses a canonical that does not match itself.
robots.txt was requested and is unavailable, so indexability beyond the page markup is unknown.

## Sources

- S1 ok file:index.html retrieved 2026-08-28T08:00:00Z
- S2 unavailable https://example.invalid/robots.txt — not fetched; example.invalid is not a live host

## Observations

The document has an empty `<title>` [S1].
The canonical href is `https://example.invalid/other` while the file is `index.html` [S1].
The first heading is `h2`, not `h1` [S1].
An internal link points at `/missing` with no matching file in the fixture [S1].
No JSON-LD or other structured data is present in the file [S1].

## Inferences

Empty title and a mismatched canonical are verified defects on this page, not ranking claims.
Without S2, robots and sitemap behavior stay unavailable; do not infer indexability from Search Console.
