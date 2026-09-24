# TaskCompleted: no task is done without a receipt

| | |
|---|---|
| Feature | `TaskCompleted` hook |
| Repo | core |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "TaskCompleted decision control"; https://code.claude.com/docs/en/agent-teams.md § "Enforce quality gates with hooks"

`TaskCompleted` fires when a task is marked completed through `TaskUpdate`, and when a teammate
ends its turn with tasks still in progress. Exit 2 prevents the completion and sends stderr back as
feedback. There is no matcher. `continue: false` is ignored when `TaskUpdate` triggered the event.
It is a gate on Claude Code's own task list. It is not a gate on git or on pull requests.

## What problem of ours it addresses

The receipt chain (`core:scripts/forensic.ps1`, `core:.continuity/forensic.jsonl`) records decisions,
but nothing requires that a piece of work produce one. Neither `AGENTS.md` states a
receipt-required rule. The practice lives in prose: `core:docs/BACKLOG.md:22` (B10), which says "in
one pull request with a receipt". BACKLOG B23 (`core:docs/BACKLOG.md:34`) asks for the stronger
property: "a run that produces no record at all must fail".

## What it would replace or strengthen

It strengthens B23 for work tracked on Claude Code's task list. The hook compares the chain's tip
sequence number at task creation with the tip at completion, and refuses completion when the tip
has not moved.

## Acceptance test

In a core clone with the hook installed:

1. Create a task, make an edit, mark it complete without appending a receipt. Measure that exit 2
   fires and the task stays open.
2. The same, with a `forensic.ps1 -Append` in between. Measure that completion succeeds and
   `forensic.ps1 -Verify` exits 0.
3. Count the tasks marked complete over one real session against the chain records appended in the
   same session. The two counts must match, or each difference must be explained.

## Risks

- Not every task deserves a receipt. The analysis inventory treats an inventory as "not a decision",
  so a blanket rule would inflate the chain. The hook needs an explicit opt-out, and each opt-out
  must be visible.
- The hook only sees tasks on Claude Code's task list. Work done without a task never triggers it,
  so it narrows B23 and does not close it.
- A receipt appended just to satisfy the hook is still a receipt. The hook proves that a record
  exists, not that the record is honest.
