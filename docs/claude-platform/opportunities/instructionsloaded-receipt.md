# InstructionsLoaded: a receipt for which instructions actually loaded

| | |
|---|---|
| Feature | `InstructionsLoaded` hook, and `@AGENTS.md` import |
| Repo | core, images |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "InstructionsLoaded"; https://code.claude.com/docs/en/memory.md § "When Claude Code reads AGENTS.md"; https://code.claude.com/docs/en/memory.md § "Where AGENTS.md differs from CLAUDE.md"; https://code.claude.com/docs/en/memory.md § "Remove an earlier AGENTS.md workaround"

`InstructionsLoaded` fires each time a CLAUDE.md or `.claude/rules/*.md` file loads. It receives
`file_path`, `memory_type`, `load_reason`, `globs`, `trigger_file_path` and `parent_file_path`. It
runs asynchronously and cannot block.

The catch is in the AGENTS.md support. From v2.1.277, Claude Code reads `AGENTS.md` natively. By
default it does so only when there is no `CLAUDE.md`, `.claude/CLAUDE.md` or `CLAUDE.local.md` in
the working directory or above it. **An AGENTS.md read natively does not fire `InstructionsLoaded`.**
It does fire when a CLAUDE.md imports `@AGENTS.md` (`load_reason: include`) or is a symlink to it.
A CLAUDE.md that says in prose "read AGENTS.md" only works if Claude decides to open the file.

## What problem of ours it addresses

Every rule in core lives in `core:AGENTS.md`, and core has no CLAUDE.md. So on a recent Claude Code,
AGENTS.md is read natively and the hook stays silent for exactly the file that matters. On an older
one it is not read at all. Either way, nothing today records whether the law was in context when
the work was done. That is the stale-premises problem seen from the input side:
`core:AGENTS.md` ("Measurement beats expectation") asks for measurement, but what the agent was told
is itself unmeasured. The images `AGENTS.md` already names files that do not exist
(`images:AGENTS.md:195`, `:197`).

## What it would replace or strengthen

It strengthens the parking and handoff rules with a machine-written line per session: these files
loaded, for these reasons. Adding a one-line `CLAUDE.md` containing `@AGENTS.md` is what makes the
hook see AGENTS.md at all.

## Acceptance test

1. Core as it is, with the hook installed and logging to a file outside the tree. Start a session
   and measure that the log contains **no** AGENTS.md line. That confirms the blind spot on our
   version, and `/memory` confirms whether AGENTS.md loaded natively.
2. Add `CLAUDE.md` containing `@AGENTS.md`. Start a session and measure an AGENTS.md line with
   `load_reason: include`.
3. Read a file under a path-scoped rule. Measure a line whose `trigger_file_path` is that file.

Pass means 1 is silent and 2 and 3 are logged.

## Risks

- Adding a CLAUDE.md to core is a change to how every agent loads the law, and it needs the human's
  decision. `CLAUDE.local.md` also counts as a CLAUDE.md and would suppress native AGENTS.md
  loading, which is a trap for anyone who adds one.
- The hook proves a file loaded, not that it was followed. Loaded and obeyed are different
  measurements.
- CLAUDE.md edits do not apply mid-session (see [`../memory-and-context.md`](../memory-and-context.md)),
  so the test must start fresh sessions.
