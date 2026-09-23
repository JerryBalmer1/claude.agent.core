![claude.agent.core](assets/header.svg)

# claude.agent.core

The substrate the agent tooling is built on: branch flow, the checks that enforce it, a forensic
hash chain, and three PowerShell modules — `ledger`, `policy` and `plans` — each with its own
manifest and its own Pester suite beside it.

It is **not** a container and it does not build one. `src/` holds nothing but `.gitkeep`; module
code needs a run order that says so. Nothing here reaches the network except CI reaching GitHub.

## Scope

Two things are in scope today, and the things that are not are named here so the boundary is
explicit rather than accidental.

**Provenance.** Tamper-evident receipts of what an agent did: hash-chained, append-only, and
verifiable without trusting the agent that produced them.

**Gating.** Enforcement of what an agent is permitted to do, applied before it acts rather than
reported after.

Two further concerns are **deliberately out of scope for v1**.

**Judgment** — deciding whether recorded actions satisfy a control, a standard or a policy. This
repository records and constrains; it does not evaluate.

**Attribution and consequence** — what happens when judgment fails: notification, rollback, merge
blocking, sign-off and ownership.

Both are out of scope for this repository and neither is built anywhere else yet — the boundary
says where the work belongs, not that the work is done. They are planned layers built on top of
this one: a layer that judges needs something trustworthy to judge, and a layer that assigns
consequence needs a judgment to act on.
Each is downstream of provenance and gating by construction, and each belongs in its own place
rather than here.

## Status

**Born 2026-09-22 at `v0.2.0`.** This repository is a clean copy of `claude.agent.substrate` at
`e40ba414be0c08df603094957cf7816ef81a14b0`, tag `v0.2.0`. The copy carried the working tree and
none of the history: the initial commit is the one commit in this repository's life that is not a
merge, and `docs/FINDINGS.md` F74 names every path that was not carried and why.

The suite is **206 tests, 0 failed**. It was **162** at birth, so **44 net have been added since**.
The source measured 188: 27 were removed and 1 was added on the way in.
The 27 are not a regression — every one of them asserted a fact about the source repository's own
git history, pinned commit shas as fixtures, a trailerless root commit, a grandfather exemption
file, none of which a clean copy has. F78 names all 27, and BACKLOG B11 rebuilds the ones worth
rebuilding against synthetic repositories the test itself constructs. The 1 that was added pins a
file mode in the index, because the copy carried bytes and not modes and only Linux CI could see
it (F79). The one retirement recorded since birth is the `ledger.psm1` blob row in
`modules/ledger/tests/fixtures/copied-blobs.psd1`, retired when core exported `Add-LedgerRecord`:
birth fidelity to `claude.build.ledger` is recorded at the birth commit, and re-asserting it at
every HEAD would forbid core from ever changing its own ledger module. At 161 that retirement was
visible in the total; at 206 it is not, which is why it is written down in `docs/DECISIONS.md`
**D002** rather than left to arithmetic.

`docs/plans/2026-09-22-substrate-cutover/verify.ps1` re-derives this release's claims and reports
**15 of 19**. Four reds, all by design. Two are F70: `modules/plans/plans.psd1` and
`modules/plans/PlanValidator.ps1` are pinned to bytes that the Phase 7 rewrite deliberately moved.
Two arrived with the `Add-LedgerRecord` export — `ledger.psd1` exports five functions where the
pin expects four, and `ledger.psm1` hashes to `ba9c8efa` rather than to the copied blob, which is
the pin this repository retired on purpose. `verify.ps1` is the archived record of the migration
and is not rewritten to match a later tree, because a rewritten measurement is a falsified one, so
it will go on reporting these until something replaces it. Run it from `develop`; run from `main`
it reports one fewer because `main -> develop` matches no row in `config.flow`, which is a fact
about the branch name and not about the tree (F76, BACKLOG B9).

| Module | Import path | Suite | Tests |
|---|---|---|---|
| `ledger` | `modules/ledger/ledger.psd1` | `modules/ledger/tests/` | **90** |
| `policy` | `modules/policy/policy.psd1` | `modules/policy/tests/` | **10** |
| `plans` | `modules/plans/plans.psd1` | `modules/plans/tests/` | **12** |
| — | the repository's own suite | `tests/` | **94** |
| | | **total** | **206** |

Every figure in that table is measured, not counted by hand. It comes out of
[`scripts/Measure-Modules.ps1`](scripts/Measure-Modules.ps1), and
[`verify.ps1`](docs/plans/2026-09-22-substrate-cutover/verify.ps1) parses the table back out of
this file and compares it to a live run, so the README cannot rot quietly — except that
`verify.ps1` is not yet a required check, so nothing in CI runs it and the figures above have now
rotted twice. The second time it did not rot quietly so much as loudly and uselessly: with the
table stale, that check threw on a malformed format string instead of reporting the mismatch, and
took the remaining seven PASS/FAIL lines with it — its own, and both of checks 7 and 8. Twelve
lines printed, seven never did, and the mismatch it existed to report —
`repo: README 49, measured 94` — was the one thing it did not say.

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
