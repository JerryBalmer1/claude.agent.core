# Refusal records from the platform's own denial stream

| | |
|---|---|
| Feature | `--permission-prompts none` denial events, `PermissionDenied` hook |
| Repo | core |
| Status | proposed (beyond the seed list) |

## What the feature does

Source: https://code.claude.com/docs/en/headless.md § "Turn off permission prompts in unattended runs"; https://code.claude.com/docs/en/hooks.md § "PermissionDenied"

In print mode, `--permission-prompts none` (v2.1.259+) denies any permission prompt nothing else
resolved and removes `AskUserQuestion`. It reports each denial as a `permission_denied` event, and
the result carries a `permission_denials` list. The `PermissionDenied` hook is narrower. It fires
only for auto-mode classifier denials, not for manual denials, PreToolUse blocks or `deny` rule
matches, and it can return `retry: true`.

## What problem of ours it addresses

BACKLOG B18 (`core:docs/BACKLOG.md:29`) asks for a refusal record schema: who refused, what was
asked, which rule bound, that rule's version, and what happened next. F90
(`core:docs/FINDINGS.md:636`) is the first refusal recorded in this tree, and it was written by
hand. Today, refusals are only as complete as the agent's own report of them. That is the "counted
versus self-reported" split B22 (`core:docs/BACKLOG.md:33`) wants labelled.

## What it would replace or strengthen

In unattended runs, the platform emits the denial list itself. That fills B18's "what was asked"
and "which tool" fields from an independent count instead of from narration. Deny-rule matches and
hook blocks are not in `PermissionDenied`, so the stream-json events are the source to use, and
the hook is not.

## Acceptance test

1. `claude -p --permission-prompts none --output-format stream-json` in a scratch clone, asked to do
   three things the settings deny. Measure three `permission_denied` events and a
   `permission_denials` list of length 3.
2. Map each event onto B18's fields. Record which fields the platform fills and which still need
   narration.
3. Confirm the documented gap: a `deny` rule match does not fire `PermissionDenied`.

## Risks

- Unattended runs only. Interactive refusals stay self-reported.
- The event schema is versioned by Claude Code, not by us. A parser for it drifts, and
  `scripts/Test-PlatformDocs.ps1` is what notices when the page that describes it changes.
