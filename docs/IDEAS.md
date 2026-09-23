# IDEAS

A holding pen for ideas raised in conversation that would otherwise be lost.

Two rules:

- **This is not a roadmap and not a commitment.** Nothing here is scheduled, owned or
  promised. An idea written down is evidence that it was said, and nothing more.
- **An entry graduates by becoming a plan or an issue, and leaves this file when it does.**
  Nothing is closed here, because nothing is tracked here.

One entry per idea, dated, newest first, under a heading of the form
`## YYYY-MM-DD 
—
 <short title>`, with a few sentences of prose beneath it. No
checkboxes, no status column, no priority field. This is a notebook, not a tracker.

## 2026-09-22 
—
 A chaos and injection harness for the sentinel

A deliberate injection-point harness for testing the sentinel end to end. A process parks
on a timeout, polls a drop location, executes whatever payload lands there, and records a
receipt for it. The payload is scripted, so the run is repeatable rather than a one-off
poke at something live.

Three constraints, all of them the point rather than caveats:

- **The harness is unmistakably a harness.** Its own file, its own module, never loaded by
  the leash image and not importable from production code. A test double reachable from the
  runtime is an attack surface, not a test.
- **Every injection is itself a receipt.** The payload, its hash, what the sentinel decided,
  and what the ledger recorded.
- **The assertions are about honesty of the record, not just deny-versus-allow.** Did the
  receipt match what actually executed; did a denied call still leave a record; does the
  chain verify afterwards. A gate that denies correctly but lies in the ledger is worse than
  one that fails openly.

Context for why it came up: PowerShell has ordinary injection surfaces 
—
 profile scripts,
`PSModulePath` shadowing, inherited environment, runspaces 
—
 so whether a deny is real or
merely claimed is worth measuring rather than assuming.
