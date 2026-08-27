# Deadline conflict

## Executive summary

Two local sources disagree on the deadline (Friday vs Monday). The calendar URL was unavailable, so neither date is confirmed outside those files.

## Sources

- S1 ok file:source-a.md retrieved 2026-08-28T08:00:00Z
- S2 ok file:source-b.md retrieved 2026-08-28T08:00:00Z
- S3 unavailable https://example.invalid/calendar — not fetched

## Observations

Source A states the deadline is Friday [S1].
Source B states the deadline is Monday [S2].
These two `ok` sources contradict each other on the same fact.

## Inferences

Do not pick a date. Confidence is low until an `ok` calendar source exists. S3 cannot break the tie.
Resume from notes.md, which still quotes [S1] and [S2].
