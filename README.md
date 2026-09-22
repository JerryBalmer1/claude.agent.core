# claude.agent.core

The substrate the agent tooling is built on: branch flow, the checks that enforce it, a forensic
hash chain, and three PowerShell modules — `ledger`, `policy` and `plans` — each with its own
manifest and its own Pester suite beside it.

It is **not** a container and it does not build one. `src/` holds nothing but `.gitkeep`; module
code needs a run order that says so. Nothing here reaches the network except CI reaching GitHub.

## Status

**Born 2026-09-22 at `v0.2.0`.** This repository is a clean copy of `claude.agent.substrate` at
`e40ba414be0c08df603094957cf7816ef81a14b0`, tag `v0.2.0`. The copy carried the working tree and
none of the history: the initial commit is the one commit in this repository's life that is not a
merge, and `docs/FINDINGS.md` F74 names every path that was not carried and why.

The suite is **161 tests, 0 failed**. That is 27 fewer than the source measured, and the 27 are
not a regression: every one of them asserted a fact about the source repository's own git history
— pinned commit shas as fixtures, a trailerless root commit, a grandfather exemption file — none
of which a clean copy has. F78 names all 27 and BACKLOG B11 rebuilds the ones worth rebuilding
against synthetic repositories the test itself constructs.

`docs/plans/2026-09-22-substrate-cutover/verify.ps1` re-derives this release's claims and reports
**17 of 19**. The two reds are F70 and are by design: `modules/plans/plans.psd1` and
`modules/plans/PlanValidator.ps1` are pinned to bytes that the Phase 7 rewrite deliberately moved.
Run it from `develop`; run from `main` it reports 16 because `main -> develop` matches no row in
`config.flow`, which is a fact about the branch name and not about the tree (F76, BACKLOG B9).

| Module | Import path | Suite | Tests |
|---|---|---|---|
| `ledger` | `modules/ledger/ledger.psd1` | `modules/ledger/tests/` | **90** |
| `policy` | `modules/policy/policy.psd1` | `modules/policy/tests/` | **10** |
| `plans` | `modules/plans/plans.psd1` | `modules/plans/tests/` | **12** |
| — | the repository's own suite | `tests/` | **49** |
| | | **total** | **161** |

Every figure in that table is measured, not counted by hand. It comes out of
[`scripts/Measure-Modules.ps1`](scripts/Measure-Modules.ps1), and
[`verify.ps1`](docs/plans/2026-09-22-substrate-cutover/verify.ps1) parses the table back out of
this file and compares it to a live run, so the README cannot rot quietly.

## Why there is Python here

There is exactly one directory of it, `modules/ledger/python/`, and it is not an oversight. The
ledger's compute engine has to be a separate process: `LedgerPythonMissing`, `LedgerSnakeFailed`,
`LedgerNoResult` and `LedgerResultMismatch` exist precisely because the module holds strings, not
objects, and cannot attest to a retry count it never observed. Porting the engine in-process would
delete four pinned error ids and leave the lying-snake fixture nothing to lie to.

The rule is data, not prose: `config/repo.json` → `runtimes.rule` states it,
`runtimes.python.allowed_under` bounds it, `scripts/ci/Test-Runtimes.ps1` measures it, and a
tracked `.py` outside that prefix fails the `requires-header` check. See
[`AGENTS.md`](AGENTS.md) → *The runtime rule*.

## Branch flow

| From | Into | How |
|---|---|---|
| `feature/*` | `develop` | pull request, merge commit |
| `develop` | `main` | pull request, merge commit |

`develop` is the default branch. `main` is the settled end.

**Merge commits only.** Never squash, never rebase, never force-push, never amend anything
pushed. Hashes are evidence here; a squash destroys the evidence and a rebase forges it.

Branch names, the flow, the merge strategy, the review mode, the required checks, the script
version floor, the runtime rule and the pull-request template are **not written down twice**. They
live in [`config/repo.json`](config/repo.json), validated against
[`schemas/repo.schema.json`](schemas/repo.schema.json). `docs/POLICY.md` and
`.github/PULL_REQUEST_TEMPLATE.md` are *generated* from that config by
[`scripts/Generate-Policy.ps1`](scripts/Generate-Policy.ps1), and CI fails if they drift.

## Enforcement

This repository is on GitHub's **free** tier, where branch protection and rulesets are not
available on private repositories. Protection was attempted once and refused; see
[`docs/PROTECTION.md`](docs/PROTECTION.md) for the exact response. **CI is the enforcement**, not
the branch settings. That is a weaker guarantee — a human with push access can still push straight
to `main` — and it is written down here rather than glossed over.

## Review mode

`config/repo.json` carries `review.mode`, and here it is `"human"`: `.github/workflows/automerge.yml`
stands down and a human merges. Flipping it to `"auto"` and regenerating would let a pull request
whose checks are all green merge itself — a one-line config change, not a workflow rewrite.

## The commit trailer

Every commit ends with a `who:` trailer as its last line, and `config/repo.json` →
`trailer.allowed` permits exactly one value:

```
who: claude
```

`git blame` says "Jerry Balmer", because the commits are made with his git identity. The trailer
is the only thing in the object that says an agent did it rather than the human. It is
**operator-asserted, not a signature** — it is not proof, it is a place to be caught lying, and
`scripts/ci/Test-Trailers.ps1` is what catches it.

## Requirements

PowerShell **7.4+** only. No bash, no sh, no heredocs. Every `.ps1` and `.psm1` carries
`#Requires -Version 7.4` and CI checks that it does.

## Reading order

[`AGENTS.md`](AGENTS.md) is the governing file — the trailer rule, the no-bash rule, the merge
rule, the parking rule, the runtime rule, and *measurement beats expectation*, which is the one
that matters most: where a document states an expected value and your measurement disagrees, the
measurement wins and the difference is written down as a finding.

[`docs/FINDINGS.md`](docs/FINDINGS.md) is this repository's own findings, F74 onward.
[`docs/BACKLOG.md`](docs/BACKLOG.md) is what is known to be owed.
[`docs/plans/`](docs/plans/) is the archived record of the migration that produced this
repository. It is carried verbatim and is **not** rewritten to match this repo's naming: a
rewritten measurement is a falsified one.
