# Flagship example — one contract, two coding agents, 57 issues

From 2026-08-12 to 2026-08-14, one Nightshift contract drove six roadmap phases on
[AdaptTable](https://github.com/orwa-mahmoud/adapttable), a production React data-table library.
Claude Code began the shift. When the owner's Claude allowance ran out, the owner issued a
Nightshift stop-work order and handed the same on-disk punch list to Cursor. Cursor resumed ten
minutes later instead of reconstructing the plan from chat.

The result was [PR #353](https://github.com/orwa-mahmoud/adapttable/pull/353): **67 commits, 700
changed files, six roadmap phases, and 57 issues closed** after owner review. The full GitHub check
suite passed before merge.

This is the scale example. For a small first run that is easier to reproduce, see
[`adapttable-overnight.md`](adapttable-overnight.md).

## The durable handoff

Nightshift's files, not either conversation, held the authority:

- one branch: `night/2026-08-12`;
- eight top-level punch-list items covering the six roadmap phases;
- one definition of done across nine adapters, 17 locales, documentation, changesets, tests,
  browser verification and Sonar;
- one parking lot for owner decisions and one snag log for failures;
- one conventional commit per issue, kept local until morning review.

The recorded sequence is public or preserved in the archived Nightshift receipt:

| UTC | Event |
| --- | --- |
| 2026-08-12 17:20 | Nightshift armed the eight-item contract with Claude Code. |
| 2026-08-13 17:12 | The owner stopped that session when the Claude allowance ran out. |
| 2026-08-13 17:22 | Cursor resumed the same branch, punch list and definition of done. |
| 2026-08-14 14:27 | All eight items were ticked after the final Sonar pass: 0 issues, 0 hotspots. |
| 2026-08-14 19:26 | Owner review, additional fixes and CI completed; PR #353 merged. |

That is **45 hours 7 minutes of elapsed shift continuity** and **50 hours 6 minutes from arming to
merge**. Commit timestamps prove the agent sequence and handoff; they are not presented as a meter
of uninterrupted token-processing time. Claude Code returned during the final review-and-fix pass,
which is also visible in the commit authorship.

## What shipped

The eight contract items produced six coherent roadmap phases:

1. **Data engine** — nested grouping, group footers, group-aware sorting and filtering,
   controlled expansion, server grouping, hierarchical tree data and nested tables.
2. **Spreadsheet interactions** — drag and column selection, clipboard copy/cut/paste, fill
   handle, selection statistics, undo/redo and find-in-table.
3. **Virtualization and sizing** — column virtualization, virtualized row detail, content sizing
   and flex-to-container columns.
4. **Editing 2.0** — validation, typed and custom editors, optimistic saves with rollback, dirty
   state, row and batch editing, row mutation helpers, lifecycle events and conflict handling.
5. **Rows and columns** — reordering, pinning, spanning, full-width rows, conditional styling,
   collapsible column groups, advanced menus, custom chrome and sparkline columns.
6. **Advanced filtering** — typed operators, relative dates, AND/OR trees and builder,
   Excel-style checklists, facet counts, header filters and a public filter registry.

## What the owner reviewed

Nightshift did not merge, publish or pretend that ticks proved correctness. The owner reviewed the
branch, ran additional checks, fixed findings and merged the PR. The final evidence included:

- all GitHub checks green, including tests with coverage, CodeQL, packaging, consumer harness,
  performance smoke, three React compatibility jobs and a 16-minute Playwright showcase run;
- core coverage reported by the PR at 96.58% statements, 99.43% lines and 99.03% functions;
- SonarQube at 0 issues and 0 hotspots;
- browser verification across all eight UI adapters;
- new labels in all 17 locales and every new public export documented;
- zero lint suppressions and zero skipped tests.

## Proof

- [Merged flagship PR #353](https://github.com/orwa-mahmoud/adapttable/pull/353)
- [First commit in the public
  sequence](https://github.com/orwa-mahmoud/adapttable/commit/b419e6623bf1bf9a3d8ad9331b918d3a0ae2b171)
- [First Cursor handoff
  commit](https://github.com/orwa-mahmoud/adapttable/commit/9bccc0b1350784bdf99518c11d5cd1cbef4cc027)
- [Last review-and-fix
  commit](https://github.com/orwa-mahmoud/adapttable/commit/e6d5d283706dd96119fccef5c04839642088f40d)

The point is not that every shift should be this large. It is that the work contract survived the
thing that normally breaks a long agent run: time, compaction, a stopped session and a change of
agent. The next agent inherited explicit state and continued shipping against the same standard.
