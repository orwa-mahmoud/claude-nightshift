# Standing loop — open-ended — improve and discover until quitting time

The greedy one: no convergence ending. An empty cycle is not "done" — it means the lens was too
shallow. For when there is credit and hours, and the job is "make the product better".

```text
- [ ] **Standing loop — improve and discover until quitting time.**
  - Open-ended: the deadline is the ONLY thing that ends this item. A cycle that finds nothing
    means the lens was too shallow — go deeper (a new subsystem, a new entry point, a new user
    path) and start the next cycle at once. Never idle between cycles.
  - Each cycle pick 1–2 fresh lenses and rotate — never repeat the same shallow pass:
    - Real bugs — trace one concrete user scenario end-to-end through every layer: races,
      permission holes, stale state after mutations, timezone and edge inputs.
    - UX friction — dead ends, hidden state, missing empty/loading/error states, too many clicks
      to high-frequency work.
    - Performance — hot-path waste, N+1 queries, missing indexes, chatty endpoints, needless
      re-renders.
    - Contracts — type drift between layers, duplicated enums out of sync, permission gating
      parity on both sides (fail closed).
    - Dead code — verify truly unreachable first, then delete fully; never stub.
  - If the project has a UI, walk it live every few cycles with real clicks and the console open —
    code-only scans miss what clicking finds.
  - At every site inspection (the interval in `## Gates`; hourly if none is set), run the
    project's quality tooling in report mode and feed new findings into the next cycle.
  - Dedupe every finding against snag-log.md (ALL seen — fixed and rejected) before acting; append
    dispositions after. Park owner decisions in parking-lot.md and keep working.
  - Verify: the item gate is green at every commit; one conventional commit per coherent fix.
```
