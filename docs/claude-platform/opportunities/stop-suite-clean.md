# Stop hook: the turn cannot end on a red suite

| | |
|---|---|
| Feature | `Stop` hook running `Assert-SuiteClean` |
| Repo | images |
| Status | proposed |

## What the feature does

Source: https://code.claude.com/docs/en/hooks.md § "Stop decision control"; https://code.claude.com/docs/en/hooks-guide.md § "Stop hook hits the block cap"

A `Stop` hook runs when Claude is about to end its turn. Returning `decision: "block"` with a
`reason`, or exiting 2, keeps Claude working and feeds the reason back to it. The input carries
`stop_hook_active` so a hook can tell that it is already inside a forced continuation. Claude Code
caps consecutive Stop blocks at eight. `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` raises that cap.

## What problem of ours it addresses

Clause (b) of the images definition of done (`images:README.md:62-75`) is that
`Invoke-Build Test.InContainer` exits 0, and the README says that means the task's exit code, not
the suite tally. `Assert-SuiteClean` (`images:build/Build.Helpers.psm1:246-343`) is the function that
turns a Pester result into that verdict: a failed test, a skip with no reason on it, or zero tests
run all fail it. Today it runs only when somebody runs the build (`images:build/tasks/Test.build.ps1:34-38`)
or when CI runs (`images:scripts/ci/Invoke-Tests.ps1:120-128`). An agent can end a turn and report
done without running either.

## What it would replace or strengthen

It strengthens clause (b) by moving the check from "CI will notice after the push" to "the turn
cannot end". It does not replace CI, which remains the check nobody can switch off locally.

## Acceptance test

In an images clone with the hook installed, three runs:

1. Plant a failing `It` in `tests/`. Ask Claude to finish. Measure that the Stop hook blocks, that
   the reason names `Assert-SuiteClean`, and that the session does not end until the plant is
   removed or the block cap is reached.
2. Plant a skip with no `BLOCKER-n` or `SkipWhen:` tag. The result must be the same as run 1.
3. Control, with a clean tree: the hook exits 0 and the turn ends. Measure the hook's wall clock
   and record it next to the run.

Pass means 1 and 2 block and 3 does not.

## Risks

- Cost. The host suite runs on every Stop. If it is slower than a turn is worth, the hook needs a
  cheap path, such as running only when tracked files changed since the last green run.
- The block cap is eight. After that the turn ends red anyway, so the hook must leave a receipt
  saying so, or the failure will look the same as success.
- Timeouts. A command hook that times out renders no decision (hooks.md § "Timeouts"). The in-container
  suite is too slow for this hook. Only the host suite fits.
