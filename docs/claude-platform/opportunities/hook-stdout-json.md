# Hook stdout is JSON only if it starts with { and ends with }

| | |
|---|---|
| Feature | Hook stdout parsing rule |
| Repo | images |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "Exit code 0"; https://code.claude.com/docs/en/hooks-guide.md § "Hook JSON has no effect"; https://code.claude.com/docs/en/hooks.md § "Other exit codes"

On exit 0, Claude Code parses a hook's stdout as JSON only if, after trimming, it starts with `{`
and ends with `}`. Anything else is plain text. That includes a JSON **array**, and it includes
output with an unconditional `echo` in front of it. A decision in plain text is not a decision.
Exit 0 with no output is not approval either, and exit 1 does not block. So a hook whose deny comes
out as `[{...}]` lets the call through with no error.

## What problem of ours it addresses

This is the same trap class as the array-unroll defect, met from the other side. The recorded sites
are all on the **input** side:

1. `images:hooks/sentinel.ps1:110-121`: a one-element array payload was accepted as a valid
   payload. The defence is a raw-text `StartsWith('{')` check.
2. PlanValidator: `images:src/PlanValidator.ps1:74`, and the same line in
   `core:modules/plans/PlanValidator.ps1:74`.
3. `images:.claude/hooks/Deny-Heredoc.ps1:60-67`: the first version denied the array while its own
   comment claimed it failed open. The fix is `-NoEnumerate`.

`images:END_GOAL.md:99-103` records sites 1 and 3 as a recurrence. This rule is the **output-side**
site. `Deny-Heredoc.ps1:91` emits its decision with `ConvertTo-Json -Compress` on an
`[ordered]` hashtable, which is an object today. The same line written with `-AsArray`, or as
`ConvertTo-Json -InputObject @($decision)`, prints `[...]` and switches the guard off without a
sound. Measured in pwsh 7: both of those forms emit `[{"a":1}]` for a one-key hashtable.
`@($decision) | ConvertTo-Json` still emits `{"a":1}`, because the pipeline unrolls the one-element
array. This is the same trap, and it happens to be harmless here.

Record this as a further site of the same recurrence class: PowerShell's array handling and a
parser that treats an array as "not JSON".

## What it would replace or strengthen

It strengthens every hook that emits a decision, by adding a test that pins the shape of the output
and not just its content.

## Acceptance test

A Pester test in images that pipes a denying payload into each hook script that emits JSON (today
only `Deny-Heredoc.ps1`), captures stdout, and asserts:

- after `Trim()`, stdout starts with `{` and ends with `}`;
- it parses to an object with `hookSpecificOutput.permissionDecision -eq 'deny'`.

Falsify it: change the emit line to `ConvertTo-Json -AsArray` and measure that the test goes red.

## Risks

- A profile or module that writes to stdout before the hook's JSON breaks the rule. `-NoProfile` in
  the registered command is load-bearing, and the test must run the hook exactly as registered.
- The sentinel exits 2 to deny, so it takes the stderr path and is not exposed to this rule. Its
  historic defect was the reverse: a deny body followed by exit 2 (`images:END_GOAL.md:550-556`).
