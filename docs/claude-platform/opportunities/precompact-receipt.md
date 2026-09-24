# PreCompact: a receipt before context is summarised away

| | |
|---|---|
| Feature | `PreCompact` and `PostCompact` hooks, `SessionStart` with the `compact` matcher |
| Repo | core |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "PreCompact"; https://code.claude.com/docs/en/hooks-guide.md § "Re-inject context after compaction"; https://code.claude.com/docs/en/context-window.md § "What survives compaction"

`PreCompact` fires before compaction, with a matcher of `manual` or `auto`. It can block with exit
2 or `decision: "block"`. Blocking a proactive auto-compaction skips it. Blocking a recovery
compaction after a context-limit error surfaces that error. `PostCompact` receives the
`compact_summary`. A `SessionStart` hook with the `compact` matcher runs after compaction, and its
output is added to the fresh context.

After compaction, the project-root CLAUDE.md, unscoped rules and auto memory are re-injected, and
git status is read fresh. Path-scoped rules and nested CLAUDE.md files are dropped until a matching
file is read again.

## What problem of ours it addresses

Transcripts are already evidence here: `core:.gitignore:4-6` keeps `docs/plans/**/TRANSCRIPT.log`
because "a run order's transcript is evidence". F18 in
`core:docs/plans/2026-09-22-substrate-cutover/FINDINGS.md:245-261` records that `Start-Transcript`
misses a child pwsh. Compaction is the in-session version of the same loss. What was said before it
is replaced by a summary nobody reviewed. No repo mentions compaction today (measured).

## What it would replace or strengthen

A `PreCompact` hook records a line with the session id, trigger (`manual` or `auto`) and time, plus
the hash of the transcript file it is about to lose from context. A `PostCompact` hook records the
hash of `compact_summary`. The pair shows exactly when evidence became paraphrase. A `SessionStart`
`compact` hook re-injects measured state, not remembered state
(see [`state-skill.md`](state-skill.md)).

## Acceptance test

1. Run `/compact` in a session with both hooks. Measure one pre line and one post line, with
   matching session ids, the post after the pre.
2. Measure that the transcript hash in the pre line equals the SHA-256 of the transcript file
   read at that moment.
3. With the `SessionStart` `compact` hook, measure that the re-injected state block appears in
   context after compaction (`/context`).

## Risks

- Blocking compaction to force a receipt can end a session on a context-limit error. The hook
  should record and not block, unless a later decision says otherwise.
- The receipt goes to a log outside the tree, not to the forensic chain. A compaction is a fact
  about a session, not about the repository. Invoke-Preflight states the same line.
