# FLOW-PROOF — substrate cutover 2026-09-22

One row per phase. Started in Phase 1, appended in every phase after it, hashed in Phase 5.

This exists because "the work went through the flow" is a claim, and a claim about merges is
checkable: every row below names a pull request and a **merge commit with two parents**. A
squash has one parent and a hash that corresponds to nothing that was ever reviewed, so a
one-parent row here is a failed proof, not a stylistic difference.

**A phase's own row is completed by the next phase.** A merge commit cannot be named by a
commit that is one of its own parents. The pull request number could in principle be written
before the merge, but only by pushing a further commit to a branch whose automerge is already
armed — a race whose loser is a phase that merged without the commit that documents it. So both
numbers are filled in by the following phase, from `gh pr view`, and nothing here is edited
into a commit that has already been pushed.

## Rows

| Phase | Branch | PR | Base | Merge commit | Parents | Landed |
|---|---|---|---|---|---|---|
| 1 | `feature/cutover-baseline` | #14 | `develop` | `918a88c69233cc6092ef240f6dc46878510e0012` | `7cd58ca` `51317d9` | `BASELINE.md`, `baseline.json`, `Measure-Baseline.ps1`, `New-BaselineMarkdown.ps1`, `runtimes` in config, `Test-Runtimes.ps1`, `Runtimes.Tests.ps1` |
| 2 | `feature/module-policy` | #15 | `develop` | `b0fc2c4fd176d27832e676f918b37fff07548032` | `918a88c` `3af2133` | `modules/policy/**` (copied in `f676d72`), `policy.Tests.ps1` + three fixtures, `Invoke-Tests.ps1` module discovery, the moved `modules/` wall, `PHASE-2-PROMPT.md` |
| 3 | `feature/module-plans` | #16 | `develop` | `21a20d08eba49e41f832f7e1da63195141b5a46c` | `b0fc2c4` `dfa5009` | `modules/plans/**` (copied in `04bcfe8`), `plans.psd1`/`plans.psm1`, `plans.Tests.ps1` + fixtures, `PHASE-3-PROMPT.md` |
| 4 | `feature/module-ledger` | #17 | `develop` | `f7cbb1169059515a2c25941ab0d16b00d2d0484f` | `21a20d0` `10ace43` | `modules/ledger/**` (copied in `8dd85fe`), `ledger.psd1`/`ledger.psm1`, `python/**`, `ledger.Tests.ps1` + `python.Tests.ps1`, `falsify-ledger.ps1`, `setup-python` in the pester job, Python and `.ledger/` in `.gitignore` |
| 5 | `feature/release-0.1.0` | recorded in Phase 6 | `develop`, then `main` | recorded in Phase 6 | — | the `README.md` status table, the `AGENTS.md` wall, the policy manifest rename (F22/F47), `Measure-Modules.ps1`, `REPORT.md`, `RELEASE-NOTES.md`, `FINDINGS.md` F47-F52, `HASHES.txt`, `verify.ps1`, forensic seq 6, tag `v0.1.0` |

Phase 1's row was completed in Phase 2, as this file's own rule requires. Measured, not copied
from the run order:

```powershell
gh pr view 14 --json number,state,mergedAt,mergeCommit,baseRefName,headRefName
git log -1 --format='%H%n%P' 918a88c
```

| | |
|---|---|
| PR | #14 — *Phase 1: baseline in-container suite counts, and the runtime declaration* |
| State | `MERGED`, `2026-09-22T00:02:14Z` |
| Head → base | `feature/cutover-baseline` → `develop` |
| Merge commit | `918a88c69233cc6092ef240f6dc46878510e0012` |
| Parents | `7cd58cadaf84e6f2afc38c2505e32a7b53ca806f` `51317d92b0e31805013fba96489b1f390fbe26a5` |
| Parent count | **2** — a merge, not a squash |

Phase 2's row was completed in Phase 3, the same way. `PHASE-3-PROMPT.md` states these numbers in
advance; they are recorded here from `gh` and `git`, and they agree:

```powershell
gh pr view 15 --json number,state,mergedAt,mergeCommit,baseRefName,headRefName
git log -1 --format='%H%n%P' b0fc2c4
```

| | |
|---|---|
| PR | #15 — *Phase 2: policy module, sandbox suite ported to Pester 10/10* |
| State | `MERGED`, `2026-09-22T00:38:06Z` |
| Head → base | `feature/module-policy` → `develop` |
| Merge commit | `b0fc2c4fd176d27832e676f918b37fff07548032` |
| Parents | `918a88c69233cc6092ef240f6dc46878510e0012` `3af2133e2735ac435c5796bbbb15c4712bb67f62` |
| Parent count | **2** — a merge, not a squash |
| Pester across the phase | **62 → 72**, `+10` |

`PHASE-3-PROMPT.md` itself was committed in `9ec4919`, before the Phase 3 run, and is unchanged by
the 3.0 merge: its blob is `e6c2e138bd548ad46b324ac9c8d25a435d8f01e0` at `9ec4919` and the same in
the working tree after `e101e8a`.

## Phase 1

**Branch:** `feature/cutover-baseline` → `develop`

**Commits, in order:**

1. `baseline: in-container suite counts at cutover` — 1.1. The measuring scripts, the JSON
   they emit and the document rendered from it. No number in `BASELINE.md` is typed.
2. `config: runtimes declared; python allowed under modules/ledger/python only` — 1.2. The
   runtime declaration, its schema, the check that enforces it as a **step** of the existing
   `requires-header` job, the Pester proof that the check goes red, and the regenerated policy
   document and PR template.
3. `docs: phase 1 flow proof and findings` — 1.3. This file and `FINDINGS.md`, carrying the
   pull request number, which does not exist until the branch is pushed.

**Copy-then-adapt:** not applicable to this phase. Phase 1 copies nothing from a sibling; the
first copy-then-adapt pair is Phase 2.

**What was measured, and where to re-run it:**

```powershell
pwsh -NoProfile -File scripts/Measure-Baseline.ps1 `
    -Json docs/plans/2026-09-22-substrate-cutover/baseline.json `
    -Markdown docs/plans/2026-09-22-substrate-cutover/BASELINE.md
```

| | |
|---|---|
| In-container checks that ran and passed | **127** (`continuity` 77, `forensic_chain` 28, `no_sabotage` 22), identical in both images |
| Suites that could not run in-container | 4 — see `FINDINGS.md` F10, F11, F12 |
| Substrate Pester at the start of the phase | **47** — clean worktree at `origin/develop` (`7cd58ca`) |
| Substrate Pester at the end of the phase | **62** — `Runtimes.Tests.ps1` adds 15 |

The end-of-phase figure, not the starting one, is what Phase 2's `+10` assertion is measured
against. `FINDINGS.md` F15 says why.

## Phase 2

**Branch:** `feature/module-policy` → `develop`

**Commits, in order:**

1. `f676d72` — `scaffold: copy claude.build.policy@3be10c4, unmodified`. Pre-staged over the GitHub
   API **before this run**, from a base that predates Phase 1. Not authored in this session and not
   rewritten by it.
2. `25e3328` — `Merge origin/develop into feature/module-policy`, 2.0. Two parents, `f676d72` and
   `918a88c`. No conflict, which the prompt named in advance as the expected outcome: `f676d72`
   touches only `modules/policy/**` and `modules/.gitkeep`, and develop touched neither.
3. `docs: record the phase 2 prompt and complete phase 1's flow-proof row` — 2.0b.
   `PHASE-2-PROMPT.md` and the Phase 1 row above.
4. `feat(policy): module + pester suite, 10/10` — 2.2. The port, the three fixtures, the module
   README, module discovery in `Invoke-Tests.ps1`, the moved `modules/` wall, and `FINDINGS.md`
   F20–F25.
5. `fix(policy): resolve the temp root cross-platform, not from $env:TEMP` — the repair of the one
   red check on PR #15. `$env:TEMP` is unset on `ubuntu-latest`, so three checks threw on a null
   path and check 10 cascaded: **68/72 on the runner against 72/72 on Windows**. `FINDINGS.md` F26.
   Pushed after the PR was opened, which is discussed under **the one push after 2.3** below.

**Copy-then-adapt, the first pair in this run:**

| | |
|---|---|
| Copy commit | `f676d72` |
| Source | `claude.build.policy@3be10c446b8b4d7c38e392ff4e3657dec8a51e1b` |
| Adapt commit | the 2.2 commit, which adds beside the copy and edits none of it |
| Files copied | 5, byte-identical |

The copy is verifiable without trusting this document. Every one of the five blobs has the same git
blob sha in the working tree as at the source commit — the shas are in `f676d72`'s own body, and
`git hash-object` reproduces all five:

```powershell
git hash-object -- modules/policy/claude.build.policy.psd1        # 8d295e8a216e7b143bea0966cc931511e83c5508
git hash-object -- modules/policy/claude.build.policy.psm1        # 72dc1ec6010897d56cb2ca3aa10351393b72d5ef
git hash-object -- modules/policy/tests/sandbox/policy_suite.ps1  # 527868ac067fae1d90c19799bf2aec7d8ea73a17
git hash-object -- modules/policy/docs/do-not.md                  # 4bec959724be5df80efb92f87ceb2644dafc9b18
git hash-object -- modules/policy/examples/parse-here.ps1         # f7d22ff40d74b01ef77c7e66f26370fe5915c082
```

**Errata, added in Phase 5.** The first two of those five paths no longer exist. The release
renamed `modules/policy/claude.build.policy.psd1` to `modules/policy/policy.psd1` and
`claude.build.policy.psm1` to `policy.psm1` — `FINDINGS.md` F47. The blobs above are still the
ones Phase 2 measured and are deliberately not restated: the `.psm1` still hashes to `72dc1ec6`
under its new name, because a rename moves a file and not its bytes, and the `.psd1` no longer
hashes to `8d295e8a` because that rename edited its `RootModule` line. Nothing else here changed,
and the commands are left as they were written so that what Phase 2 actually measured stays
legible.

Neither of 2.1's two repair paths was needed. `requires-header` and `trailer-guard` both pass on
`f676d72` as it stands, so `config/trailer-grandfather.txt` **still lists exactly one hash** and no
copied file was edited to gain a header.

**What was measured, and where to re-run it:**

```powershell
pwsh -NoProfile -File scripts/ci/Invoke-Tests.ps1
```

| | |
|---|---|
| Substrate Pester at the start of the phase | **62** — on the merge commit, before any 2.2 edit |
| Substrate Pester at the end of the phase | **72** |
| Delta | **+10**, exactly the run order's number |
| Ported checks | 10 of 10, one `It` per sandbox check, numbered to match |
| Fixture-backed | 3 — checks 2, 6, 7. `FINDINGS.md` F23 has the per-check table |
| First run on the runner | **68/72** — four red on `ubuntu-latest` from a Windows-only `$env:TEMP`, fixed in commit 5. `FINDINGS.md` F26 |

The total is 72 on both platforms; only the pass count differed, so the `+10` delta was never in
question — what was wrong was calling it green off a Windows-only run.

### The one push after 2.3

`PHASE-2-PROMPT.md` says *"Let automerge take it. Do not push after the PR is opened."* One commit
was pushed after PR #15 was opened, and it is the `$env:TEMP` fix.

Stated plainly rather than filed quietly, because it is an instruction not followed to the letter.
The reading taken: that sentence sits directly under *"Let automerge take it"* and guards the race
this document describes at the top — pushing a further commit to a branch whose automerge is already
armed. A **required check that is red** means automerge did not and cannot take it, so the sentence's
premise does not hold, and the run order the block amends prescribes the remedy for exactly this
case: *"If automerge does not merge within 10 minutes, read the run log, fix on the same branch,
push, repeat. Never merge by hand."* The block repealed nothing about red checks, and nothing here
was merged by hand.

The alternative reading — stop and park a red pull request — was available and was not taken. If it
was the intended one, this is the line to point at.

The 62 is not clean: on the merge commit the suite was **61 passed, 1 failed**, the failure being the
`modules/` wall test that the Phase 2.1 copy trips. `FINDINGS.md` F21 has it. The total of 62 is what
the `+10` is measured against and the wall fix does not move it — one `It` before, one `It` after —
so the delta measures the port and nothing else.

`BASELINE.md` was not touched by this phase, and `git log --oneline -- .../BASELINE.md` still shows
exactly one commit.

## Phase 3

**Branch:** `feature/module-plans` → `develop`

**Commits, in order:**

1. `04bcfe8` — `scaffold: copy plan validator from image.builder@a6b61dd, unmodified`. Pre-staged
   over the GitHub API **before this run**, from a base that predates Phase 1. Not authored in this
   session and not rewritten by it.
2. `9ec4919` — `docs: record the phase 3 prompt ahead of the run`. `PHASE-3-PROMPT.md`, committed
   before the work so the record precedes it.
3. `e101e8a` — `Merge origin/develop into feature/module-plans`, 3.0. Two parents, `9ec4919` and
   `b0fc2c4`. No conflict, which the prompt named in advance as the expected outcome.
4. `cdc5289` — `docs: complete phase 2's flow-proof row, open phase 3's`, 3.0b.
5. `feat(plans): module + pester suite` — 3.2. The manifest, the wrapper, the suite, seven fixtures,
   the module README, and `FINDINGS.md` F27–F34.

**Copy-then-adapt, the second pair in this run:**

| | |
|---|---|
| Copy commit | `04bcfe8` |
| Source | `claude.pwsh.image.builder@a6b61dd6ab3d4e2a61e05de6be92f2dfebcd72c1` |
| Adapt commit | the 3.2 commit, which adds beside the copy and edits none of it |
| Files copied | 3, byte-identical |

3.1 verifies the copy three ways — the commit body, the working tree, and the source repository —
and all three agree:

```powershell
git hash-object -- modules/plans/PlanValidator.ps1 modules/plans/schemas/plan.schema.json modules/plans/docs/plan-contract.md
git -C ../claude.pwsh.image.builder ls-tree a6b61dd -- src/PlanValidator.ps1 schemas/plan.schema.json plans/README.md
```

| Here | Source | Blob |
|---|---|---|
| `modules/plans/PlanValidator.ps1` | `src/PlanValidator.ps1` | `8e5da7682f212499e4fb33c2cdaafe1fb1aa2a09` |
| `modules/plans/schemas/plan.schema.json` | `schemas/plan.schema.json` | `ad219cb0a4503ca1854f612df84abe267413dc6a` |
| `modules/plans/docs/plan-contract.md` | `plans/README.md` | `b9c435354abf28f6511bee8d1dde2fe8ae6f915c` |

The suite asserts the first of those three on every run, computing the git blob id from the bytes on
disk rather than shelling out, so the module cannot quietly end up wrapping a different file.

Neither of 3.1's two repair paths was needed. `requires-header` and `trailer-guard` both pass on
`04bcfe8` as it stands — its line 1 is already `#Requires -Version 7.4` and it carries `who: claude`
— so `config/trailer-grandfather.txt` **still lists exactly one hash** and no copied file was edited
to gain a header.

**What was measured, and where to re-run it:**

```powershell
pwsh -NoProfile -File scripts/ci/Invoke-Tests.ps1
```

| | |
|---|---|
| Substrate Pester at the start of the phase | **72 — 72 passed, 0 failed**, on the merge commit `e101e8a`, before any 3.2 edit |
| Substrate Pester at the end of the phase | **83** |
| Delta | **+11**. The run order gives no expected delta for this phase |
| Fixtures | 7 plan JSON files under `modules/plans/tests/fixtures/` |
| Run with `TEMP` and `TMP` deleted from a child `pwsh` | **83/83** — F26's condition, checked before calling it green |

Phase 2's 62 was **61 passed, 1 failed** on its merge commit, because the Phase 2.1 copy tripped the
`modules/` wall test (F21). Phase 3's 72 is clean: F21 moved that wall to a named set that already
included `plans`, so the 3.1 copy lands inside it and nothing had to be repaired to merge.

**One line per `It`, which is the whole file:**

| `It` | What it is |
|---|---|
| `a` | the manifest imports, `Test-PlanStructure` is the only export, version `0.1.0`, floor `7.4`, and `PlanValidator.ps1` still hashes to blob `8e5da768` |
| `b` | a valid plan — `id`, two steps each with an `action`, `expected_output` — returns `$true` |
| `c1` | a plan missing `id` throws `Plan missing required field: id`, the copy's message verbatim |
| `c2` | a plan missing `steps` throws `Plan missing required field: steps` |
| `c3` | a plan missing `expected_output` throws `Plan missing required field: expected_output` |
| `d` | a step with no `action` throws `Plan step missing action.` — the validator's rule, which the schema does not have (F4) |
| `e` | `skills_to_build` **absent** passes; it is optional in the schema and optional to the validator (F3) |
| `f` | `skills_to_build` measured: a blank entry throws, an unknown name passes and nothing lists it (F30) |
| `g` | neither `plans.psm1` nor `PlanValidator.ps1` **calls** `Test-Json` — asserted over the parse tree and the token stream, not by grepping text (F32) |
| `i` | `-SchemaPath` defaults to the module's schema and is inert: a path that does not exist changes no verdict, and a plan the schema rejects (`id: 42`) still passes (F5, F27) |
| `h` | the suite wrote nothing under `modules/plans` — module-scoped snapshot, as policy's check 10 |

Eleven, not the ten `PHASE-3-PROMPT.md` enumerates. `i` is the addition and it is there because the
phase adds a parameter the copy does not have: `g` proves no schema validation is *called*, and `i`
proves none *happens*. F5's whole point is that neither may be claimed on the strength of a
parameter name, and a source grep alone does not establish that.

The suite's falsifiability was measured rather than asserted — `FINDINGS.md` F33 has the table,
including the one planted defect that correctly does not go red.

`BASELINE.md` was not touched by this phase either. `AGENTS.md` was not touched: F21's deferral of
its prose to Phase 5.1 stands, and F22's deferral of the policy manifest rename stands with it.
## Phase 4

**Branch:** `feature/module-ledger` → `develop`, cut from `develop` at `21a20d0`.

Phase 3's row above was completed here, the same way the two before it were. Measured:

```powershell
gh pr view 16 --json number,state,mergedAt,mergeCommit,baseRefName,headRefName
git log -1 --format='%H%n%P' 21a20d0
```

| | |
|---|---|
| PR | #16 — *Phase 3: plans module, validator wrapped and measured, Pester 72 -> 83* |
| State | `MERGED`, `2026-09-22T01:35:24Z` |
| Head → base | `feature/module-plans` → `develop` |
| Merge commit | `21a20d08eba49e41f832f7e1da63195141b5a46c` |
| Parents | `b0fc2c4fd176d27832e676f918b37fff07548032` `dfa5009816bb8c5668f97f154637f82bbeafd465` |
| Parent count | **2** — a merge, not a squash |
| Pester across the phase | **72 → 83**, `+11` |

**Commits, in order:**

1. `8dd85fe` — `scaffold: copy claude.build.ledger@d57938d src+docs+suites, unmodified`. Twelve
   files, byte for byte. Authored in this session, unlike Phases 2 and 3 whose copy commits were
   pre-staged over the API.
2. `054c798` — `feat(ledger): module + pester suites, python engine under modules/ledger/python`.
   The one-line manifest adaptation, both Pester suites, the burst helper, the blob fixture, the
   module README, `setup-python` in the pester job and three `.gitignore` rules.
3. `docs: phase 4 findings, falsification table and flow proof` — `FINDINGS.md` F35–F46,
   `falsify-ledger.ps1`, and this section.

No merge from `develop` was needed: the branch was cut from `21a20d0`, which is `develop`'s tip,
so there was nothing to catch up on. Phases 2 and 3 each opened with such a merge because their
copy commits predated Phase 1.

**Copy-then-adapt, the third pair in this run — and the first where the copy was made here:**

| | |
|---|---|
| Copy commit | `8dd85fe` |
| Source | `claude.build.ledger@d57938d1eed2b5df13435d7820826e50de30483d` |
| Adapt commit | `054c798`, which adds beside the copy and edits **one line of one file** |
| Files copied | 12, byte-identical |

4.2 asks for the copy to be verified three ways, and it was, before the commit was made: the
source repository at the copy sha, the source working tree, and this tree. All twelve agree in all
three, and the table is in `8dd85fe`'s body. Reproduce any row:

```powershell
git -C . rev-parse HEAD:modules/ledger/python/snake.py
git -C ../claude.build.ledger rev-parse d57938d:src/ledger/python/snake.py
```

| Here | Source | Blob |
|---|---|---|
| `modules/ledger/ledger.psd1` | `src/ledger/Ledger.psd1` | `0506e41c6426f00980deb4c2da84b5eaad639fc6` *(adapted in `054c798`)* |
| `modules/ledger/ledger.psm1` | `src/ledger/Ledger.psm1` | `37d63403e7f0e21c5a8aa34ac6f80bbacb792d5a` |
| `modules/ledger/python/__init__.py` | `src/ledger/python/__init__.py` | `23304ab6c6b309e76fa432a29d551032c9fbc637` |
| `modules/ledger/python/cli.py` | `src/ledger/python/cli.py` | `90dbd91f31b5964fb9e3b808da6239ff7b9553d6` |
| `modules/ledger/python/snake.py` | `src/ledger/python/snake.py` | `e9a4f06d77b00ca5807b31ed04ab6e5f7fc17ddb` |
| `modules/ledger/python/validators.py` | `src/ledger/python/validators.py` | `8f9bbbe4c2b475154fd43510ca0b610b6711aa4d` |
| `modules/ledger/python/requirements.txt` | `requirements.txt` | `d7f3e260185c6ff62fb019fee20b67e88f5d6a87` |
| `modules/ledger/docs/theory-of-operation.md` | `docs/theory-of-operation.md` | `3e4579539dbb805e55720d675dd85bdc32263272` |
| `modules/ledger/docs/commands.md` | `docs/commands.md` | `4561a6acdc810c18ad61c18db90e012514417afd` |
| `modules/ledger/tests/sandbox/ledger_chain.ps1` | `tests/sandbox/ledger_chain.ps1` | `2dbcbba94168d13a7193adf1e36381a2cea14309` |
| `modules/ledger/tests/sandbox/forensic_chain.ps1` | `tests/sandbox/forensic_chain.ps1` | `55b8c74403f6327d60a334969f8700cf06dfbe41` |
| `modules/ledger/tests/sandbox/fail_path.ps1` | `tests/sandbox/fail_path.ps1` | `02abe8bbeeab39e45d45970cdc75d8aa05d2e0b9` |

Eleven of the twelve are asserted on **every suite run**, from the bytes on disk, with no git
involved — `modules/ledger/tests/fixtures/copied-blobs.psd1` holds the table and
`ledger.Tests.ps1` recomputes `sha1("blob <len>\0" + content)` by hand. The twelfth, the manifest,
is asserted in reverse: undo its one adaptation in memory and blob `0506e41c` comes back, which
says the diff is that line and provably nothing else.

The copy landed at its **final** names. `Ledger.psd1` → `ledger.psd1` is a case-only rename, and
doing it as a `git mv` on a case-insensitive filesystem is a way to lose a byte for no gain.
Identity here is the blob sha, which is what the table is for.

Neither of the copy step's two repair paths was needed. `requires-header` passes on all four
copied `.ps1`/`.psm1` as they stand, so `config/trailer-grandfather.txt` **still lists exactly one
hash** and no copied file was edited to gain a header.

**What was measured, and where to re-run it:**

```powershell
pwsh -NoProfile -File scripts/ci/Invoke-Tests.ps1
pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/falsify-ledger.ps1
```

| | |
|---|---|
| Substrate Pester at the start of the phase | **83 — 83 passed, 0 failed**, on `develop` at `21a20d0`, before any Phase 4 file existed |
| Substrate Pester at the end of the phase | **167 — 167 passed, 0 failed** |
| Delta | **+84**. The run order gives no expected delta for this phase |
| Split, measured per file | `ledger.Tests.ps1` **66**, `python.Tests.ps1` **18** |
| Falsification | 10 planted defects, **all ten go red**; control 84/84. `FINDINGS.md` F41 |
| Python | 3.10.4 locally; `actions/setup-python@a26af69` pinned to 3.10 on the runner |

Phase 3's 83 was clean on its merge commit, and so is Phase 4's starting figure — no wall test had
to be repaired to let this copy land, because F21 had already moved the `modules/` wall to a named
set that includes `ledger`.

**The three things the phase prompt asked for by name, and where each one is:**

| Asked for | Where |
|---|---|
| chain append/verify round-trip | `ledger.Tests.ps1`, *"the chain — append and verify round-trip"*, 8 `It`s |
| tamper detection | *"the chain — tamper detection"*, 13 `It`s: a control, 9 mutations by `FullyQualifiedErrorId`, a re-hashed forgery, a corrupt read-back, and a blank line that must **not** count as a break |
| lock across tail-read + append | *"the lock"*, 2 `It`s: a foreign `FileShare.None` handle must make the append fail, and four concurrent `pwsh` processes must land 20 **distinct** records on one chain |
| no `ConvertTo-Json`/`Test-Json` on the chain, by parse not grep | *"no ConvertTo-Json, ConvertFrom-Json or Test-Json goes anywhere near the chain"*, 11 `It`s including four planted-defect twins — three that must fire and one that must **not**, on comments alone. **Scoped to the chain functions** — `FINDINGS.md` F39 says why the whole-file version was wrong and what the module's three real calls are doing |
| blob shas re-asserted by the suite from disk bytes | *"provenance — the copy is the copy"*, 16 `It`s |

The remaining 16 of the 66 are the module surface (8), the error surface (5) and the footprint
checks (3). `python.Tests.ps1`'s 18 split as the interpreter (3), the CLI (3), the no-SDK dry-run
path (5), the failure path (3) and the footprint (4). Counted from
`(Invoke-Pester -PassThru).Tests`, not from reading the file.
| `LedgerReceipt.ps1` not copied | asserted, not merely omitted: an `It` fails if it appears anywhere under `modules/`. `FINDINGS.md` F29 |

**What was NOT done, and is named rather than implied:** `-SchemaPath` (F27/F28) was not touched —
that decision waits for Phase 6. `AGENTS.md` was not touched; F21's and F22's deferrals to Phase 5
both stand. `BASELINE.md` was not touched, and `git log --oneline -- .../BASELINE.md` still shows
exactly one commit. `scripts/forensic.ps1` was not touched — `FINDINGS.md` F42 measured the drift
the run order anticipated and there is none. Four subjects the sandbox originals covered are not
covered by the port, each with its reason, in `FINDINGS.md` F44.

## Phase 5

**Branch:** `feature/release-0.1.0` → `develop`, then `develop` → `main`. Cut from `develop` at
`f7cbb11`.

Phase 4's row above was completed here, the same way the three before it were. Measured:

```powershell
gh pr view 17 --json number,state,mergedAt,mergeCommit,baseRefName,headRefName
git log -1 --format='%H%n%P' f7cbb11
```

| | |
|---|---|
| PR | #17 — *Phase 4: ledger module, engine wrapped and measured, Pester 83 -> 167* |
| State | `MERGED`, `2026-09-22T02:26:29Z` |
| Head → base | `feature/module-ledger` → `develop` |
| Merge commit | `f7cbb1169059515a2c25941ab0d16b00d2d0484f` |
| Parents | `21a20d08eba49e41f832f7e1da63195141b5a46c` `10ace432459ef6626a762606ce8f5e1c79321694` |
| Parent count | **2** — a merge, not a squash |
| Pester across the phase | **83 → 167**, `+84` |

**Commits, in order:**

1. `405cdfc` — `refactor(policy): rename the manifest to policy.psd1, module name is now policy`.
   The F22 decision taken rather than deferred a third time: two `git mv`s, one manifest line, two
   `It`s and one fixture data file. `FINDINGS.md` F47.
2. `03b9532` — `feat: measure per-module Pester counts from the run instead of by hand`.
   `scripts/Measure-Modules.ps1`, the source of every per-module number in `README.md`,
   `REPORT.md` and `RELEASE-NOTES.md`.
3. `2d803ef` — `fix: Measure-Modules writes -Json to an absolute path`. Found by writing
   `verify.ps1`, which needs the counts without dirtying the tree it is measuring.
4. `docs: release 0.1.0 — status, wall, report, release notes, findings, flow proof` — this
   section, `REPORT.md`, `RELEASE-NOTES.md`, `FINDINGS.md` F47–F52, the README status table and
   the AGENTS.md wall.
5. `docs: hashes and verify for the substrate cutover run` — `verify.ps1` and `HASHES.txt`, the
   transcript closed before the hashes were taken.
6. `forensic: seq 6 — substrate-modules-landed` — appended after `COMBINED` existed to put in it.

**Copy-then-adapt:** not applicable. Phase 5 copies nothing from a sibling; it releases what
Phases 2–4 copied. It is, however, the first phase to **edit** a file inside a module that had
already landed — the policy manifest — and that is why the rename is its own commit with its own
falsification table rather than a line in a docs commit.

**What was measured, and where to re-run it:**

```powershell
pwsh -NoProfile -File scripts/Measure-Modules.ps1
pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/verify.ps1
```

| | |
|---|---|
| Substrate Pester at the start of the phase | **167 — 167 passed, 0 failed**, on `develop` at `f7cbb11` |
| Substrate Pester at the end of the phase | **167 — 167 passed, 0 failed** |
| Delta | **0**. A release phase whose test count moves has done something other than release |
| Per module | `ledger` **84**, `policy` **10**, `plans` **11**, the repository's own `tests/` **62** |
| Policy suite across the rename | **10 → 10**; three planted defects red, control green |

**What was NOT done, and is named rather than implied:** `-SchemaPath` (F27/F28) was not touched
— that decision still waits for Phase 6. `BASELINE.md` was not touched, and
`git log --oneline -- .../BASELINE.md` still shows exactly one commit. `config/repo.json`'s
`review.mode` is still `"auto"`; it flips in Phase 6, and flipping it here would have made this
the pull request that stopped its own automerge. `modules/ledger/ledger.psm1` is untouched and
still hashes to blob `37d63403e7f0e21c5a8aa34ac6f80bbacb792d5a`, which `verify.ps1` asserts on
every run. F44's TEST 10 hole is **not** closed: `LedgerResultMismatch` is still unexercised, and
`RELEASE-NOTES.md` names it as a known gap rather than letting a tag imply otherwise.

## Out-of-order: migration manifest

**Not a phase, and deliberately not numbered.** It is absent from the Rows table above for that
reason: that table is one row per phase, and counting this as Phase 5.5 or Phase 6 would make the
cutover's own sequence unreadable. `docs/migration/HANDOFF.md` calls it "out-of-order work, not a
phase" and says to run it *between* phases. Phase 6 is halted at 6.1 (PR #26), so this ran in that
window rather than beside anything in flight.

| | |
|---|---|
| Branch | `feature/migration-manifest` |
| PR | [#20](https://github.com/JerryBalmer1/claude.agent.substrate/pull/20) → `develop` |
| Merge commit | `ad1425a8413357e1e43da2dddc6efe9dd4b7ba8b` |
| Parents | `b8b2abe2b883ad71ca12fed0f1489e1c03154b72` `e81848ce1ceb64f37372f151f09c2d9bfe23ea65` |
| Parent count | **2** — a merge, not a squash |
| Merged | `2026-09-22T05:14:52Z`, by the `automerge` workflow on the `workflow_run` trigger, `review.mode = auto`, all 6 required checks green |
| Authored | over the GitHub API off `develop` at `f7cbb11`, left as a draft on purpose |
| Completed | locally, `HANDOFF.md` steps 0-4, on a merge of `origin/develop` at `72026cb` |
| Landed | `docs/migration/**`, `schemas/migration.schema.json`, `scripts/New-MigrationReport.ps1`, `scripts/Measure-MigrationSymbols.ps1`, `tests/Migration.Tests.ps1`, `FINDINGS.md` F59 |
| Pester | **167 → 179**, `+12` |

`develop` was **merged into** this branch, not rebased onto it — sixteen commits, no conflict, as
the handoff predicted. The branch adds files and touches nothing under `modules/`, `config/` or
`.github/`, and neither `BASELINE.md` nor `AGENTS.md`.

**What this pass changed that the handoff did not anticipate,** stated here because a handoff that
is followed exactly is rare enough that the exceptions are the interesting part:

- `New-MigrationReport.ps1 -Check` could never pass on Windows — CRLF from `AppendLine` compared
  against a file normalised to LF. Fixed in the generator, not by editing the markdown.
- The `not_migrated` leak check false-positived on policy's `build.ps1`, whose own `reason` field
  says it was replaced by a fixture of the same name. `allowed_in_tree` now excuses exact paths
  and nothing else, with an anti-padding test holding that line.
- Phase 5's `405cdfc` renamed the policy manifest, which this manifest's own note said would be a
  later decision. Measurement won; the rows moved to the tree.
- **F59**: the `plans` source was pinned to `e96bba8`, the clone HEAD, not `a6b61dd`, the commit
  `04bcfe8` says it copied from. Measured at the wrong pin, symbol coverage reported a missing
  export that does not exist.

**Falsification, because every claim above is a test that was watched to fail:** five twins across
the three commits — drop `allowed_in_tree`, point it at a file that is not there, corrupt a landed
blob, relabel an adapted item as landed, relabel a landed item as adapted. Each drove exactly the
expected red; each was restored from the original in a `finally`; the suite was green before and
after every one.