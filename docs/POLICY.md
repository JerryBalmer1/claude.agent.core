<!--
  GENERATED FILE - DO NOT EDIT BY HAND.
  Rendered from config/repo.json by scripts/Generate-Policy.ps1.
  Edit the config and regenerate:
      pwsh -NoProfile -File scripts/Generate-Policy.ps1
  CI check "generated-match-config" fails the build if this file and the config disagree.
-->

# Policy - JerryBalmer1/claude.agent.core

Every rule below is rendered from `config/repo.json`. This file is evidence of the
config, not a second copy of it. If you want to change a rule, change the config.

## Branch flow

Long-lived branches: `main` and `develop`.
Work starts on a branch named `feature/<something>`.

| From | Into |
|---|---|
| `feature/*` | `develop` |
| `develop` | `main` |

Any other pair is refused by the `branch-flow` check. There is no path that skips
`develop`.

## Merge strategy

Strategy: **merge**. Delete the branch on merge: **true**.

Merge commits only. Never squash, never rebase, never force-push, never amend anything
already pushed. A merge commit has two parents and that is the evidence; a squash has
one parent and a hash that corresponds to nothing that was ever reviewed.

## Review mode

Mode: **human**.

> human from birth; core is a clean copy and every commit after the first is a merge, so there is always a human on the other side of the flow

While the mode is `human`, `.github/workflows/automerge.yml` stands down and exits
without merging. A human merges, and the checks below still have to be green.

## Checks that must be green

- `requires-header`
- `trailer-guard`
- `branch-flow`
- `generated-match-config`
- `pester`
- `forensic-verify`

One CI job per entry, named exactly the string above. The `generated-match-config` job
asserts that the set of job names in `.github/workflows/ci.yml` equals this list, so
the workflow cannot quietly drop a check.

## Commit trailer

Every commit carries a `who:` trailer as its **last line**. Allowed values:

- `who: claude`

Verify your own commit before pushing:

```powershell
git log -1 --format='%(trailers:key=who,valueonly)'
```

The trailer is **operator-asserted**. It is not a signature and it does not prove
anything. It is a place to be caught lying, checked by `trailer-guard`.

## Script version floor

PowerShell **7.4+** only. Every `.ps1` and `.psm1` in this repository starts with:

```powershell
#Requires -Version 7.4
```

No bash, no sh, no heredocs - including in CI, where workflow steps use `shell: pwsh`
and call scripts in `scripts/`. The `requires-header` check enforces the header.

## Runtimes

PowerShell **7.4+**. This section is the whole list of languages this repository is
allowed to contain, so the floor is restated here; it must equal the one above, and
`Test-Runtimes.ps1` fails the `requires-header` check if the two ever disagree.

Python **3.10+** is permitted, and only under:

- `modules/ledger/python/`

PowerShell 7.4+ for everything this repo does. No bash, sh, or heredocs.

Python is permitted in exactly one place, `modules/ledger/python/`, and only because the ledger engine must be a separate process: `LedgerPythonMissing`, `LedgerSnakeFailed`, `LedgerNoResult` and `LedgerResultMismatch` exist because the module holds strings, not objects, and cannot attest to a retry count it never observed.

An in-process port would delete four pinned error ids and leave the lying-snake fixture nothing to lie to.

`config/repo.json` -> `runtimes.python.allowed_under` enforces the placement, and `scripts/ci/Test-Runtimes.ps1` is what measures it.

## Owners

- @JerryBalmer1
