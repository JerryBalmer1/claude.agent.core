# REPORT — substrate cutover 2026-09-22, Phases 1–5, and Phase 6 halted at 6.1

What landed, phase by phase, with the pull request and the merge commit that carried it and the
test counts on either side of it.

**Every number in this file is reproducible by a script in this repository**, and the command is
printed beside the number rather than left implied. Where a number cannot be reproduced here — the
in-container baseline needs Docker and the image builder — the reason is stated in the section
that uses it.

This file does not repeat the findings. `FINDINGS.md` holds the 52 of them, including every place
a measurement disagreed with the run order. It does not repeat the merge evidence either:
`FLOW-PROOF.md` holds one row per phase with parent hashes, and it is the document that proves the
work went through the flow rather than around it.

---

## The five phases

| Phase | Branch | PR | Merge commit | Pester | What it landed |
|---|---|---|---|---|---|
| 1 | `feature/cutover-baseline` | [#14](https://github.com/JerryBalmer1/claude.agent.substrate/pull/14) | `918a88c` | 47 → 62 | the in-container baseline, and the runtime declaration |
| 2 | `feature/module-policy` | [#15](https://github.com/JerryBalmer1/claude.agent.substrate/pull/15) | `b0fc2c4` | 62 → 72 | `modules/policy/` |
| 3 | `feature/module-plans` | [#16](https://github.com/JerryBalmer1/claude.agent.substrate/pull/16) | `21a20d0` | 72 → 83 | `modules/plans/` |
| 4 | `feature/module-ledger` | [#17](https://github.com/JerryBalmer1/claude.agent.substrate/pull/17) | `f7cbb11` | 83 → 167 | `modules/ledger/`, engine included |
| 5 | `feature/release-0.1.0` | recorded in Phase 6 | recorded in Phase 6 | 167 → 167 | the release: this file, the notes, the tag |

Every merge commit above has **two parents**. `FLOW-PROOF.md` lists them and the command that
prints them.

## Reproducing the numbers

```powershell
pwsh -NoProfile -File scripts/ci/Invoke-Tests.ps1        # the Pester total, under the pinned version
pwsh -NoProfile -File scripts/Measure-Modules.ps1        # the same run, bucketed per module
pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/verify.ps1          # re-derives this release's claims
pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/falsify-ledger.ps1  # plants ten defects in the ledger suite
pwsh -NoProfile -File scripts/Measure-Baseline.ps1 -Json <j> -Markdown <m>        # the in-container baseline; needs Docker
```

`verify.ps1` is the one to run if you only run one. It recomputes `HASHES.txt`, runs every CI
check script against `HEAD`, and asserts the per-module numbers in `README.md` against a live
Pester run — so a stale number in the README is a failing check rather than a document nobody
noticed.

---

## Phase 1 — the baseline, and the runtime declaration

**Branch** `feature/cutover-baseline` → `develop`. **PR** #14, merged `2026-09-22T00:02:14Z`.
**Merge commit** `918a88c69233cc6092ef240f6dc46878510e0012`, parents `7cd58ca` `51317d9`.

**What landed.** `BASELINE.md` and the `baseline.json` it is generated from;
`scripts/Measure-Baseline.ps1` and `scripts/New-BaselineMarkdown.ps1`; `runtimes` in
`config/repo.json` and in `schemas/repo.schema.json`; `scripts/ci/Test-Runtimes.ps1` as a **second
step of the existing `requires-header` job**, not as a new required check; `tests/Runtimes.Tests.ps1`.

**Why it exists.** The README's definition of done is measured against "the same pass count it had
at cutover", and that count had never been recorded. Phase 1 recorded it before anything moved.

| | | Reproduced by |
|---|---|---|
| In-container checks that ran and passed | **127** — `continuity` 77, `forensic_chain` 28, `no_sabotage` 22 | `scripts/Measure-Baseline.ps1` |
| Suites that could not produce a count in-container | **4** — one aborted, three could not start | same; `FINDINGS.md` F10–F12 |
| Substrate Pester at the start | **47** | `scripts/ci/Invoke-Tests.ps1` at `7cd58ca` |
| Substrate Pester at the end | **62** | same, on the merge commit |

The 127 is measured identically in both images — `claude.pwsh.image.leash:run-01` and
`claude.pwsh.image.developer:run-01` — and the suites measured are the tree image.builder **pins
as its submodule**, which is behind `claude.build.ledger`'s HEAD. The pin is the baseline, not the
HEAD; `BASELINE.md` says so and asserts the tree object before it runs anything.

`BASELINE.md` has been committed exactly once, in this phase, and nothing since has touched it:

```powershell
git log --oneline -- docs/plans/2026-09-22-substrate-cutover/BASELINE.md   # one line: ecc373a
```

## Phase 2 — `modules/policy/`

**Branch** `feature/module-policy` → `develop`. **PR** #15, merged `2026-09-22T00:38:06Z`.
**Merge commit** `b0fc2c4fd176d27832e676f918b37fff07548032`, parents `918a88c` `3af2133`.

**What landed.** The five files of `claude.build.policy@3be10c4`, copied byte-identical in
`f676d72`; the ten-check sandbox suite ported to Pester as `modules/policy/tests/policy.Tests.ps1`,
one `It` per original check, numbered to match; three fixtures for the three checks that reach for
things substrate does not have; module discovery in `scripts/ci/Invoke-Tests.ps1`; and the moved
`modules/` wall in `tests/Skeleton.Tests.ps1`.

| | | Reproduced by |
|---|---|---|
| Pester at the start | **62** — 61 passed, **1 failed** | `Invoke-Tests.ps1` on the merge commit |
| Pester at the end | **72** — all passed | same |
| Delta | **+10**, exactly the run order's number | |
| Checks ported one-to-one | **7** of 10 | `policy.Tests.ps1`, checks 1, 3, 4, 5, 8, 9, 10 |
| Checks fixture-backed | **3** — 2, 6, 7 | `FINDINGS.md` F23 has the per-check table |

The one failure at the start is not an asterisk on the delta, it is the wall doing its job: the
copy tripped `It 'modules/ contains nothing but .gitkeep'` the moment it landed (`FINDINGS.md`
F21). The wall was **moved to a named set**, not removed, and it is one `It` before and one `It`
after, so the `+10` measures the port and nothing else.

The first run on the runner was **68/72**, not 72/72: three checks bound a null path and a fourth
cascaded, because the port inherited `$env:TEMP` from a suite that had only ever run on Windows
and CI is `ubuntu-latest` (`FINDINGS.md` F26). That is the phase's most useful finding and it cost
one commit.

## Phase 3 — `modules/plans/`

**Branch** `feature/module-plans` → `develop`. **PR** #16, merged `2026-09-22T01:35:24Z`.
**Merge commit** `21a20d08eba49e41f832f7e1da63195141b5a46c`, parents `b0fc2c4` `dfa5009`.

**What landed.** `PlanValidator.ps1`, `plan.schema.json` and the plan contract, copied
byte-identical from `claude.pwsh.image.builder@a6b61dd` in `04bcfe8`; `plans.psd1` and `plans.psm1`
wrapping the entry function that actually exists — `Test-PlanStructure`, measured from the
caller rather than assumed (`FINDINGS.md` F2); eleven `It`s and seven plan fixtures.

| | | Reproduced by |
|---|---|---|
| Pester at the start | **72** — clean | `Invoke-Tests.ps1` on `e101e8a` |
| Pester at the end | **83** | same |
| Delta | **+11**. The run order gives no expected delta for this phase | |
| Run with `TEMP` and `TMP` deleted from a child `pwsh` | **83/83** | F26's condition, checked before calling it green |

Eleven rather than ten because the phase added a parameter the copy does not have: one `It` proves
no schema validation is **called**, and a second proves none **happens**. `-SchemaPath` is inert —
a path that does not exist changes no verdict, and a plan the schema rejects still passes
(`FINDINGS.md` F5, F27). That is the copy's behaviour, recorded rather than fixed; fixing it is
somebody's decision, not a release's.

## Phase 4 — `modules/ledger/`

**Branch** `feature/module-ledger` → `develop`. **PR** #17, merged `2026-09-22T02:26:29Z`.
**Merge commit** `f7cbb1169059515a2c25941ab0d16b00d2d0484f`, parents `21a20d0` `10ace43`.

**What landed.** Twelve files copied byte-identical from `claude.build.ledger@d57938d` in
`8dd85fe` — the manifest, the module, the Python engine, two documents and three sandbox suites;
then `ledger.Tests.ps1` (66) and `python.Tests.ps1` (18), the burst helper, the blob fixture,
`setup-python` pinned by sha in the pester job, and three `.gitignore` rules.

| | | Reproduced by |
|---|---|---|
| Pester at the start | **83** — clean | `Invoke-Tests.ps1` on `21a20d0` |
| Pester at the end | **167** | same |
| Delta | **+84** | |
| Split per file | `ledger.Tests.ps1` **66**, `python.Tests.ps1` **18** | `scripts/Measure-Modules.ps1` |
| Falsification | **10** planted defects, all ten red; control 84/84 | `falsify-ledger.ps1` |
| Python | 3.10.4 locally; `actions/setup-python@a26af69` pinned to 3.10 on the runner | `python.Tests.ps1` |

Eleven of the twelve copied blobs are re-asserted **on every suite run**, from the bytes on disk,
by recomputing `sha1("blob <len>\0" + content)` without git. The twelfth is the manifest, asserted
in reverse: undo its one adapted line in memory and the original blob comes back, which says the
diff is that line and provably nothing else.

Three of the ledger's seven sandbox suites did not come, and the report says which and why rather
than implying a clean sweep: `fuzzer_import.ps1` and `hook_pre_tool.ps1` are not substrate's
(`claude.agent.tools` and `claude.agent.images` respectively), and `continuity.ps1` and
`no_sabotage.ps1` were triaged the same way (`FINDINGS.md` F37). Four subjects the originals
covered are **not** covered by the port, each named with its reason in `FINDINGS.md` F44.

## Phase 5 — the release

**Branch** `feature/release-0.1.0` → `develop`, then `develop` → `main`, tagged `v0.1.0` on the
`main` merge commit. The pull request numbers and merge commits are recorded in Phase 6, because a
merge commit cannot be named by a commit that is one of its own parents.

**What landed.**

- `refactor(policy)` — F22 decided. `claude.build.policy.psd1`/`.psm1` → `policy.psd1`/`policy.psm1`;
  the module name is now `policy`. Two `It`s and one fixture data file changed, not the one the
  prompt predicted (`FINDINGS.md` F47).
- `scripts/Measure-Modules.ps1` — per-module counts from `(Invoke-Pester -PassThru).Tests`.
- `README.md` — the Status section is no longer "skeleton only".
- `AGENTS.md` — the wall bullet now matches the test that has encoded it since Phase 2
  (`FINDINGS.md` F48).
- `REPORT.md` (this file), `RELEASE-NOTES.md`, `FINDINGS.md` F47–F52, `FLOW-PROOF.md`'s Phase 4
  row and Phase 5 section, `HASHES.txt`, `verify.ps1`, and forensic record seq 6.

| | | Reproduced by |
|---|---|---|
| Pester at the start | **167** — 167 passed, 0 failed, at `f7cbb11` | `scripts/Measure-Modules.ps1` |
| Pester at the end | **167** — 167 passed, 0 failed | same |
| Delta | **0**. A release whose test count moves has done something other than release | |
| `ledger` / `policy` / `plans` / repo `tests/` | **84** / **10** / **11** / **62** | same |
| Policy suite across the rename | **10 → 10**; three planted defects red, control green | `FINDINGS.md` F47 |

---

## Phase 6 — the cutover, halted at 6.1

**Branch** `feature/cutover-halt` → `develop`. Nothing in this phase touches `modules/`,
`config/`, `README.md` or `BASELINE.md`. It is a record of a measurement that stopped.

**What Phase 6.1 permits, and what it forbids.** One commit in image.builder changing two paths
— `.gitmodules` and the gitlink — and an explicit instruction: *if the Dockerfile, the build
tasks or anything else must change for the image to build, stop and write the finding, because
that is the coupling measurement.* It must.

| | |
|---|---|
| Pre-swap, same tree | `Invoke-Build Bootstrap, Build.Image` → **4 tasks, 0 errors**; `sha256:1716f8ab…` (leash), `sha256:6708943e…` (developer), both identical to `BASELINE.md` |
| The commit | `405ea22` on `feature/submodule-substrate`, `3 files changed, 4 insertions(+), 4 deletions(-)`, submodule at `3933dcc` / `v0.1.0` |
| Post-swap, break 1 | `Bootstrap` — `Vendored Ledger missing: …\vendor\claude.build.ledger\src\ledger\Ledger.psd1`, `build/tasks/Core.build.ps1:31` |
| Post-swap, break 2 | `docker build` — `"/vendor/claude.build.ledger/src/ledger": not found`, `Dockerfile:97` |
| Sites bound to the literal | **13** — 8 on the build context, 5 on `/opt/leash/ledger/Ledger.psd1` in the image |
| Second, independent break | substrate's manifest is `ledger.psd1`, lowercase; case-insensitive on the host, a different file in the image |

**And a flow that cannot carry it.** `origin/develop` in image.builder has no `.gitmodules`, no
`vendor/`, no `build/`, no `config/`, no `.build.ps1`, and `entrypoint.sh` where the other side
has `entrypoint.ps1`. `397f631`, the vendoring commit, is an ancestor of `origin/main` and not of
`origin/develop`; the split is `9  16`. The only lane the configured flow offers is
`feature/* -> develop`, and on that side there is nothing to cut over. `FINDINGS.md` F53.

**Not done, and named as not done.** No image rebuilt after the swap, so no
`Measure-Baseline.ps1` run and **no per-suite comparison**: the pre-registered table is
unmeasured, not matched. No cutover pull request in either repository. `review.mode` **not**
flipped. `FLOW-PROOF.md` untouched — Phase 5's open row is left open rather than completed
out of turn, and the facts it needs are in F54 and F56 where the next pass can transcribe them.
`v0.1.0` still points at `3933dcc`.

**What was measured.**

| | | Reproduced by |
|---|---|---|
| image.builder flow vs substrate flow | identical but for `tooling.pester`: **6.1.0** vs **5.7.1** | `FINDINGS.md` F53 |
| Substrate's own suite, host | **167** — 167 passed, 0 failed, exit 0 | `scripts/ci/Invoke-Tests.ps1` |
| Substrate's own suite, in-container | **unmeasured** — no image could be built to run it in | — |
| `verify.ps1` before this phase wrote anything | 19 checks, 19 passed, `COMBINED 51a3e0c8…` | `verify.ps1` |
| The definition of done | **unreachable by construction** — 99 of the 127 come from `continuity.ps1` and `no_sabotage.ps1`, which substrate does not ship | `FINDINGS.md` F55 |
| `F27`/`F28` | recorded, not resolved: `a6b61dd` *is* the default-branch HEAD; `Plan.Check` points at image.builder's own `src/PlanValidator.ps1` | `FINDINGS.md` F56 |
| POSIX shell commands this phase | **0** — the `F25`/`F46`/`F52` streak ends | `FINDINGS.md` F57 |

---
## What is still open at `v0.1.0`

Stated here so that a tag does not read as a finish line.

1. **The definition of done is not met, and as written it cannot be.** 99 of `BASELINE.md`'s 127 come from two suites substrate deliberately does not ship — `FINDINGS.md` F55 does the arithmetic and proposes a replacement. `README.md` is left exactly as it is; the choice is Jerry's. The original clause read: it is met in Phase 6, when image.builder's submodule
   points here and its in-container suite matches `BASELINE.md` suite by suite. `README.md` says
   so and this release does not claim otherwise.
2. **`LedgerResultMismatch` is unexercised** — `FINDINGS.md` F44 and F51, and it is named in
   `RELEASE-NOTES.md` as a known gap.
3. **`-SchemaPath` is inert** in the plans module — F5, F27, F28. Untouched by this release by
   instruction; the decision waits for Phase 6.
4. **Four sandbox subjects are not covered** by the ledger port — F44.
5. **`review.mode` is still `"auto"`.** Phase 6 would have flipped it to `"human"` and did not, because the flip was gated on a cutover that halted at 6.1. Until it does, a pull
   request with green checks merges itself.
6. **Enforcement is CI, not branch protection** — this repository is on GitHub's free tier and
   protection was refused once, recorded in `docs/plans/2026-09-21-repo-policy/PROTECTION.md`.
   A human with push access can still push straight to `main`; `push-guard` is a tripwire, not a
   gate, and it is deliberately not a required check.
