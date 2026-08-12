# First-night safety checklist

Use this once before leaving Nightshift alone with a real project.

- **Start attended.** Run one small shift while watching it. Confirm the proposed gates pass, one
  item becomes one reviewable commit, and the shift ends only after its box is ticked.
- **Choose permissions deliberately.** Pre-allow only what the work needs, or explicitly accept the
  unattended full-access option. Nightshift's owner-defined deny rules still matter; they are not a
  sandbox and do not replace reviewing the agent's permissions.
- **Prove STOP before sleeping.** From another terminal run `touch .nightshift/STOP`, then confirm
  the next stop attempt ends the shift while unfinished boxes remain open. Remove the test STOP
  file and start a fresh shift afterward.
- **Decide how stalls should end.** The default holds and flags a stalled run. Set `stallMax` only
  if you prefer an automatic clock-out after a fixed number of stuck attempts; always use a
  deadline for open-ended work.
- **Test notifications if configured.** `notifyCommand` is unrestricted owner-provided shell. Run
  it yourself first and remember it can access the network if your command does.
- **Know the host boundary.** Claude Code's Stop hook mechanically rejects an early clock-out and
  its watchman can revive a dead session. Codex keeps the same state, gates, and recovery target,
  but its host lifecycle differs: do not treat closing a live Codex session as a crash test.
- **Leave pushing for morning.** Keep the default local-only commits, review the diff and receipts,
  then push or open a pull request yourself.

The emergency stop is always available from the workspace root:

```sh
touch .nightshift/STOP
```

See [Owner knobs](knobs.md) for the exact rule and notification settings, and
[Command reference](commands.md) for setup, start, status, stop, and archive.
