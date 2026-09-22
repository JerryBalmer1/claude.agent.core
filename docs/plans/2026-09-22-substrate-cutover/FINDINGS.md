# FINDINGS — substrate cutover 2026-09-22

Everything measured during this run that disagrees with the run order, is out of scope, or is
a decision the next phase has to know about. A finding is not a complaint; it is the part of
the work that did not become a commit, written down so the next pass does not rediscover it.

The run order's standing clause applies throughout: **where it states an expected value and
the measurement disagrees, the measurement wins.**

Appended per phase. Phase 1 findings are `F6` onward; `F1`–`F5` were measured before this run
started and are carried in unchanged.

---

## Carried in — measured over the GitHub API while the module branches were staged

These five were recorded in the commit bodies of `feature/module-policy` and
`feature/module-plans` before this run began. They are restated here so the phase that acts on
them does not have to go and read a commit message, and they are re-verified in their own
phase rather than trusted.

### F1 — `policy_suite.ps1` checks 2, 6 and 7 cannot run in substrate

`policy_suite.ps1` depends on `build.ps1` and on `../claude.build.ledger` and
`../claude.build.fuzzer` by relative path. None of those exist here. The run order's Phase 2
expectation — *"the sandbox original stays in place and still passes … both must report 10"* —
**cannot hold unmodified**.

Phase 2.2: port checks 1, 3, 4, 5, 8, 9, 10 one-to-one; write fixture-backed equivalents for
2, 6 and 7 and record the substitution per check. The sandbox original stays in the tree,
recorded as *not runnable here, kept as provenance*.

### F2 — the plans entry function is `Test-PlanStructure`, not `Test-Plan`

Measured again this phase, from image.builder's own caller: `build/tasks/Plan.build.ps1` calls
`Test-PlanStructure -Plan $plan -SchemaPath $schema` and throws if that command is not defined
after dot-sourcing the validator. Phase 3.2 wraps the name that exists.

### F3 — `skills_to_build` is OPTIONAL in `plan.schema.json`

Only `id`, `steps` and `expected_output` are required. The run order's Phase 3.2 lists
`skills_to_build[]` among the required fields whose absence must fail. **It must not be tested
as a required field** — that test would assert the opposite of the contract.

### F4 — the validator and the schema disagree about what a step is

The validator requires every step to carry a non-empty `action`. The schema says nothing about
step shape. Phase 3.2: **the validator's behaviour is the contract**, because it is what
image.builder actually runs. Record the gap. Do not edit the schema to match and do not loosen
the validator.

### F5 — the validator never reads the schema

It takes a `-SchemaPath` and performs hand-written checks. Phase 3.2 wraps `Test-PlanStructure`
as-is and additionally exposes the schema path; **do not** bolt on `Test-Json` in that phase.
Recorded as a later decision, so that "the module validates against the schema" is never
claimed on the strength of a parameter name.

---

## Phase 1

### F6 — DEVIATION: image.builder is not on its default branch

The run order's preflight expects *"ledger/policy/image.builder on their default branches"*.

| Repo | Branch | HEAD | Dirty |
|---|---|---|---|
| `claude.build.ledger` | `feature/grok-confession-record` | `d57938d` | 0 |
| `claude.build.policy` | `main` | `3be10c4` | 0 |
| `claude.pwsh.image.builder` | `feature/oneshot-2026-09-21` | `e96bba8` | 0 |

`origin/HEAD` in image.builder points at `main`, so its default branch is `main` and it is not
on it. Both clones are clean, so nothing is at risk of being clobbered, but **the images this
baseline measures were built from `e96bba8`, a feature branch**, not from image.builder's
default branch. That sha is recorded in `BASELINE.md` as a source pin for exactly this reason.
Phase 6 must re-check which branch image.builder is on before branching from it.

### F7 — image.builder has its own `config/repo.json`, and it pins a different Pester

It ported substrate's pattern, as the run order warned. Measured:

| | substrate | image.builder |
|---|---|---|
| `flow` | `feature/* -> develop`, `develop -> main` | identical |
| `required_checks` | the same six | identical |
| `review.mode` | `auto` | `auto` |
| `tooling.pester` | **5.7.1** | **6.1.0** |

Phase 6 therefore goes through a flow substrate already understands. The Pester difference is
the thing to carry forward: a suite written here against 5.7.1 is run there under 6.1.0, and
the two majors do not share a configuration API. Anything substrate ships that image.builder
executes must be version-agnostic or pinned at the point of use.

### F8 — `tests/plan.failfirst.ps1` does not exist and could not be run

Run order 1.1c: *"Also run `tests/plan.failfirst.ps1` and record that it fails red (that is its
contract; a green there is a finding)."*

There is no such file. It was **deliberately deleted**, and the reason is recorded in
image.builder's own `build/tasks/Plan.build.ps1` header: the `Test.FailFirst` task wrote the
test out if it was missing, ran it, and treated *any* failure as success — and the test it wrote
called `Test-PlanStructure`, which did not exist, so "the fail-first test failed as expected"
was really "command not found". It would have kept reporting success after someone shipped a
validator that accepted every plan on earth.

`tests/Plan.Tests.ps1` replaces it. image.builder's `tests/` now holds eight Pester files
(`Entrypoint`, `Env`, `Image`, `Plan`, `Repo`, `Sentinel`, `Settings`, `Trailers`) plus
`TestHelpers.psm1` and `run.ps1`, not the single file the run order describes.

**Nothing was run in its place.** Running image.builder's Pester suite is not what 1.1c asked
for and is not this phase's scope.

### F9 — the suites are not in the image; they have to be mounted

Neither `Dockerfile` copies `tests/sandbox/` into an image. Both copy exactly
`vendor/claude.build.ledger/src/ledger/` to `/opt/leash/ledger/`. "Run the suites
in-container" therefore means bind-mounting them.

`scripts/Measure-Baseline.ps1` mounts a **clone of the pinned tree in a temp directory**, not
image.builder's own submodule working tree. That is not fastidiousness: `ledger_chain.ps1`
appends two receipts to the real ledger by design and `fuzzer_import.ps1` writes fixtures, so
mounting the sibling would have the baseline dirty a repository that Phases 1–5 are forbidden
to write to. The script asserts the clone's tree object equals the vendored tree before it runs
anything, so the bytes are the same bytes.

`build/container.gitconfig` in image.builder documents the other wall this hits —
`safe.directory` on a bind mount — and the measuring script solves it the same way, with a
global-scope config file written into the temp tree.

### F10 — neither image provides a `python` command, and the snake is Python

The single most consequential measurement in this baseline.

| Image | `python` | `python3` | `pip` |
|---|---|---|---|
| `claude.pwsh.image.leash:run-01` | absent | **absent** | absent |
| `claude.pwsh.image.developer:run-01` | **absent** | `Python 3.12.3` | present |

The leash `Dockerfile` installs no Python at all. The developer `Dockerfile` installs
`python3` and `python3-pip` with the comment *"the developer image runs the Ledger snake, and
the snake is Python"* — but `python3` is not `python`, and `Ledger.psm1` defaults
`-PythonPath 'python'` and resolves it with `Get-Command -Name 'python'`.

Consequence: **`ledger_chain.ps1` and `fail_path.ps1` cannot run in either image as shipped.**
The two suites that exercise the snake contribute zero checks to the in-container baseline.

Not fixed here. Fixing it means editing a sibling repository, which Phases 1–5 forbid, and the
right fix is not obvious from here — a `python -> python3` symlink in the image, a
`-PythonPath` default that probes both, or a declared dependency — and choosing the wrong one
is annoying to undo. It is recorded so that Phase 4's triage and Phase 6's comparison both
start from the true number rather than from an assumption that these suites ran.

### F11 — `fuzzer_import.ps1` cannot run in-container, as the triage predicted

It resolves `../../claude.build.fuzzer` and fails on the empty path before its first check.
The fuzzer is neither in the mount nor in the image. This confirms the run order's Phase 4
triage line without needing to open the file: **not substrate's**, destination
`claude.agent.tools`. Recorded, not copied.

### F12 — `hook_pre_tool.ps1` aborts after 11 passing checks

Exit 1 at `New-Fixture`, `tests/sandbox/hook_pre_tool.ps1:230`, inside check 2. Eleven checks
had passed by then. It is a container concern by the run order's triage — destination
`claude.agent.images` — so it is not substrate's to repair, but the partial count is recorded
so that Phase 6 can tell *"aborted at 11"* from *"absent"*. Those are not the same event and a
table that renders them identically is how a regression gets waved through.

### F13 — the number the definition of done is measured against is 127

Three suites run to their own summary line in-container, and they are **identical in both
images**:

| Suite | Checks |
|---|---|
| `continuity.ps1` | 77 |
| `forensic_chain.ps1` | 28 |
| `no_sabotage.ps1` | 22 |
| **Total** | **127** |

Phase 6 expects these three at exactly these counts. `fuzzer_import.ps1` and
`hook_pre_tool.ps1` are the two known removals; `ledger_chain.ps1` and `fail_path.ps1` are
absent from the total for the reason in F10, not by design, and that distinction must survive
into the Phase 6 table.

### F14 — the submodule pin is behind the sibling's HEAD, so the pin is the baseline

| | |
|---|---|
| `vendor/claude.build.ledger` pinned at | `ed9c9d79856b4590b64eb2f0229dee8775a903d5` |
| `claude.build.ledger` HEAD | `d57938d1eed2b5df13435d7820826e50de30483d` |
| Pinned worktree in sync, undirty | yes |

One commit apart. The baseline measures **the pin**, because the pin is what image.builder
ships. The measuring script refuses to run if the vendored worktree and the recorded gitlink
disagree, rather than measuring whatever happens to be checked out.

It also reads the pin from `git ls-tree` rather than `git submodule status`: that command's
first character is the in-sync flag, and a trim eats it silently. The first version of this
script did exactly that and then failed to parse its own output.

### F15 — the starting Pester total is 47, but Phase 2 must compare against 62

Run order 1.0 expects 47 and 47 is what was measured — in a **clean worktree at
`origin/develop` (`7cd58ca`)**, not in the Phase 1 working tree.

That distinction is load-bearing. The first rendered `BASELINE.md` reported *"47 total, 45
passed, 2 failed"*, because the suite ran against a working tree that already held Phase 1.2's
config edits with the policy document not yet regenerated. The number was real; it was a
measurement of the wrong thing. `Measure-Baseline.ps1` now creates a throwaway git worktree at
the baseline ref and measures there, so the baseline cannot be contaminated by the work it is
the baseline for.

**Phase 1 ends at 62.** `tests/Runtimes.Tests.ps1` adds 15 tests. Run order 2.2 says *"Assert
the total count went up by exactly 10 over the Phase 1 recorded total"* — the number that
assertion starts from is **62**, not the 47 in `BASELINE.md`. `BASELINE.md` deliberately
records only the starting figure, because it is the cutover baseline and a baseline that moves
is not a baseline.

### F16 — the PowerShell floor is now stated twice, on purpose, with a guard

Run order 1.2a specifies `runtimes.powershell` while `scripts.requires_version` already exists.
The repository now declares its PowerShell floor in two places, which is normally exactly the
defect this repo exists to prevent.

Kept as specified, with the duplication made falsifiable rather than argued about:
`Test-Runtimes.ps1` fails if the two are not equal, and `tests/Runtimes.Tests.ps1` drives that
check over a config with `7.2` in one of them and asserts it goes red. A floor stated twice and
checked never is a coincidence; stated twice and checked is redundancy.

### F17 — the runtime check is a STEP, not a seventh job

Run order 1.2a: *"do NOT add a new required check name in this phase"*. `Test-Runtimes.ps1`
runs as a second step of the existing `requires-header` job, so the set of ci.yml job keys is
still exactly `config.required_checks` and `generated-match-config` stays green. A newly
required check name that branch protection has never seen is a check that can go red while the
merge proceeds anyway.

The physical proof the run order asked for is in `TRANSCRIPT.log`: a `.py` planted in
`scripts/`, **staged** (closeout F-C6 — the check reads `git ls-files`, so an unstaged file is
invisible and the proof would be vacuous), exit 1; removed, exit 0. The unit version of the
same proof is in `tests/Runtimes.Tests.ps1` and runs on every CI run thereafter, per the
closeout's F-C2 reasoning.

### F18 — `Start-Transcript` records the host session, not a child process

Run order 1.0 says `Start-Transcript` at the top of the phase. Two things about this
environment break the naive reading, and both were found the hard way.

**It cannot span invocations.** Each shell invocation here is a separate process, so the
transcript is opened and closed around each block of work rather than once for the phase. The
Phase 5 instruction to `Stop-Transcript` before hashing is satisfied by every call already
having done so in a `finally`.

**It does not capture a child `pwsh`.** `Start-Transcript` records the host's own output
streams. `pwsh -NoProfile -File <script>` writes to its own console, so the first transcript
of this phase contained the section headers, the exit codes and none of the measurements —
6 KB of frame around an empty picture. The measuring run is now piped through `Write-Host`, and
the final transcript is a single run that covers preflight, the in-container measurement and
the 1.2 proof, so that the numbers in `BASELINE.md` and the run that produced them are the same
run rather than two runs that agree.

### F19 — three defects in the measuring script, caught before any number was committed

Recorded because "the script worked first time" and "the script was never wrong" are not the
same claim, and the second one is the only one worth making.

1. `@(Get-GitValue ... -split "``n")` — PowerShell bound `-split` as a parameter of the
   function. Fixed with parentheses; the comment stays in the file.
2. `git submodule status` parsed after a `.Trim()` that ate the leading in-sync flag. Replaced
   with `git ls-tree`, which states the gitlink outright.
3. ANSI escape sequences from pwsh's colourised errors reached the committed JSON and the
   rendered table. pwsh colourises stderr even when it is redirected to a file. Stripped at
   the point of capture.

A fourth was a judgement, not a bug: a suite that passes eleven checks and then dies has
`passed=11 failed=0 exit=1`, and reporting that as `RED 11/11` reads as a contradiction.
`ABORTED` is now its own status and its partial count is excluded from the totals.

---

## Phase 2

### F20 — the Phase 2 prompt numbers findings from F15; the file was already at F19

`PHASE-2-PROMPT.md` says *"any new findings numbered continuing from F15"*. Phase 1 landed `F16`,
`F17`, `F18` and `F19`, so continuing from F15 would have overwritten four of them.

Numbering continues from **F19**. This is the run order's standing clause working in the smallest
possible way — the block states a value, the file disagrees, the file is what is measurable, so the
file wins and the discrepancy is written down rather than quietly reconciled. Nothing else in the
Phase 2 block was found to be stale.

### F21 — the wall is executable, and it went red in Phase 2 while its prose is scheduled for Phase 5

`tests/Skeleton.Tests.ps1` carried `It 'modules/ contains nothing but .gitkeep'`. That is AGENTS.md's
wall expressed as a test, and the Phase 2.1 copy trips it the moment it lands: measured on the merge
commit, **62 total, 61 passed, 1 failed**, the one failure being that test.

The run order did not anticipate this. Phase 5.1 schedules the **prose** update — *"Update AGENTS.md's
wall: 'Module code' is no longer forbidden"* — three phases after the test that encodes the same rule
goes red. A red `pester` check blocks automerge, so Phase 2 cannot merge on the run order's schedule.

Fixed here, by moving the wall rather than removing it. The test is now
`It 'modules/ holds only the modules a run order named'`, and it fails on a `modules/<unnamed>/`
subtree or a loose file at the top of `modules/` — the two things the original actually caught. The
named set is `ledger`, `policy`, `plans`, which is exactly what the run order's WHAT table authorises,
and the `-Because` cites the run order by path so the authority for the change is in the failure
message.

**It is one `It` before and one `It` after**, so the Pester total is unaffected by it and the `+10`
delta below measures the port and nothing else.

`AGENTS.md`'s prose is **deliberately left stale** — it still reads *"No `src/`, no `modules/` beyond
`.gitkeep`. Substrate is currently a skeleton."* Editing it is Phase 5.1's, it is not in the Phase 2
block's 2.2 list, and a wall rewritten in the phase that first crosses it is a wall rewritten by the
party it binds. Until Phase 5.1, the test is the authoritative statement of the wall and the prose
is behind it. Anyone reading `AGENTS.md` between now and then will be misled, which is why it is here.

### F22 — the manifest was NOT renamed, because the newer block requires check 1 to port one-to-one

Run order 2.2 says: *"Manifest: rename to `modules/policy/policy.psd1` / `policy.psm1`."*
`PHASE-2-PROMPT.md`, which is newer and overrides, says: *"Checks 1,3,4,5,8,9,10 port one-to-one."*

Those two cannot both hold. Sandbox check 1 asserts `Get-Module -Name 'claude.build.policy'`, the
module version and the export list — a rename changes the module's name, so the check would have to
be rewritten rather than ported, and it is named in the port-one-to-one list.

The newer block wins, per its own first line. **No rename in Phase 2.** The import path stays
`modules/policy/claude.build.policy.psd1` and the module name stays `claude.build.policy`.

What this costs: the README's *"Renamed from"* line became *"Copied from"*, and Phase 5's README, which
names the three modules bare, will describe directories (`modules/policy/`) rather than manifest
filenames. The directory names are already bare, so nothing downstream needs the rename. What it buys:
check 1 is a genuine port, and a reviewer diffing the adapt commit against
`claude.build.policy@3be10c4` sees no change to the module's identity at all.

The rename remains available to any later phase that wants it. It is a two-line change plus the
`RootModule` key, and it is cheaper to do later than to undo.

### F23 — what each of the ten checks became

Checks 2, 6 and 7 are fixture-backed for the reason F1 recorded before the copy. Three of the
seven "one-to-one" checks also needed their target retargeted inside the module, and saying they
ported unchanged would be false.

| Check | Original dependency | Now | What it proves that the original proved |
|---|---|---|---|
| 1 | — | one-to-one | manifest imports, `Get-PolicyRules` is the only export, version `0.1.0`, `PowerShellVersion` `7.4` |
| **2** | `<repo>/build.ps1` | `tests/fixtures/build/build.ps1` + `build.json` | a child `pwsh` reads the **manifest** and reports the identity: exit 0, stdout naming `0.1.0` and `claude.build.policy`. The version and name come out of the manifest, and a `build.json` that disagrees throws — which was the original `build.ps1`'s actual work, not the printing |
| 3 | — | one-to-one | a missing path throws `PolicyPathNotFound` |
| 4 | `<repo>` root | `modules/policy/` root | the directory walk yields well-formed rules — eight properties, 64-hex `Hash`, five closed vocabularies, unique `Id`s, `Source` among the three walked names. **Retargeted:** substrate's own root yields exactly **1** rule, from a single `AGENTS.md` wall bullet that Phase 5.1 is scheduled to edit; the module root yields **14** from the `docs/do-not.md` that was copied with it and is frozen |
| 5 | `<repo>/AGENTS.md` | `modules/policy/docs/do-not.md` | `Hash` per `Id` is identical across two parses of one file. **Retargeted** for the same reason as check 4 |
| **6** | `../claude.build.ledger/AGENTS.md` | `tests/fixtures/sibling-agents.md` | an `AGENTS.md`-shaped source yields at least one `module`-or-`law` rule mentioning import or Ledger. The fixture restates the sibling's import law so that all three parser paths the original hit still fire: law-token bullets (pattern 1), repo names beside `import` (pattern 3), and `Ledger` appearing bare rather than only as the tail of `claude.build.ledger` |
| **7** | `../claude.build.fuzzer/docs/do-not.md` | `tests/fixtures/sibling-do-not.md` | a `do-not.md`-shaped source yields at least one rule. Five bullets across three law tokens, two of them pairing a prohibition with a `tests/` or `.ledger/` path token, so pattern 4 fires too — the original's bar was "at least one rule", which a one-line file would clear while testing almost nothing |
| 8 | — | one-to-one | a no-law file and an empty file each yield zero rules and do not throw |
| 9 | — | one-to-one | a `- Do not import Ledger` bullet yields a `halt`/`none` law rule **and** the module import rule from the same line |
| 10 | `<repo>` root snapshot | `modules/policy/` root snapshot | parsing wrote nothing and `$env:TEMP` is clean. **Retargeted twice**, below |

Check 10's two deviations, stated rather than buried:

1. **The snapshot root is the module, not the repository.** The original's repo *was* the module. Here
   the module is a subtree of a repository whose other suites legitimately rewrite files during the
   same Pester run — `tests/Generated.Tests.ps1` mutates `docs/POLICY.md` in place to prove
   `generated-match-config` goes red. A whole-repo snapshot would be measuring those suites instead
   of this one, and would be flaky on their ordering.
2. **The surviving-file assertion changed target.** The original asserted `tests/sandbox/.gitkeep`
   survived. The copy brought no `.gitkeep` into `modules/policy/tests/sandbox/`; the provenance
   script is what must survive there, so `policy_suite.ps1` is asserted present *and* hash-identical
   to its pre-run hash. That is strictly stronger than the original's existence check.

The port is falsifiable, which was checked rather than assumed. Against a throwaway copy of the
module in `$env:TEMP`:

| Planted defect | Red |
|---|---|
| none (control) | — 10/10 pass |
| `ModuleVersion` `0.1.0` → `0.2.0` | check 1, check 2 |
| `docs/do-not.md` blanked | check 4, check 5 |
| law rules `halt` → `log` | check 9 |

Check 2's fixture failed on *"build.json version '0.1.0' does not match manifest ModuleVersion
'0.2.0'"*, which is the fixture doing the original's job rather than echoing a constant.

### F24 — `modules/policy/examples/parse-here.ps1` cannot run as copied, and was left that way

It resolves its manifest at `../src/claude.build.policy/claude.build.policy.psd1`, relative to
`examples/` in the source repo. That path does not exist in substrate: the copy flattened
`src/claude.build.policy/**` into `modules/policy/**`, so the manifest is now one level up, at
`../claude.build.policy.psd1`.

**Not fixed.** It is not in the 2.2 list, nothing runs it, `requires-header` passes on it, and the
copy-then-adapt rule exists so that a reviewer diffing the adapt commit against
`claude.build.policy@3be10c4` sees only what was authorised. A one-line drive-by would be invisible
in that diff's intent.

The fix, for whoever takes it: in `modules/policy/examples/parse-here.ps1`, the manifest join becomes
`Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'claude.build.policy.psd1'`. It
is a broken example shipping inside a module either way, so it should not survive Phase 5.

### F25 — `PHASE-2-PROMPT.md` was authored with a bash heredoc, against AGENTS.md's no-bash rule

Self-reported. AGENTS.md says *"No bash, no sh, no heredocs, no `cat >`"*. One file in this phase,
`docs/plans/2026-09-22-substrate-cutover/PHASE-2-PROMPT.md`, was written with `cat > … <<'EOF'`
because the harness session was configured to prefer a POSIX shell. Every other file in both commits
was written with PowerShell, and every check and measurement was run through `pwsh -NoProfile`.

No bash reached the tree: the artifact is LF-only, BOM-free and byte-verified, and it contains no
script. The rule's purpose — that nothing in this repository depends on a POSIX shell — is intact.
The rule as written was still broken, by the tool that authored a file rather than by the file, and
a rule that is only reported when the output looks wrong is not being enforced.

### F26 — the sandbox suites are Windows-only via `$env:TEMP`, and CI is `ubuntu-latest`

**This one was found by CI, not by me, after I had already reported the port green.** Worth stating
in that order, because "72/72" and "72/72 on the only platform I ran it on" are different claims and
I made the first one.

`$env:TEMP` is a Windows environment variable. On the `ubuntu-latest` runner it is **unset**, so
`Join-Path -Path $env:TEMP -ChildPath …` throws
`ParameterBindingValidationException: Cannot bind argument to parameter 'Path' because it is null`.

Measured on PR #15, run `35672303710`, against a port that passes 72/72 on Windows:

| | Windows (local) | `ubuntu-latest` (CI) |
|---|---|---|
| Total | 72 | 72 |
| Passed | **72** | **68** |
| Failed | 0 | **4** — checks 3, 8, 9, and 10 by cascade |

Checks 3, 8 and 9 each build a path under `$env:TEMP`. Check 10 then failed on its own
anti-vacuity guard — `$script:TempFiles.Count | Should -Be 3 … but got 0` — which is the guard
doing exactly its job: without it, check 10 would have compared an unchanged snapshot to itself,
found nothing written, and reported **green** while three checks upstream had already died. A
cleanup assertion over an empty list is the most flattering possible lie in this file and it is the
one thing there that had to be asserted rather than assumed.

Fixed by resolving the temp root **once**, in `BeforeAll`, as
`$script:TempRoot = [System.IO.Path]::GetTempPath()`, which is correct on both platforms — on Linux
`/tmp/`, on Windows `TMP` then `TEMP` then `USERPROFILE` then the Windows directory, so it is also
resilient to the variable simply being absent. Proved under the failing condition rather than
assumed: the suite was re-run in a child `pwsh` with both `TEMP` and `TMP` deleted from the
environment, and reported **10/10**.

The port inherited this from its source. `tests/sandbox/policy_suite.ps1` uses `$env:TEMP` in three
places and its own `.DESCRIPTION` advertises it; it is Windows-only and always was, which nothing
noticed while it only ever ran on a Windows workstation. **The sandbox original is deliberately not
fixed** — it is provenance, byte-identical to `claude.build.policy@3be10c4`, and it does not run here.

**This is a Phase 4 problem at five times the scale, and it should be read before Phase 4.2 starts.**
Phase 4 ports `ledger_chain.ps1`, `forensic_chain.ps1`, `fail_path.ps1`, `no_sabotage.ps1` and
possibly `continuity.ps1` from `claude.build.ledger`, where `$env:TEMP` is not incidental but
structural — that repo's `AGENTS.md` states that `ledger_chain.ps1`'s TEST 6 fixtures live in
`$env:TEMP` and are removed in a `finally`, and `demo-sixty.ps1` builds a throwaway project there.
Every one of those is a Windows-only dependency that will pass on a workstation and fail on the
runner, and each will fail with the same unhelpful null-binding message some distance from its cause.

Two consequences worth carrying forward:

1. Phase 4's ports should take the temp root from `[System.IO.Path]::GetTempPath()` from the start,
   not discover this five more times.
2. **A suite is not green until it is green on the runner.** Local `pwsh` on Windows and
   `ubuntu-latest` are different platforms, and this repository's only gate is the second one.

---

## Phase 3

Numbering continues from **F26**, which is where Phase 2 left the file.

### F27 — the copied validator has no `-SchemaPath`, so nothing can be passed through to it

`PHASE-3-PROMPT.md` 3.2: *"SchemaPath: expose it as a parameter defaulting to
`modules/plans/schemas/plan.schema.json` relative to `$PSScriptRoot`. **It is passed through to
`Test-PlanStructure` exactly as image.builder passes it.**"* F5, restated at the top of this file,
says the validator *"takes a `-SchemaPath` and performs hand-written checks"*.

Measured against the copy, blob `8e5da7682f212499e4fb33c2cdaafe1fb1aa2a09`:

```powershell
param(
    [Parameter(Mandatory)]
    [object]$Plan
)
```

That is the whole parameter block. `-SchemaPath` is a **binding error** against it, not an ignored
argument, so there is no reading of "passed through" that this copy can satisfy. F28 explains why
the instruction reads as it does.

The parameter is exposed on `plans.psm1`'s wrapper, defaults to the module's own schema relative to
`$PSScriptRoot`, and is **inert**: not read, not tested for existence, not consulted in any verdict.
That is the honest wrapping of a validator that never opens a schema, and the alternative — making
the parameter mean something — is exactly what F5 forbids. Two `It`s hold the line rather than one:
check `g` proves no `Test-Json` is called, and check `i` proves the inertness by behaviour, passing
a plan the schema rejects (`id: 42`, where the schema says `"type": "string"`) and a `-SchemaPath`
that does not exist.

### F28 — the copy and the caller F2/F4/F5 were measured from are on **different branches** of image.builder

This is the root of F27, and it matters to Phase 6 more than it matters here.

| | |
|---|---|
| Copy source `a6b61dd` | on `origin/main`; `git merge-base --is-ancestor a6b61dd HEAD` exits **1** |
| The clone's `HEAD` | `e96bba8`, `feature/oneshot-2026-09-21` — F6 already recorded that it is not on its default branch |
| Merge base | `b0232b8` |
| `src/PlanValidator.ps1` at `a6b61dd` | blob `8e5da768` — hand-written checks, no `-SchemaPath`, never opens the schema |
| `src/PlanValidator.ps1` at `e96bba8` | blob `ff7b2baf` — a **rewrite**: takes `-SchemaPath` defaulting to `Get-PlanSchemaPath`, reads the schema and drives `required`, `properties`, `type` and `minItems` off it, and has **no step-shape rule at all** |

So the carried-in findings are each true of one branch and not the other:

| Finding | True at `a6b61dd` (the copy) | True at `e96bba8` (the clone) |
|---|---|---|
| F2 — the entry function is `Test-PlanStructure` | yes | yes |
| F2 — the caller passes `-Plan` and `-SchemaPath` | no; `Plan.Check` there does not call it at all | yes |
| F4 — every step must carry a non-blank `action` | yes | **no** — no step rule exists there |
| F5 — it never reads the schema | yes | **no** — it reads nothing else |
| F5 — it takes a `-SchemaPath` | **no** | yes |

Only the function's *name* survives both. F2, F4 and F5 were each measured correctly and then
written down as if they described one file.

**Nothing is repointed here.** 3.1 pins `a6b61dd` byte-for-byte, the run order forbids writing to
image.builder before Phase 6, and the schema-reading rewrite is not substrate's to adopt on its own
authority. What Phase 6 has to decide, with this in front of it: if `feature/oneshot-2026-09-21`
merges to `main` there, this module is a wrapper around a **superseded** validator, and "the
submodule points here" will mean image.builder consuming an older contract than the one in its own
`src/`. That is a cutover question, not a Phase 3 one.

### F29 — `src/LedgerReceipt.ps1` is a **second** hash-chain implementation, not a copy of Ledger's

Run order 3.1 asks whether its logic duplicates `Ledger.psm1`'s receipt writer. Read-only, as
instructed — with one correction: **the file does not exist in image.builder's working tree.** It
was never on `feature/oneshot-2026-09-21`, so there is no deletion commit to find; it lives on
`main`. Read at the copy sha, `a6b61dd:src/LedgerReceipt.ps1`, blob `54ea915f`, which is the right
source anyway.

Compared against `claude.build.ledger@d57938d`'s `src/ledger/Ledger.psm1`:

| | `Ledger.psm1` | `LedgerReceipt.ps1` |
|---|---|---|
| Record keys | `ts, attempt, validator, mode, model, sha256, prev, self` | `ts, principal, tool, decision, reason, armed, prev, self` |
| Canonical bytes | hand-assembled JSON string — *"Deliberately not ConvertTo-Json. The canonical bytes feed a hash chain"* (`:88`); read back with `System.Text.Json`, not `ConvertFrom-Json` (`:198`) | `ConvertTo-Json -Compress`, for both writing and verifying |
| `self` | `sha256(canonical payload)`, `prev` being a field inside it | `sha256(prev + canonical)` — `prev` hashed twice, once concatenated and once inside |
| Genesis | 64 zeros | 64 zeros |
| Concurrency | a `FileStream` lock held across the tail read **and** the append (`:337`), so link-and-append is one operation | `Get-SentinelPrevHash` then `Add-Content`, unlocked — two writers race between reading the tip and appending |
| Unparseable tail line | a chain break | silently hashes the raw line and carries on as `prev` |

**Verdict: not a duplicate of the writer — a weaker second implementation of the same idea.** Eight
keys each and a shared genesis convention, and nothing else in common; a receipt written by one
cannot be verified by the other. It also does the one thing the ledger's own README bans on the
chain, `ConvertTo-Json`, on both the write and the verify path.

Not copied, and the reason is not only that it is a duplicate. Its own header calls it *"Thin
receipt rail for the leash hook"*; it hard-codes `/ledger`, reads `LEDGER_DIR`, `LEDGER_PRINCIPAL`
and `LEDGER_HOOK_ARM`, and `Invoke-LedgerBootVerify` probes `/opt/leash/...` before falling back to
itself. By the run order's governing rule — *receipts are libraries, judgments are containers* — a
hook rail that decides at boot is the container's. **Destination: `claude.agent.images`.** Phase 4
should not pick it up either without revisiting this.

### F30 — *"an unknown skill is listed, not ignored"* has no implementation behind it

Run order 3.2 states it as the contract: *"a plan with an unknown skill is accepted but the skill is
listed (that is the contract: 'listed, not ignored')"*. `PHASE-3-PROMPT.md` 3.2f asks for the
measurement rather than the assumption.

Measured. The validator's **only** interaction with `skills_to_build` is this:

```powershell
if ($null -ne $Plan.skills_to_build) {
    foreach ($skill in @($Plan.skills_to_build)) {
        if ([string]::IsNullOrWhiteSpace([string]$skill)) {
            throw 'Plan skills_to_build contains an empty skill name.'
        }
    }
}
```

It rejects a blank entry. It does not resolve, list, report or emit skill names, and there is no
stream on which it could: the function's only output is `$true`. An unknown skill is accepted
**silently**. Check `f` records both halves — the blank entry throws with that exact message, and
the unknown name in `valid-plan.json` passes with `-InformationVariable` and `-WarningVariable`
both empty, so "listed" is falsified rather than merely unproven.

No listing was added. F4's rule: the validator's behaviour is the contract.

The same sentence is wrong in the copied contract document, `modules/plans/docs/plan-contract.md`,
which additionally calls `skills_to_build` required (against both the schema and the validator — F3)
and points at `tests/plan.failfirst.ps1`, which image.builder deleted for being theatre (F8). It is
kept exactly as copied: it is provenance, not documentation. `modules/plans/README.md` says so and
says what is actually true.

### F31 — image.builder's `Plan.build.ps1` still points at its own `src/PlanValidator.ps1`

Run order 3.2's third bullet, confirmed on both branches:

- `a6b61dd` — `Plan.Check` only asserts that `$Build.RepositoryRoot/src/PlanValidator.ps1` exists.
- `e96bba8` — `Plan.Check` dot-sources that same local path, checks `Test-PlanStructure` is defined
  after it, and validates every `plans/*.json` through it.

Neither reaches into a submodule. `Test.FailFirst` no longer exists on the newer branch (F8).
**Repointing is Phase 6 or later, in image.builder, not here** — and F28 is the thing that decides
whether repointing is even the right move.

### F32 — the `no Test-Json` check, written as a text grep, went red on its own explanation

Self-reported, because the red was in my own suite and I found it before CI did rather than after.

Check `g`'s first version was a regex over `plans.psm1` and `PlanValidator.ps1` with `#`-prefixed
lines stripped. It failed: `plans.psm1`'s block comment — the one explaining *why* no `Test-Json` is
added — contains the string. Stripping `#` lines does not strip `<# … #>`.

The lazy repair was to rephrase the comment, and that is the reason not to take it: a check that a
**word** is absent from a file punishes writing down the reasoning, and can be satisfied by writing
around it. Replaced with a parse of both files: no `CommandAst` names `Test-Json`, the name occurs
in no non-comment token, and both files parse without error. That states the claim that was meant —
no `Test-Json` **call** — and cannot be satisfied by prose in either direction.

### F33 — the suite is falsifiable, including the planted defect that does **not** go red

Measured against throwaway copies of `modules/plans` under `[System.IO.Path]::GetTempPath()`, one
defect at a time:

| Planted defect | Score | Red |
|---|---|---|
| none (control) | 11/11 | — |
| a byte appended to `PlanValidator.ps1` | 10/11 | `a` |
| a second **real** export (function defined **and** exported) | 10/11 | `a` |
| the wrapper writes a file under the module | 10/11 | `h` |
| a `Test-Json` call added to `plans.psm1` | 2/11 | `b, c1, c2, c3, d, e, f, g, i` |
| the wrapper catches the throw and returns `$true` | 6/11 | `c1, c2, c3, d, f` |
| **a second export named in `plans.psd1` only** | **11/11** | **—** |

The last row stays in the table rather than being deleted from it. It is not a hole: a name in
`FunctionsToExport` with no function behind it exports **nothing**, because the manifest's list and
`Export-ModuleMember`'s list intersect, so the module genuinely still has one export and check `a`
is right not to fail. The row above it is the same defect made real, and that one goes red. A
falsification table that lists only the plants which worked is a table edited to flatter the suite.

### F34 — the module is named `plans`, bare, and the Phase 2 blocker does not exist here

Run order 2.2's naming rule — *"the README names the three modules bare (ledger, policy, plans)"* —
applied unhindered. `modules/plans/plans.psd1`, `plans.psm1`, module name `plans`.

F22 deferred the same rename for policy, and the reason was specific: sandbox check 1 asserts
`Get-Module -Name 'claude.build.policy'` by name, and `PHASE-2-PROMPT.md` required that check to
port one-to-one, so a rename would have forced a rewrite of a check that was named in the
port-one-to-one list. **No such constraint exists here.** There is no sandbox suite for the plans
validator to port — image.builder shipped none at `a6b61dd`, and the one file the run order names,
`tests/plan.failfirst.ps1`, had already been deleted there (F8) — so nothing asserts the module's
name except the suite written in this phase, which asserts the name the rule gives it.

F22's deferral for policy stands; it is Phase 5's, and nothing here touched it.
---

## Phase 4

Numbering continues from **F34**, which is where Phase 3 left the file.

### F35 — there is no `LedgerError` to absorb; it is a private factory inside the module

The Phase 4 prompt names three things to take: *"module + LedgerError + Python compute engine"*,
and asks for LedgerError *"as nested module or sibling, your call, state it in FINDINGS"*.

Measured first. There is no such file, in any of the six repositories on this workstation:

```powershell
foreach ($r in 'claude.build.ledger','claude.build.inspector','claude.build.fuzzer',
               'claude.build.policy','claude.pwsh.image.builder','claude.agent.substrate') {
    git -C "C:\__Code\____Claude.Build\$r" ls-files | Where-Object { $_ -match 'LedgerError' }
}
```

Nothing. What exists is `New-LedgerError`, a twenty-line `ErrorRecord` factory at
`ledger.psm1:61`, private, called from nine sites, plus a vocabulary of ids that the module
raises. So the question "nested module or sibling" has a third answer, and it is the right one:
**neither. It stays where it is.**

The reason is not laziness about moving a function. `ledger.psm1` is byte-identical to
`claude.build.ledger@d57938d`, and that is the entire argument that the public surface is
unchanged — not a promise, arithmetic about a file, checked from the bytes on every run. Lifting
twenty lines out of it to satisfy the shape of the instruction would trade a provable artifact
for a directory layout, and would change a module this phase is supposed to absorb without
changing.

What replaces the move is that the error surface is now **pinned instead of described**. Three
`It`s: `New-LedgerError` is defined exactly once in the psm1, the manifest declares no
`NestedModules`, and there is no `.ps1` beside the module at all; and the id vocabulary is read
off the AST and compared to a fixed list of fourteen.

### F36 — the module builds `ErrorRecord`s **two** ways, and the first version of the check saw one

Worth recording in the order it happened, because the wrong version of this check would have
passed and read as thorough.

The first collector walked `CommandAst`s named `New-LedgerError` and read the `-Id` argument. It
found eight ids and they looked like a complete vocabulary. They are not: seven further sites
call `[System.Management.Automation.ErrorRecord]::new($ex, '<id>', ...)` directly, and those are
where `LedgerBadSettings`, `LedgerCliMissing`, `LedgerMissingApiKey`, `LedgerNoResult`,
`LedgerPythonMissing` and `LedgerSnakeFailed` live — six of the fourteen, including the one a
caller is most likely to catch by name.

It surfaced by accident: a separate `It` exercised the exhausted-retry path and measured
`LedgerSnakeFailed,Invoke-LedgerForce` off the `ErrorRecord`, which was not in the list the other
`It` called complete.

Both paths are now collected, and the collector's own coverage is asserted **before** its result
is trusted — one `It` proves each path found at least one id and that exactly one constructor
call has a non-literal second argument (`New-LedgerError`'s own, where the id is a parameter). A
second non-literal would mean an id this collector cannot see, and that is a failure rather than
a silence.

`InspectorPolicyHalt` is deliberately not in the list. It is raised by `claude.build.inspector`
and travels up through `Invoke-LedgerForce` unwrapped; nothing here constructs it.

### F37 — the triage, and why two suites the run order called "library" are not

Run order 4.1 asks for the per-suite decision before anything is copied.

| Sandbox suite | Run order says | Measured | Destination |
|---|---|---|---|
| `ledger_chain.ps1` | library, migrates | **library** — 10 tests over append, verify, tamper, policy pass-through | copied as provenance; ported |
| `forensic_chain.ps1` | library, migrates | **library** — 8 sections over the forensic chain | copied as provenance; see F42 |
| `fail_path.ps1` | library, migrates | **library** — non-zero Python exit becomes a terminating error | copied as provenance; ported |
| `no_sabotage.ps1` | library, migrates | **NOT substrate** | stays in `claude.build.ledger` |
| `continuity.ps1` | read it and decide | **NOT substrate** | stays in `claude.build.ledger` |
| `fuzzer_import.ps1` | not substrate | confirmed | `claude.agent.tools` |
| `hook_pre_tool.ps1` | not substrate | confirmed | `claude.agent.images` |

**The measurement disagrees with the run order on two rows, and the measurement wins.**

`no_sabotage.ps1` does not test the ledger. It reads `docs/no-sabotage.md`,
`docs/continuity.md`, `prompts/claude-handoff.md`, `.grok/rules/no-sabotage.md`,
`.grok/rules/continuity.md` and `.claude/skills/build-covenant-test/`, and asserts things like
*"the covenant must carry the call-it-out clause and name the stabbing"* and *"continuity must
record Grok's carpet stab"*. It is a falsifiable test of the **three-party covenant prose** of
`claude.build.ledger` — twelve assertions with planted-defect twins, and good ones. None of its
subjects exists in substrate, and none of them is substrate's to adopt: this repository has no
covenant, no `.grok/`, no handoff file, and the run order's governing rule (*receipts are
libraries, judgments are containers*) does not reach a suite whose subject is neither.

`continuity.ps1` is the same shape and additionally asserts the **contents of
`no_sabotage.ps1` itself** — that its check 6 uses a shared predicate, that its twins are named
`twin-empty-covenant` and `twin-empty-handoff`. It is a test of the other suite's honesty. That
is a real and unusual thing to have, and it belongs beside the thing it watches.

Copying either would have meant either copying a covenant this repository has not entered, or
editing the suites until they passed against something else — and an edited covenant test is the
exact failure its own rule 2 names. Neither was done. **Not copied, no substitute written, and
the reason is here rather than in a commit body.**

### F38 — the `src/ledger` grep found two hits, both prose, and neither was fixed

Run order 4.3: *"Every internal path that assumed `src/ledger/` is fixed; grep for `src/ledger`
and `src\ledger` and list every hit in the commit body."*

Two hits, both in `ledger.psm1`, both comments:

```
:13   # file no matter where pwsh was launched from. src/ledger -> repo root.
:469  Spawns src/ledger/python/cli.py as a subprocess. Scalar knobs go on argv,
```

Zero executable hits. Every real path in the module is computed from `$PSScriptRoot`, and
`modules/ledger` sits two levels below the repository root exactly as `src/ledger` did — so the
`..\..` the first comment explains still lands on the repo root, and `$script:LedgerCli` resolves
to `modules/ledger/python/cli.py`, which an `It` asserts against the path on disk.

So the instruction has nothing to act on. **Both comments are left exactly as copied**, because
editing prose inside a byte-identical file costs the one thing that file is carrying: the ability
to say "unchanged" and mean a sha rather than an opinion. `modules/ledger/README.md` states the
real layout, and the manifest's single changed line is the only edit in the module.

### F39 — the `ConvertTo-Json` ban is on the **chain**, not on the module, and the first check got that wrong

Self-reported, and found by the check going red rather than by reading.

Run order 4.3 says to carry the ban as *"a Pester assertion that greps `ledger.psm1`'s
chain-writing functions for those cmdlets"*. The first version ignored the qualifier and parsed
the whole file. It failed, correctly, on three real calls:

| Line | Call | Where |
|---|---|---|
| 701 | `ConvertTo-Json -Depth 6 -Compress` | `Invoke-LedgerForce` — the JSON payload written to the snake's stdin |
| 735 | `ConvertFrom-Json -ErrorAction Stop` | `Invoke-LedgerForce` — parsing one NDJSON event line from the snake's stdout |
| 748 | `ConvertTo-Json -Depth 4 -Compress` | `Invoke-LedgerForce` — echoing an event into `Write-Debug` |

None of those bytes is hashed. They are a subprocess protocol between two processes that agree on
it, and the reason the chain forbids the same cmdlets does not apply: nothing downstream has to
reproduce those bytes, and nobody verifies them later.

The tempting repair was to keep the whole-file ban and move the three calls. That would have
edited the copy to satisfy a test — the tail wagging the module — and the module would then
differ from `claude.build.ledger` for no reason anyone could defend.

So the check states the claim that was actually meant, and states it in two halves:

1. **No chain function calls any of the three.** Scoped, by name, to the nine functions that
   touch the record bytes: `Resolve-LedgerPath`, `Test-LedgerHex64`, `ConvertTo-LedgerJsonString`,
   `ConvertTo-LedgerCanonicalJson`, `Get-LedgerSha256Hex`, `ConvertFrom-LedgerLine`,
   `Add-LedgerRecord`, `Get-LedgerVerify`, `Get-LedgerEntry`.
2. **The calls that do exist are all inside `Invoke-LedgerForce`**, and there are exactly three.

Plus the guard that makes (1) mean anything: an `It` asserts every one of those nine names was
actually found in the file. A typo in that list would scope the check to the empty set and it
would pass forever.

It is a parse, not a grep — AST for calls, token stream for bare names, comments and string
literals excluded — for the reason F32 records: `ledger.psm1`'s own header says *"Deliberately not
`ConvertTo-Json`. The canonical bytes feed a hash chain"*, and a grep punishes writing that down.
A further `It` asserts the file **does** discuss the cmdlets in comments, so the parse cannot be
passing by silence, and three planted-defect twins prove the predicate fires on a real call, fires
through the scoped form as well as the whole-file form, and does **not** fire on comments alone.

### F40 — substrate had no `.gitignore` entry for Python, because it had no Python

Found by running the suite, not by reading the file.

Spawning `modules/ledger/python/cli.py` makes CPython write `modules/ledger/python/__pycache__/`.
`.gitignore` carried `output/`, `.obsidian/` and `*.log` and nothing else, so the bytecode showed
up as untracked, and the `It` that asserts `modules/ledger` is byte-identical to the copy went
red for a reason that had nothing to do with anyone editing it.

Three lines added: `__pycache__/`, `*.pyc`, and `.ledger/`.

The third is not incidental. `Resolve-LedgerPath`'s default is `<repo>/.ledger/ledger.jsonl`, so
any local `Invoke-LedgerForce` without an explicit `-LedgerPath` writes a receipt chain at the
repository root. A receipt chain is evidence about a run on somebody's workstation; committing
one would put unreviewed hashes in the tree and make every later verify depend on them. Two `It`s
hold the line: one asserts `<repo>/.ledger` does not exist after the suites have run, one asserts
the ignore rules are there by name.

### F41 — the suite is falsifiable, and the row F33 could not make go red goes red here

Measured by `docs/plans/2026-09-22-substrate-cutover/falsify-ledger.ps1`, which plants one defect
at a time in the real tree, runs both suites in a child process, reverts with `git checkout --`,
and refuses to plant the next defect if the revert did not produce a clean tree.

```powershell
pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/falsify-ledger.ps1
```

| Planted defect | Score | Red |
|---|---|---|
| none (control) | **84/84** | — |
| a byte appended to `ledger.psm1` | 82/84 | 2 |
| a byte appended to `python/snake.py` | 82/84 | 2 |
| **a fifth name in `ledger.psd1` `FunctionsToExport` only** | **82/84** | **2** |
| a second real export (defined **and** exported) | 80/84 | 4 |
| a `ConvertTo-Json` call inside `Add-LedgerRecord` | 79/84 | 5 |
| the writer drops the exclusive lock (`FileShare.None` → `ReadWrite`) | 81/84 | 3 |
| the canonicalizer emits `mode` and `model` in the wrong order | 81/84 | 3 |
| an error id renamed (`LedgerBadSelf` → `LedgerSelfMismatch`) | 79/84 | 5 |
| `LedgerReceipt.ps1` dropped into the module | 82/84 | 2 |
| the verifier stops checking `prev` linkage | 79/84 | 5 |

Three of those rows are worth more than their number.

**The bolded row is F33's hole, closed.** In the plans module, a name added to `FunctionsToExport`
with no function behind it went 11/11 — correctly, because the manifest's list and
`Export-ModuleMember`'s list intersect, so nothing is actually exported and an export-count check
is right not to fail. Here it goes red twice, and neither red is an export count: the manifest is
covered by an `It` that reverses its single adaptation and expects the source blob sha back, and
by an `It` that compares `FunctionsToExport` against the names parsed out of `Export-ModuleMember`
in the psm1. A manifest that promises a fifth function the module does not have is now a lie the
suite can catch, not because the module behaves differently but because the two lists disagree.

**Dropping the lock is caught by exactly one check, and it is not the obvious one.** The
`It` that holds a foreign `FileShare.None` handle and expects the append to fail still passes
with the writer downgraded to `FileShare.ReadWrite` — the *foreign* handle is the one denying the
share, so that check cannot tell the two apart. Only the four-process burst catches it. A suite
with the single-handle check and no concurrency check would have reported green on a writer with
no lock, and this is the measurement that says so.

**`LedgerReceipt.ps1` is caught twice, independently.** Once by the `It` that names it (F29), and
once by the `It` that asserts the module is one manifest and one psm1 with no `.ps1` beside them.

No row is omitted. Every defect planted was recorded, and the control is in the table because a
falsification pass whose control is not green measures nothing.

### F42 — substrate's `scripts/forensic.ps1` and the ledger's do **not** diverge

Run order 4.1 anticipates that they might: *"Compare its forensic logic to substrate's
`scripts/forensic.ps1` (copied from image.builder, known to drift — repo-policy FINDINGS #13). If
they diverge, the MODULE's version wins and `scripts/forensic.ps1` is replaced by a thin wrapper
that imports it."*

Measured with `Compare-Object` over the two files:

| | |
|---|---|
| `claude.build.ledger/scripts/forensic.ps1` | 311 lines, sha256 `ad16a85b…` |
| `claude.agent.substrate/scripts/forensic.ps1` | 323 lines, sha256 `ef39a34d…` |
| Difference | **12 lines, all present only in substrate's copy, all comment** |

Those twelve lines are the provenance header substrate added when it copied the file, and it
names `claude.pwsh.image.builder@06e738d` and the sha256 `ad16a85b…` — which is exactly the
ledger's file. Strip the header and the two are byte-identical. image.builder's copy and
`claude.build.ledger`'s copy are the same artifact.

**So the contingency does not fire.** Nothing is repointed, no wrapper is written, and
`scripts/forensic.ps1` is not touched by this phase. The drift repo-policy FINDINGS #13 records is
real about some pair of files; it is not real about this one at these shas, and a wrapper written
on the assumption would have been a change with no defect behind it.

`forensic_chain.ps1` is copied as provenance rather than ported. It is a suite over
`scripts/forensic.ps1` and `.continuity/forensic.jsonl` — the **forensic** chain, which is the
repository's record of who did what to the law, not the receipt chain this module owns. Substrate
already tests it: `tests/Skeleton.Tests.ps1` verifies the live chain and the `forensic-verify`
required check runs the verifier on every push and pull request. Porting eight more sections of
the same subject into a *module* suite would file them under the wrong owner; the module's chain
is `.ledger/ledger.jsonl` and that is what `ledger.Tests.ps1` covers.

### F43 — three sandbox originals are in the tree and none of them can run here

Same shape as F24 for policy, recorded so nobody discovers it by running one.

`modules/ledger/tests/sandbox/` holds `ledger_chain.ps1`, `forensic_chain.ps1` and
`fail_path.ps1`, byte-identical to the source and asserted so on every run. All three resolve the
module through the **source repository's** layout:

Run, not assumed — `pwsh -NoProfile -File` on each, all three exit 1:

- `ledger_chain.ps1` and `fail_path.ps1` build `<repo>/src/ledger/Ledger.psd1` from
  `$PSScriptRoot/../..`, which in this tree is `modules/ledger/`. Both **throw** before the first
  assertion: *"Ledger.psd1 not found at …\modules\ledger\src\ledger\Ledger.psd1"*.
- `ledger_chain.ps1` would additionally run `examples/force_example.ps1`, which was not copied, and
  write to `<repo>/.ledger/ledger.jsonl`, which this repository deliberately does not have.
- `forensic_chain.ps1` does not throw — it resolves `<repo>/scripts/forensic.ps1` the same way and
  reports `FAIL scripts/forensic.ps1 exists` as its first check, then cascades.

None of the three wrote anything: the tree was clean after all three runs.

They are also **Windows-only**, which is the second reason they could not have been kept green
here even with the paths fixed. `ledger_chain.ps1`'s own `.DESCRIPTION` says TEST 6 writes its
fixtures to `$env:TEMP`, and `New-SnakeStub` emits a `.cmd` containing `@echo off` and `type`.
F26 predicted exactly this for Phase 4 and asked that it be read before 4.2; it was, and the
outcome is that the ports take their temp root from `[System.IO.Path]::GetTempPath()` from the
first line rather than discovering the problem on the runner.

They are kept because they are what the Pester port was written from. A reader checking the port
against its oracle needs the oracle in the tree, and a suite quoted from memory is not an oracle.
They are **not** wired into `Invoke-Tests.ps1`: Pester's `*.Tests.ps1` filter excludes them, which
is the same mechanism that keeps `modules/policy/tests/sandbox/` out.

The run order's Phase 4.3 expectation — *"Sandbox originals stay and stay green — they are the
oracle. Per suite, the Pester count must equal the sandbox count"* — **cannot hold**, for the
same reason F1 recorded for policy and by a wider margin. The per-suite count comparison it asks
for is therefore not in the report, because it would be a comparison against a number that cannot
be produced in this repository. What is in its place is F44.

### F44 — what the port covers, against what the originals covered

The honest version of the table run order 4.4 asks for. The right-hand column is not a count of
the original's checks, because those counts are not reproducible here (F43); it is what the
original asserted and where that assertion now lives.

| Original | Its subject | In the port |
|---|---|---|
| `ledger_chain.ps1` TEST 1–2 | the example appends one receipt; a second run links `prev` → `self` | `ledger.Tests.ps1` — the append/verify round-trip Context, 8 `It`s, plus the dry-run force in `python.Tests.ps1` |
| TEST 3 | a tampered copy makes verify throw | the tamper Context, **11** `It`s where the original had one, each asserting a `FullyQualifiedErrorId` |
| TEST 4 | dry-run never imports `anthropic` | `python.Tests.ps1` — the SDK is asserted absent, and `snake.py`'s import is proved lazy through Python's own `ast` |
| TEST 5 | live mode with no key throws before spawn, writes nothing | `python.Tests.ps1`, one `It`, id `LedgerMissingApiKey` |
| TEST 6 | `-Policy` / `-Halt` pass-through to `claude.build.inspector` | **not ported.** It needs the Inspector sibling on disk. Out of scope by the run order's own boundary — a judgment, and the sibling is not substrate's |
| TEST 7 | schema and chain rejection, forged line by line | the tamper Context, and the eight-keys-in-order `It` |
| TEST 8 | the writer rehashes the output and refuses what it cannot reproduce | **partly.** `python.Tests.ps1` recomputes the receipt's `sha256` from `$r.Output` with an independent hasher; the *refusal* half needs a lying stub, which is Windows-only in the original — see below |
| TEST 9 | a halt writes no receipt | **not ported**, with TEST 6 |
| TEST 10 | the result event must describe the run that was asked for, or `LedgerResultMismatch` | **not ported.** The original drives it with a stub snake that returns a doctored event; the port asserts only that a real dry-run comes back with the mode it was given. `LedgerResultMismatch` is in the pinned id vocabulary but nothing exercises it |
| `fail_path.ps1` | non-zero Python exit → terminating PowerShell error | `python.Tests.ps1`, one `It`, id `LedgerSnakeFailed`, plus `LedgerPythonMissing` for a missing interpreter |
| `forensic_chain.ps1` | the forensic chain detects tampering | **not ported** — F42. Substrate covers that chain in `tests/Skeleton.Tests.ps1` and the `forensic-verify` check |

Net: **84 new `It`s**, 66 in `ledger.Tests.ps1` and 18 in `python.Tests.ps1`, Pester **83 → 167**.

Four subjects the originals covered are not covered here — the `-Policy`/`-Halt` pass-through
(TEST 6), the halt-writes-no-receipt rule (TEST 9), the result-echo mismatch (TEST 10), and the
forensic chain (`forensic_chain.ps1`). TEST 6 and TEST 9 need the Inspector sibling on disk and
are judgments rather than receipts, which the run order's governing rule puts outside substrate.
`forensic_chain.ps1` is F42.

**TEST 8 and TEST 10 deserve the real reason, which is a platform one.** Both are driven by
`New-SnakeStub`, and that helper writes a Windows `.cmd`:

```powershell
[System.IO.File]::WriteAllText($cmd, "@echo off`r`ntype `"$payload`"`r`n", $utf8)
```

`@echo off`, `type`, CRLF, `.cmd`. It cannot run on `ubuntu-latest`, which is this repository's
only gate. TEST 8's claim was portable without it — the port recomputes the receipt's `sha256`
from the output a **real** dry-run returned, using an independent hasher — but TEST 10's is not:
proving that a snake which *lies about the run it performed* raises `LedgerResultMismatch`
requires a snake that lies, and the only stub mechanism the module offers is `-PythonPath`, an
executable.

A cross-platform replacement is possible — a `.cmd` on Windows and a shebanged script on Linux,
branching on `$IsWindows` — and it was not written, on purpose. A shell script is what AGENTS.md
bans outright; a Python one lands a `.py` outside `runtimes.python.allowed_under`; and either way
**I would be committing a branch I cannot execute on the platform that decides whether it works.**
That is exactly how F26 happened: a suite reported green from a Windows workstation and went red
on the runner, and the lesson recorded there was that local `pwsh` on Windows and `ubuntu-latest`
are different platforms.

So `LedgerResultMismatch` is in the pinned id vocabulary and nothing exercises it. That is a real
hole in the port, it is this size, and it is here rather than in a summary that says "ported".

### F45 — two documents were copied out of the ledger's `docs/`, not eleven

Run order 4.2 says `docs/** -> modules/ledger/docs/`. `claude.build.ledger/docs/` holds thirteen
files. Two were copied: `theory-of-operation.md` (the contract between the two halves of the
module) and `commands.md` (the four functions and the alias).

The other eleven are `README.md`, `verification.md`, `scenarios.md`, `do-not.md`, `hooks.md`,
`continuity.md`, `no-sabotage.md`, `fuzzer-import.md`, `grok-watched-test.md`,
`trifecta-audit.md` and `plans/2026-09-20-three-party-workbench.md`. They are the covenant, the
hook rail, the fuzzer, the audit and a set of copy-pasteable command sequences rooted at the
source repository's layout. None documents this library, and the two of them that *are* law —
`continuity.md` and `no-sabotage.md` — are the subjects of the two suites F37 declined to copy;
bringing the prose without the tests would be the worse half of that decision.

Both copied documents describe the source repository's paths, and `modules/ledger/README.md` says
so. They are provenance, byte-identical and asserted so, not this module's documentation.

### F46 — this phase used a POSIX shell for read-only inspection, and nothing else

Self-reported, in the same terms as F25 and for the same reason: a rule that is only mentioned
when the output looks wrong is not being enforced.

AGENTS.md says *"No bash, no sh, no heredocs, no `cat >`"*. The opening survey of this session —
listing tracked files, reading `AGENTS.md` and `RUN-ORDER.md`, and counting lines — was run
through the harness's POSIX shell before the session switched to `pwsh` for everything else. Six
read-only commands: `git ls-files`, `cat`, `find`, `ls`, `grep`, `wc`.

No file was authored, copied, edited or hashed by it. Every copy was `[System.IO.File]::ReadAllBytes`
/ `WriteAllBytes` from PowerShell, every measurement was `pwsh -NoProfile`, every commit message
was written to a file with PowerShell and passed to `git commit -F`, and nothing in the repository
depends on a POSIX shell. The rule's purpose is intact. The rule as written still says no `sh`,
and six commands were `sh`.

---

## Phase 5

### F47 — the policy rename cost two `It`s, not one, and a fixture's data file

F22 is decided, not deferred a third time: `modules/policy/claude.build.policy.psd1` and `.psm1`
are now `policy.psd1` and `policy.psm1`, the import path is `modules/policy/policy.psd1`, and the
module name is `policy` — bare, like `ledger` and `plans`.

**Why in the release phase rather than never.** Phase 6 flips `review.mode` to `"human"`. This is
the last phase whose pull requests merge on green checks alone, so a cosmetic identity change
either lands here or costs a human-gated pull request for the rest of the repository's life.
Nothing outside `modules/policy` imports the module — Phase 6 repoints image.builder at
`modules/ledger` only — so the change is cheap in both directions, and `v0.1.0` is the tag a
consumer would pin, so the name found there should be the name the README promises.

**The prompt's expectation was wrong by one, and the measurement wins.** It says *"sandbox check 1
in `policy.Tests.ps1` is the one `It` that has to change"*. Check **2** changes as well: it runs
`modules/policy/tests/fixtures/build/build.ps1` in a child process, and that fixture derives the
module name from the manifest **filename**
(`[System.IO.Path]::GetFileNameWithoutExtension($manifestPath)`) and throws when `build.json`
disagrees with it. That cross-check is the part of the original `build.ps1` worth carrying, so the
correct response was to move the fixture's data with the rename, not to loosen the check.

check 1, before:

```powershell
        $module = Get-Module -Name 'claude.build.policy'
```

check 1, after:

```powershell
        $module = Get-Module -Name 'policy'
```

check 2, before:

```powershell
        $joined | Should -Match 'claude\.build\.policy'
```

check 2, after:

```powershell
        $joined | Should -Match '(?m)^\[build\] name policy$'
```

Check 2's replacement is anchored to a whole line deliberately. `-Match 'policy'` is true of the
string `claude.build.policy`, so the obvious port of that assertion would have passed against the
very name it exists to prove is gone — the same shape of defect as F32, caught before it shipped
rather than after.

Also changed: `build.json`'s `name` → `"policy"`, `build.ps1`'s manifest path and its own doc
comment, and `modules/policy/README.md`.

**Not changed, on purpose.** `policy.psm1` is the byte-identical Phase 2 copy and still hashes to
blob `72dc1ec6010897d56cb2ca3aa10351393b72d5ef` under its new name — a rename moves a file, not
its bytes. It therefore still emits `PSTypeName = 'claude.build.policy.PolicyRule'` and still
lists the four `claude.build.*` repository names in `$script:SiblingNames`. Those are the parser's
subject matter and its provenance, not this module's identity; editing them would end the
provenance claim and buy nothing. **The manifest is the only copied file this repository has ever
edited**, and the edit is one line, `RootModule`.

Two files that were already stale are now staler, and neither was touched: the sandbox oracle
`tests/sandbox/policy_suite.ps1` and `examples/parse-here.ps1` both resolve
`src/claude.build.policy/claude.build.policy.psd1` in the **source** repository's layout. F24
recorded that they cannot run here; after the rename they cannot run here for a second reason.
They are provenance, and provenance that gets edited to look current is not provenance.

**Falsification — three planted defects, each restored after measuring:**

| planted | measured |
|---|---|
| `build.json` keeps the old module name | 10 total, **1 red** (check 2) |
| check 1 looks for the old module name | 10 total, **1 red** (check 1) |
| the manifest's `RootModule` points at the old `.psm1` | 10 total, **10 red** |
| control, nothing planted | 10 total, **0 red** |

Ten checks before, ten after. The Pester total does not move.

### F48 — `AGENTS.md`'s wall was three phases stale, and the test was right the whole time

F21 left the prose deliberately behind the test: *"a wall rewritten in the phase that first
crosses it is a wall rewritten by the party it binds."* Phase 5.1 is where it gets corrected, and
the prompt says to check the prose against `tests/Skeleton.Tests.ps1` first — **if they disagree,
the test wins and the prose is corrected**.

Checked. They do not disagree. The test has said
*"modules/ holds only the modules a run order named"* since Phase 2, failing on a
`modules/<unnamed>/` subtree or a loose file at the top of `modules/`, with the named set
`ledger`, `policy`, `plans` and a `-Because` that cites the run order by path. The run order's
Phase 5 wording — *"Module code outside `modules/<n>/` for a module this run order did not name"*
— is that same rule in prose. So nothing had to be overruled; the prose caught up.

One thing the test carries that the run order's sentence does not: `It 'src/ contains nothing but
.gitkeep'`. `src/` is still empty and still walled, and a bullet that only mentioned `modules/`
would have quietly dropped that half. The new bullet names both, and says in the file itself that
the test wins where they diverge — so the next agent who finds them disagreeing does not have to
guess which one is law.

### F49 — the per-module numbers did not exist until this phase, and now they have a script

`scripts/ci/Invoke-Tests.ps1` answers one question, *did the suite pass*, and prints one total.
The README's status table needs four numbers it has never had, and this repository does not let a
report state a figure that no script reproduces.

`scripts/Measure-Modules.ps1` buckets `(Invoke-Pester -PassThru).Tests` by the file each test was
**declared in** — `$test.ScriptBlock.File` — rather than by the Pester root it was collected
under, so a test counts to its module no matter how the run was invoked. Measured at `f7cbb11`:

| bucket | tests |
|---|---|
| `ledger` | **84** — `ledger.Tests.ps1` 66, `python.Tests.ps1` 18 |
| `plans` | **11** |
| `policy` | **10** |
| repository `tests/` | **62** — six files |
| total | **167** |

The script exits 1 when the per-file rows do not sum to Pester's own `TotalCount`. That assertion
is about the script, not the repository: a bucketing bug that silently dropped a file would
otherwise print a smaller, tidier and entirely wrong table, which is exactly the kind of number
this run order exists to prevent.

### F50 — `Start-Transcript` writes CRLF into a repository whose `.gitattributes` says LF

Measured, from git's own warning when the transcript was first appended this phase:

```
warning: in the working copy of 'docs/plans/2026-09-22-substrate-cutover/TRANSCRIPT.log',
CRLF will be replaced by LF the next time Git touches it
```

So the transcript on disk and the transcript in the object store differ by line ending, and a
sha256 of the working-tree file will never equal a sha256 of the committed blob's bytes. It
changes nothing here, because `TRANSCRIPT.log` is one of the two names `HASHES.txt` excludes from
its manifest. That exclusion was originally about a file that grows while it is being hashed; this
is a second, independent reason for it, and it is written down so that nobody later "fixes" the
exclusion and produces a `COMBINED` that cannot be reproduced on another machine.

### F51 — F44's TEST 10 hole is open at the tag, and the release notes say so

`LedgerResultMismatch` is in the ledger module's pinned error-id vocabulary and **nothing
exercises it**. F44 measured why: proving that a snake which lies about the run it performed
raises that error needs a snake that lies, the only stub mechanism the module offers is
`-PythonPath` (an executable), and the original's stub is a Windows `.cmd` that cannot run on
`ubuntu-latest` — while a shell replacement is banned outright and a Python one would land a `.py`
outside `runtimes.python.allowed_under`.

Restated here rather than left in Phase 4's findings because a tag is precisely the moment a known
gap becomes easy to forget. It is **not** closed by this release, it is named in
`RELEASE-NOTES.md` as a known gap, and it stays open with the same three constraints on any fix.

### F52 — this phase used a POSIX shell for read-only inspection, and nothing else

Self-reported in the same terms as F25 and F46, for the same reason: a rule that is only mentioned
when the output looks wrong is not being enforced.

`AGENTS.md` says *"No bash, no sh, no heredocs, no `cat >`"*. The opening survey of this session —
listing the plan directory, reading `AGENTS.md`, `RUN-ORDER.md`, `FLOW-PROOF.md`, `BASELINE.md`,
the CI scripts and the policy suite, and grepping for the module name — was run through the
harness's POSIX shell. Roughly a dozen read-only commands: `cat`, `sed -n`, `head`, `grep`, `find`,
`ls`, `wc`.

Nothing in the repository was authored, edited, renamed, measured or hashed by it. Every edit was
`[System.IO.File]::ReadAllText` / `WriteAllText` from `pwsh` and asserted to have changed something
before it was written; every rename was `git mv`; every measurement was Pester under the pinned
version; every commit message was written to a file and passed to `git commit -F`. No heredoc was
used anywhere, and nothing in the repository depends on a POSIX shell. The rule's purpose is
intact. The rule as written still says no `sh`, and about a dozen commands were `sh`.

---

## Phase 6 — the cutover, halted at 6.1

### F53 — image.builder's own flow cannot express the cutover: `develop` carries no submodule

Phase 6.0 is "measure image.builder's CURRENT flow first, because its flow governs its PR".
Measured from `config/repo.json` on `feature/oneshot-2026-09-21` and from `git`:

| | image.builder | substrate |
|---|---|---|
| Default branch | `main` (`origin/HEAD -> origin/main`) | `main` |
| `origin/main` | `a6b61dd6ab3d4e2a61e05de6be92f2dfebcd72c1` | `3933dccf4013f9427a2e14206899ec8eede155cd` |
| `origin/develop` | `57637ae08291dd9501a52df89c1d94772298542d` | `1c0d068ea5483225266aed5e150e0df72f63084b` |
| `flow` | `feature/* -> develop`, `develop -> main` | identical |
| `review.mode` | `"auto"` | `"auto"` |
| `required_checks` | `requires-header`, `trailer-guard`, `branch-flow`, `generated-match-config`, `pester`, `forensic-verify` | identical |
| `merge` | `merge`, `delete_branch_on_merge: true` | identical |
| `trailer` | `who:` — claude, grok, fable, jerry | identical |
| `tooling.pester` | **`6.1.0`** | **`5.7.1`** |

The two `repo.json` files agree on everything a flow is made of and disagree on the one thing a
suite is made of. That is `F7`, unchanged, now with both values read on the same day.

**The flow cannot carry this commit.** `feature/* -> develop` is the only lane a feature branch
has here, and `origin/develop` does not contain the thing Phase 6.1 is supposed to remove:

```
git -C claude.pwsh.image.builder rev-parse origin/develop:.gitmodules
  fatal: path '.gitmodules' exists on disk, but not in 'origin/develop'
git -C claude.pwsh.image.builder rev-parse origin/develop:vendor/claude.build.ledger
  fatal: path 'vendor/claude.build.ledger' exists on disk, but not in 'origin/develop'
```

It is not only the submodule. `git ls-tree --name-only origin/develop` has no `build/`, no
`config/`, no `.build.ps1`, no `.gitmodules`, no `vendor/`, and its entrypoint is
`entrypoint.sh`, not `entrypoint.ps1`. There is no `Invoke-Build`, so there is no
`Build.Image` to rebuild and no `Bootstrap` to fail. A feature branch cut from `develop` could
not perform the cutover, could not measure it, and would not build an image either before or
after.

The vendoring commit `397f631` ("chore: vendor claude.build.ledger @ ed9c9d7 (pre-PR4 main)")
sits on one side of the split only:

| Ref | `397f631` is an ancestor |
|---|---|
| `origin/main` | yes |
| `main` (local) | yes |
| `feature/oneshot-2026-09-21` | yes |
| `origin/develop` | **no** |

`git rev-list --left-right --count origin/main...origin/develop` gives `9  16`. This is
`BLOCKER-5` in image.builder's own `config/contracts.json` — *"main and develop have diverged
into two incompatible repositories"* — still true, and now it is load-bearing: the cutover is a
main-side operation and the flow only offers a develop-side lane.

**Deviation, stated rather than hidden.** The branch was therefore cut from
`feature/oneshot-2026-09-21` (`e96bba8b1dd17cb7e1fc5439bfbf2fe2c057f68d`), the only ref that
carries both the submodule and the build system that consumes it, and which is also the ref
`BASELINE.md` recorded as image.builder's HEAD at baseline. The branch is
`feature/submodule-substrate`. It is **not** per the configured flow, because no branch per the
configured flow can do this, and choosing the ref that can is the smaller of the two
deviations. Phase 6 cannot open a pull request in image.builder until Jerry decides which side
of the 9/16 split is the repository.

### F54 — the coupling measurement: two paths changed, thirteen sites depend on them, the image stops building

Phase 6.1 permits exactly two paths to change: `.gitmodules` and the gitlink. Commit
`405ea22` on `feature/submodule-substrate` changes exactly those and nothing else —
`3 files changed, 4 insertions(+), 4 deletions(-)`, `delete mode 160000
vendor/claude.build.ledger`, `create mode 160000 vendor/claude.agent.substrate`,
`git submodule status` reporting
`3933dccf4013f9427a2e14206899ec8eede155cd vendor/claude.agent.substrate (v0.1.0)` with
`git describe --exact-match --tags` answering `v0.1.0`.

**Green immediately before.** Same clone, same tree, submodule still on
`vendor/claude.build.ledger @ ed9c9d7`:

```
Invoke-Build Bootstrap, Build.Image
  Assessment verified: 798b10ee3ca2d64b28bc779611484ddc0565448c6468ae2ddaf54a53a98030a3
  Ledger vendored at ed9c9d7
  Built claude.pwsh.image.leash:run-01
  Built claude.pwsh.image.developer:run-01
  Build succeeded. 4 tasks, 0 errors, 0 warnings
```

Image ids, identical to the two `BASELINE.md` records:
`sha256:1716f8ab42c50b9349eb11c0a703cfdb8cef509c5d0fae1bd1918bbfaeb87cab` (leash) and
`sha256:6708943e90b067ba9b18e5c985ea337bd5eeed05aec758515756ad36f02be819` (developer).

**Red immediately after,** from the two-path commit alone, in two independent places:

```
Invoke-Build Bootstrap, Build.Image
  Assessment verified: 798b10ee...
  ERROR: Vendored Ledger missing: ...\vendor\claude.build.ledger\src\ledger\Ledger.psd1.
         Run: git submodule update --init
  at build/tasks/Core.build.ps1:31
  Build FAILED. 1 tasks, 1 errors

Invoke-Build Build.Image
  #16 [12/15] COPY vendor/claude.build.ledger/src/ledger/ /opt/leash/ledger/
  #16 ERROR: failed to compute cache key: failed to calculate checksum of ref ...:
             "/vendor/claude.build.ledger/src/ledger": not found
  Dockerfile:97
  ERROR: Program "docker.exe" ended with non-zero exit code: 1
  at build/tasks/Images.build.ps1:25 (task Build.Image.Leash)
  Build FAILED. 2 tasks, 1 errors
```

`Bootstrap` is the first job of image.builder's default chain, so the failure is not at the
edge of the build — it is before the build.

**The coupling, enumerated.** Eight sites bind the build-context path, and all eight are
literals; none reads `.gitmodules`:

| Site | The literal |
|---|---|
| `.gitmodules:1-3` | submodule name, `path`, `url` |
| `Dockerfile:97` | `COPY vendor/claude.build.ledger/src/ledger/ /opt/leash/ledger/` |
| `images/developer/Dockerfile:89` | the same `COPY` line |
| `build/tasks/Core.build.ps1:29` | `Join-Path $ledgerRoot 'src' 'ledger' 'Ledger.psd1'` |
| `build/tasks/Core.build.ps1:33` | `git -C $ledgerRoot rev-parse --short HEAD`, printed as provenance |
| `scripts/ci/Invoke-Tests.ps1:84` | `vendor/claude.build.ledger/src/ledger/Ledger.psd1` — the M17 private-submodule detector |
| `tests/TestHelpers.psm1:225` | `Get-LedgerManifestPath` builds `vendor/claude.build.ledger/src/ledger/Ledger.psd1` |
| `tests/Image.Tests.ps1:140` | asserts the Dockerfile **text** matches `COPY vendor/claude\.build\.ledger/src/ledger/ /opt/leash/ledger/` |

Plus `config/contracts.json:35`, whose `ledger` row carries
`"vendor/claude.build.ledger at ed9c9d79856b4590b64eb2f0229dee8775a903d5"` as evidence, and
`:36`, which names `Ledger.psd1`.

Five further sites bind the **in-container** path `/opt/leash/ledger/Ledger.psd1`:
`entrypoint.ps1:67` (exit 13 if absent), `hooks/sentinel.ps1:81`,
`build/InContainer.Test.ps1:72`, and `tests/Image.Tests.ps1:212` and `:216`. These would
survive a change of source directory — but not a change of filename, and substrate's manifest is
`modules/ledger/ledger.psd1`. **Lowercase.** On the host that is invisible; in the image it is a
different file. So the rename is a second, separate break that a Windows-only measurement would
have missed.

| | image.builder expects | substrate ships |
|---|---|---|
| Module directory | `src/ledger/` | `modules/ledger/` |
| Manifest | `Ledger.psd1` | `ledger.psd1` |
| Module name | `Ledger` | `ledger` |
| Python | `src/ledger/python/` | `modules/ledger/python/` |
| Suites | `tests/sandbox/` (7 scripts) | `modules/ledger/tests/sandbox/` (3 scripts) |

Nothing above was repaired. Repairing it is what 6.1 forbids, and the prohibition is the
instrument: a cutover that needed one commit needs at least three files of Dockerfile, task and
test surgery plus a contract edit, and that number is the measurement.

**Consequence.** Phases 6.2, 6.3 and 6.4 were not reached. No image was rebuilt after the swap,
so `Measure-Baseline.ps1` was not run against one, the per-suite comparison against `BASELINE.md`
**was not evaluated**, and the pre-registered table is neither matched nor contradicted — it is
unmeasured. No pull request was opened in either repository for the cutover, `review.mode` was
**not** flipped to `"human"`, `Generate-Policy.ps1` was not re-run, `FLOW-PROOF.md` was not
touched, and `v0.1.0` still points at `3933dcc`. `feature/submodule-substrate` is held local and
unpushed: image.builder's `review.mode` is `"auto"`, and a branch whose purpose is to be red does
not belong in front of a merge robot.

### F55 — the README's definition of done cannot be met by any substrate, and what should replace it

`README.md` says substrate is done when image.builder's submodule points here and its
in-container suite is green *"at the same pass count it had at cutover"*. `BASELINE.md` fixes
that count at **127**, identical in both images, and says where it comes from: three suites of
seven produced a count — `continuity.ps1` 77, `forensic_chain.ps1` 28, `no_sabotage.ps1` 22.

Substrate does not ship two of those three. `modules/ledger/tests/sandbox/` holds exactly
`fail_path.ps1`, `forensic_chain.ps1` and `ledger_chain.ps1`. `continuity.ps1` and
`no_sabotage.ps1` are absent by the Phase 4 triage (`F37`, destinations recorded:
tools/images), as are `fuzzer_import.ps1` (tools) and `hook_pre_tool.ps1` (images) — the
**four** removals the run order pre-registered, not two.

So 99 of the 127 come from suites that are, by design, somewhere else. The arithmetic is not
close: the most a green substrate could contribute is 28 from `forensic_chain.ps1` plus whatever
`fail_path.ps1` and `ledger_chain.ps1` produce, and both of those were `SKIPPED` at baseline for
the `F43` path-resolution reason. **127 is unreachable by construction, not by defect.** No
substrate that passes `verify.ps1` check 4 — *"modules/ holds exactly ledger, policy, plans"* and
*"fuzzer_import.ps1 and hook_pre_tool.ps1 are nowhere under modules/"* — can ever reach it. The
release was built to remove those suites and the definition of done was written to require them.

**Proposed replacement**, three clauses, each measurable:

1. `claude.pwsh.image.builder` builds both images with the submodule at `vendor/claude.agent.substrate`
   pinned to `v0.1.0` — `Invoke-Build Bootstrap, Build.Image` green, image ids recorded.
2. Substrate's own suite runs green **in-container** against the submodule checkout —
   `scripts/ci/Invoke-Tests.ps1`, total recorded.
3. The four removals are **named** with their destination repositories, and the suites substrate
   does ship are compared to `BASELINE.md` row by row rather than to a single total.

`README.md` is **not** edited by this pass. Which definition of done governs is Jerry's call, and
a repository that rewrites its own acceptance criterion when it cannot meet it has not met it.

**What is measurable today, for clause 2.** Substrate's own suite, host, pinned Pester 5.7.1:
`pester: total=167 passed=167 failed=0 skipped=0 duration=00:00:46.5`, exit 0 — the
pre-registered expectation of 167, met. `verify.ps1` is 19 checks, 19 passed, 0 failed,
`COMBINED 51a3e0c839065e3a09341cc71d186e806bd81fe457b4afd02ca324284b7020a3`, run before this
finding was written. The **in-container** number remains unmeasured, because the only way to get
an image with substrate in it is the build that 6.1 stopped. `F10` also stands unretested here:
the leash image has no `python` at all, and `modules/ledger/tests/python.Tests.ps1` has never
been run inside it.

### F56 — the `F27`/`F28` record, not the decision

The run order asks for two facts and forbids resolving them. Both measured today:

**Is `a6b61dd` an ancestor of image.builder's current default-branch HEAD?** Yes — trivially, it
*is* that HEAD. `git rev-parse origin/main` answers
`a6b61dd6ab3d4e2a61e05de6be92f2dfebcd72c1`; `git merge-base --is-ancestor a6b61dd origin/main`
exits 0. So `verify.ps1` check 8's provenance — `modules/plans/PlanValidator.ps1` blob
`8e5da7682f212499e4fb33c2cdaafe1fb1aa2a09` from `claude.pwsh.image.builder@a6b61dd` — names the
tip of the default branch, not a commit that has since been built on.

**Which `PlanValidator` does its `Plan.Check` task point at?** Its own, at the repository root,
on every ref that has the task: `build/tasks/Plan.build.ps1` resolves
`Join-Path $Build.RepositoryRoot 'src' 'PlanValidator.ps1'` on `origin/main` and on
`feature/oneshot-2026-09-21` alike. Never the submodule's copy, and `modules/plans/` is
referenced nowhere in image.builder. `F31` restated, re-verified.

The sharper half is `F28`, and it has moved:

| Ref | `src/PlanValidator.ps1` blob | Is it the blob substrate copied |
|---|---|---|
| `origin/main` (`a6b61dd`) | `8e5da7682f212499e4fb33c2cdaafe1fb1aa2a09` | yes |
| `feature/oneshot-2026-09-21` (`e96bba8`) | `ff7b2baf02aec1765e3c6fdcf72490a5a06d5028` | **no** |
| `origin/develop` (`57637ae`) | absent | n/a |

The copy matches the default branch and not the branch image.builder is actually working on, and
is absent from the branch its flow says to merge into. `-SchemaPath` stays inert and the `F27`
decision stays open, as instructed.

### F57 — no POSIX shell was used in this phase, and that is the point

`F25`, `F46` and `F52` are the same confession three times: the phase's read-only survey went
through the harness's POSIX shell while `AGENTS.md` says *"No bash, no sh, no heredocs, no
`cat >`"*. The Phase 6 prompt names that streak and asks for a phase with none.

There is none. Every command in this phase ran through `pwsh` — the survey as well as the work:
`git` invoked with `-C`, `Get-ChildItem`, `Select-String`, `Get-Content`, `docker image inspect`,
`Invoke-Build`, and `[System.IO.File]::ReadAllBytes` / `WriteAllText` for every edit, with LF
written explicitly because `.gitattributes` says `eol=lf` and `F50` is what happens when it is
not. No `cat`, no `sed`, no `head`, no `grep`, no `find`, no `ls`, no `wc`, no heredoc. Two
file-content searches used the harness's `ripgrep` tool directly, which is an executable taking
argv, not a shell: no `sh`, no interpolation, no pipeline.

Stated positively rather than left silent, because a streak that is only reported when it is
broken is not being measured. The harness's own default guidance for this session asked for the
opposite — *"read files with `cat`, `head`, or `sed -n`, search with `grep` and `find`"* — and
`AGENTS.md` wins.

### F58 — the 167 re-measurement handed to "the next Claude Code session" is done

Forensic seq 7 (`grok-rat-out-does-not-verify`, landed on `develop` by PR #25 while this phase
was being written) closes with: *"NOT MEASURED HERE: 167 (no Pester runtime in this session) —
Grok's challenge to re-run `scripts/Measure-Modules.ps1` on a clean worktree stands and is handed
to the next Claude Code session."* This is that session. Measured four ways on clean worktrees
under pinned Pester 5.7.1:

| Worktree | Command | Result |
|---|---|---|
| `develop` @ `1c0d068`, clean, before this phase wrote anything | `scripts/ci/Invoke-Tests.ps1` | `total=167 passed=167 failed=0 skipped=0`, exit 0 |
| same | `verify.ps1` check 6 — `Measure-Modules.ps1` live vs `README.md` | PASS, `ledger=84 policy=10 plans=11 repo=62 total=167` |
| `feature/cutover-halt` @ `124c883` (merge of `origin/develop` `5f75e79`), clean | `scripts/ci/Invoke-Tests.ps1` | `total=167 passed=167 failed=0`, exit 0 |
| same | `scripts/Measure-Modules.ps1` | `ledger 84, plans 11, policy 10, repo 62`, `total=167`, exit 0 |

**167 stands**, before and after PR #25. Charge (f) of seq 7 — that Grok's *"README still says
skeleton only"* claim is false — is independently re-confirmed, because check 6 parses the four
per-module numbers back out of `README.md` and would have gone red on a stale table.

Stated honestly in the other direction: this phase did **not** run the suite in a container
either, for the reason `F54` gives — no image containing substrate could be built. Clause 2 of
`F55`'s proposed definition of done is measured on the host and remains unmeasured where it has
to hold.

### F59 — the `plans` source was pinned to the clone's HEAD, not to the commit the copy came from

Found by `HANDOFF.md` step 2 (symbol coverage), which is the first procedure that reads the pin and
the tree in the same breath. Out-of-order work on `feature/migration-manifest`, not a phase.

`docs/migration/migration.json` pinned `claude.pwsh.image.builder` at **`e96bba8`**, branch
`feature/oneshot-2026-09-21`, while recording the landed blob for `src/PlanValidator.ps1` as
`8e5da768`. Those two cannot both be right. Measured 2026-09-22:

| Ref | `src/PlanValidator.ps1` blob | functions defined |
|---|---|---|
| `a6b61dd` — main, and now also develop | `8e5da768` | `Test-PlanStructure` |
| `e96bba8` — the clone HEAD, the old pin | `ff7b2baf` | `Get-PlanSchemaPath`, `Test-PlanStructure` |
| `3864f74` — the reconciliation merge | `ff7b2baf` | same |
| substrate `modules/plans/PlanValidator.ps1` | `8e5da768` | `Test-PlanStructure` |

The bytes in substrate are `a6b61dd`'s. The pin is corrected to `a6b61dd`.

**F28 was right and the manifest misquoted it.** F28's table reads "Copy source `a6b61dd`" and puts
`ff7b2baf` at `e96bba8`; the manifest's pin note had rendered that as *"blob ff7b2baf on main takes
-SchemaPath. Copy was taken from the clone"*, which reverses both halves. F28 needs no correction.
The manifest did, and has it. Recorded here because the first draft of this finding accused F28 of
the inversion, and was wrong: the file was read only after the accusation was written.

**Why it mattered rather than being a typo.** Symbol coverage is measured *at the pin*. Against
`e96bba8` the measurement reported `Get-PlanSchemaPath` missing from substrate and would have
blocked `claude.build.ledger`'s and `claude.build.policy`'s retirement behind a gap that does not
exist — a phantom, produced entirely by pinning a commit the code never came from. At the corrected
pin all three modules measure clean:

```
ledger   pin d57938d1  source and substrate both export Get-LedgerEntry, Get-LedgerStatus,
                       Get-LedgerVerify, Invoke-LedgerForce   missing none
policy   pin 3be10c4   both export Get-PolicyRules                    missing none
plans    pin a6b61dd   both export Test-PlanStructure                 missing none
```

Reproduce with `scripts/Measure-MigrationSymbols.ps1`, which is what `symbols.measured_by` now
names; `-Check` compares its measurement against the manifest and exits 1 on drift.

**What stays open.** `Get-PlanSchemaPath` is real, and it is real on the branch image.builder
actually carries: `3864f74` resolved `src/PlanValidator.ps1` to `ff7b2baf`, so the oneshot rewrite
is what its lineage holds today. The moment this pin is bumped to that blob, `Get-PlanSchemaPath`
becomes a genuinely missing export and `-SchemaPath` stops being inert (F27). That bump is the
**Phase 7** decision and is deliberately not taken here. Until then `plans` wraps the hand-written
validator, and the manifest says which one by sha rather than by branch name.

---

## Phase 6.2–6.4 — the definition of done, measured

Numbering continues from **F59**. Phase 6 resumes at 6.2 with image.builder PR #9 merged
(`5f711736e028f0078d8b32b732ec37cb224258be`), which is the event F54 said Phase 6.2 was waiting
for.

### F60 — DEVIATION: the run order predicted step 6.3, and step 6.3 had already landed

`docs/plans/2026-09-22-substrate-finish/RUN-ORDER.md` step 6.3 schedules the F10 fix as work to be
done in image.builder on a branch `feature/f10-python-shim`: *"images/developer/Dockerfile: make
`python` resolve to python3. Prefer the distro's python-is-python3 package over a hand symlink."*

That work was already inside PR #9 when the run order was written. It is commit
**`0b47155632ef262adcc3ff52776e84ee9f939e84`**, *"fix: python-is-python3 in the developer image —
F10, the sole cause of every in-container red"*, and it landed on image.builder's `develop` with
the rest of PR #9 at merge commit **`5f711736e028f0078d8b32b732ec37cb224258be`**. Measured on
`develop` today, `images/developer/Dockerfile:47` is the single line `python-is-python3 \` inside
the one `apt-get install`, with F10 named in the comment block at `:31-38` — exactly the shape
6.3a asked for, including its preference for the distro package over a hand symlink.

**Step 6.3 was therefore NOT performed.** Nothing was branched, edited, built or merged in
image.builder by this pass; 6.2 was read-only as written. The run order predicted a step that had
already been taken, which is the benign direction for a stale prediction to fail in, and the
evidence that it is the same step is the commit body: `0b47155` states the measurement 6.3c asks
for — developer 167/167, leash 156/167 with all 11 reds in `modules/ledger/tests/python.Tests.ps1`
— before the run order asked for it.

6.2 re-measured all of it rather than quoting it, and the numbers agree exactly. See the
in-container section of `RELEASE-NOTES.md`; F62 and F63 are the two places where something else
did not agree.

### F61 — `verify.ps1` was already red on `develop` before this pass, and its own failure path cannot print

The finish run order's step 0 predicts *"verify 18/19 with check 6 red"*. Measured on `develop` at
`bbacdf19`, before this branch existed: **two** checks are red, and the script does not reach its
verdict line at all.

| | |
|---|---|
| Lines printed before it died | 12 of 19 — 11 PASS, 1 FAIL |
| Check 1, `HASHES.txt recomputes` | **FAIL**, not predicted |
| Check 6, README per-module counts | **FAIL**, predicted |
| Checks 7 and 8 (6 lines) | never ran |
| Exit code | 1 |

**Check 1 has been red since before this run order was written, and nothing noticed.**
`HASHES.txt` was last written by `ef5f08d`. Two commits then changed files in the same directory
without updating it:

| File | Blob at `ef5f08d` | Blob at `bbacdf19` | Moved by |
|---|---|---|---|
| `FINDINGS.md` | `57277386` | `195f54c6` | `797e699` |
| `FLOW-PROOF.md` | `5f4135dd` | `3e3a9355` | `e81848c`, `eedcd50` |

`git merge-base --is-ancestor ef5f08d <each>` exits 0 for all three, so the staleness is theirs and
not this pass's. PR #44, the last thing to land on `develop`, added only `ANALYSIS.md` at the
repository root and is not involved. Nothing in `tests/` covers `HASHES.txt` — the Pester suite is
179/179 green with it stale — so `verify.ps1` is the only thing that reads it, and `verify.ps1` is
not a required check.

**The crash.** After check 5, the script stops with
`Error formatting a string: Index (zero based) must be greater than or equal to zero and less than
the size of the argument list.` The cause is `verify.ps1:217`:

```powershell
$mismatch.Add("{0}: README {1}, measured {2}" -f $name, $stated[$name], $byName[$name])
```

In a method call, PowerShell splits the parenthesised list into arguments *before* `-f` binds, so
the format operator receives one argument for three placeholders. It is reached only when a
per-module row disagrees — which is why a check that has been in the tree since the release has
never once executed this line. Check 6 going red for the first time is what found it. The
`total:` mismatch on the next line uses interpolation and is fine.

**`verify.ps1` is NOT edited**, because the run order forbids it in two places, and because the
bug is confined to the failure path: with the README table corrected the branch is never taken.
`HASHES.txt` **is** regenerated on this branch, since this pass changes `FINDINGS.md` and
`RELEASE-NOTES.md` in that directory and the manifest is meant to describe the directory as it is.
Check 1 and check 6 are both green afterwards, and the verdict line prints 19 of 19 — which is
also the first evidence anyone has that checks 7 and 8 still pass, since no run since `797e699`
has got that far.

### F62 — the developer image is not reproducible, because `__pycache__` is gitignored but not dockerignored

6.2 was told the image ids *"may differ from `0b47155`'s … because the merge commit is a different
tree"*. Measured, the leash id is **identical** and the developer id is not:

| Image | `0b47155` recorded | Measured on `5f71173` |
|---|---|---|
| leash | `sha256:968f1ce9…a50a3a` | `sha256:968f1ce9…a50a3a` — same |
| developer | `sha256:d587a1a1…f15668` | `sha256:165da90f…d9e057` — **different** |

And the offered explanation does not hold. `git diff --stat 0b47155..HEAD` over every input the
developer image `COPY`s — `build/InContainer.Bootstrap.ps1`, `images/developer/managed-settings.json`,
`hooks/`, `entrypoint.ps1`, `src/`, `vendor/claude.agent.substrate` — is **empty**, and only two
commits separate them (`572a6b3`, a grandfather-file edit, and the merge). The tracked tree feeding
that image is byte-identical.

`0b47155`'s image is still in the local store, untagged, so the two were compared directly:
**14 of 17 layers match; layers 13, 14 and 15 differ.** Those are the three ledger `COPY` steps and
the `chown` that follows them. Which narrows it to one thing, and it is present:

```
vendor/claude.agent.substrate/modules/ledger/python/__pycache__
```

`.gitignore` carries `__pycache__/` (F40 added it, so a host Pester run would stop dirtying the
submodule), and image.builder's `.dockerignore` carries `ledger/`, `work/`, `.git/`, `*.md` and
`!README.md` — **no `__pycache__`**. So `git status` is clean while the build context is not, and
`COPY …/modules/ledger/python/ /opt/leash/ledger/python/` carries whatever bytecode the host
happened to leave. Confirmed in the shipped artifact, not inferred:

```powershell
docker run --rm --entrypoint pwsh claude.pwsh.image.developer:run-01 `
  -NoProfile -Command "Get-ChildItem /opt/leash/ledger/python -Force -Recurse -Directory"
  ->  /opt/leash/ledger/python/__pycache__
```

Two consequences, and the second is the one that matters. **An image id is being recorded as
evidence in three documents while it is a function of whether someone ran the tests on the host
first** — so two honest agents on the same commit will record different ids and each will look
like the other is lying. And the leash image, which is *the product*, ships CPython bytecode
compiled by a Windows workstation's Python 3.10 against a `python3.12` runtime it will never use.

Not fixed here: `.dockerignore` is image.builder's file, and 6.2 is read-only. It is a one-line
change there, and `tests/Image.Tests.ps1` is where it would be held. Recorded so that the next
agent who gets a third developer id does not go looking for a tree difference that does not exist.

### F63 — image.builder's `Test.Unit` is 174/2 on a parked clone, because its pull-request range is empty

The prompt for this pass expects `Invoke-Build Test.Unit` at *"176/0 (`0b47155`'s number)"*.
Measured: **176 total, 174 passed, 2 failed.** The total is right; `0b47155`'s body does not
actually state a `Test.Unit` figure, and PR #9's body states `175 / 1` on the feature branch, so
`176/0` has no source. Both reds are in `tests/Trailers.Tests.ps1`, both `Expected 1, but got 0`:

- `rejects a Co-Authored-By trailer, which the CI port would otherwise have dropped` (`:90`)
- `fails with an empty exemption list, so the list is load-bearing rather than decorative` (`:102`)

All three `It`s in `Describe 'the trailer guard over the pull-request range'` drive the range
`origin/develop..HEAD`. On a clone parked on `develop` after PR #9 merged, `origin/develop` and
`HEAD` are both `5f71173` and that range holds **zero commits**:

```
git rev-list --count origin/develop..HEAD   ->  0

Test-Trailers.ps1 -Base origin/develop -Head HEAD -GrandfatherPath <empty file>
  trailer-guard: PASS -- no commits in range                      exit 0

Test-Trailers.ps1 -Base HEAD~10 -Head HEAD  -GrandfatherPath <empty file>
  OK 572a6b35 / 0b471556 / 559103a7 …                             exit 1
```

So the guard is not broken — it is correct on an empty range, and it still goes red on a real one
with the same empty exemption list. The two falsification tests cannot fire because there is
nothing to falsify against, and the third test, `passes, using the exemption`, is **green for the
wrong reason**: it is asserting that a guard over zero commits does not complain.

This is the exact inverse of the red PR #9 pre-registered. There, on the feature branch,
`origin/develop..HEAD` was 33 commits because of the main/develop split, so `passes, using the
exemption` failed and the two falsification tests passed. Merging swapped which half of the
`Describe` is measurable. The three cannot be green together on any clone whose `HEAD` equals
`origin/develop`, which is the state image.builder's own parking rule asks for.

Not a cutover regression, not substrate's, and not fixed here: it is image.builder's suite and 6.2
is read-only. Recorded because a number in the prompt disagreed with the measurement, and because
"the suite is green on a parked clone" is not something anyone can currently say.

### F64 — flipping `review.mode` broke the test that proves the schema rejects a bad `review.mode`

Found by the suite going red one commit after the flip, which is the right way round, and recorded
because the shape of it is the thing this repository keeps catching itself on.

`tests/Skeleton.Tests.ps1`'s *"the schema actually rejects a bad review.mode"* plants a defect by
string replacement and asserts the schema throws on it:

```powershell
$bad = (Get-Content -LiteralPath $script:ConfigPath -Raw) -replace '"mode": "auto"', '"mode": "vibes"'
{ Test-Json -Json $bad -SchemaFile $script:SchemaPath -ErrorAction Stop } | Should -Throw
```

The pattern is the literal `"auto"`. Once `config/repo.json` says `"human"`, the `-replace` matches
nothing, `$bad` **is** the real config, the real config validates, nothing is thrown, and the test
fails: `Expected an exception to be thrown, but no exception was thrown`. 178/179.

The failure is loud and the test is right to fail — but it is failing because its *plant* stopped
working, not because the schema stopped rejecting `"vibes"`. The schema was never consulted about
anything invalid. A falsification whose planted defect is keyed to the current value of the thing
under test silently expires the first time that value moves, and the only reason this one did not
expire quietly is that `Should -Throw` fails closed. Keyed the other way round — a test asserting
something is *absent* — the same drift produces a green (F-shaped: see the detector-shaped-to-the-fix
problem this repo has hit before, and F32, where a check was satisfiable by rewriting a comment).

Repaired in this pass, because flipping the mode is 6.4a's whole job and the flip cannot land with
the suite red. Two changes, not one:

1. The plant matches the mode **value**, not a specific value: `'"mode":\s*"[^"]*"'`. It now works
   at `auto`, at `human`, and at whatever a later phase sets.
2. An anti-vacuity guard, `$bad | Should -Not -Be $good`, asserts the plant actually changed the
   config **before** the schema is asked anything. Without it, this test's failure mode is silence
   rather than a red, which is exactly the trade the repair is meant to close.

`schemas/repo.schema.json` was not touched, and neither was the assertion being made. The `It` count
is unchanged at 179, so no number in `README.md` moves because of this.

### F65 — a draft pull request parks automerge permanently, and the standing-down is green

Not hit in this pass. Recorded because the two halves that cause it are each correct on their own,
which is the reason it survives reading.

`.github/workflows/automerge.yml` accepts three pull request events:

```yaml
on:
  pull_request:
    types: [opened, synchronize, reopened]
    branches: [develop, main]
  workflow_run:
    workflows: [ci]
    types: [completed]
```

and `scripts/Invoke-AutoMerge.ps1:98` stands down on a draft:

```powershell
if ($pr.isDraft) { Write-Step 'pull request is a draft - nothing to do'; exit 0 }
```

Open a pull request as a draft and the sequence is: `opened` fires, automerge exits 0; `ci` runs;
`workflow_run` fires, automerge reads `isDraft` and exits 0 again. Now mark it ready for review.
**`ready_for_review` is not in the `types` list**, so no `pull_request` event fires. No commit was
pushed, so `ci` does not re-run, so no `workflow_run` completes either. The pull request is now
open, not a draft, and all six required checks are green — and automerge will never look at it
again. There is no event left that reaches it.

Nothing turns red, and that is the trap rather than a side effect of it. "I merged it" and "I
declined to look at it" are the same exit code, separated only by a `Write-Step` line that nobody
reads on a green run. The check list on the pull request is entirely green, the automerge job in
its history is a tick, and the branch simply never lands. The cures are all events the list does
accept: push a commit (`synchronize`), close and reopen (`reopened`), or merge it by hand.

`FLOW-PROOF.md` records PR [#20](https://github.com/JerryBalmer1/claude.agent.substrate/pull/20) as
"authored over the GitHub API off `develop` at `f7cbb11`, left as a draft on purpose", and it
merged at `2026-09-22T05:14:52Z`. That one escaped because work continued on the branch after the
draft was opened and each push re-fired `synchronize`. A draft whose work is *finished* before it
is un-drafted has no such push, and parks.

Not repaired here. The fix is one token — `ready_for_review` in the `types` list — but `.github/**`
is outside this pass's scope, and the file's own header note says a `workflow_run` workflow always
runs the copy on the default branch, so the change cannot be demonstrated by the pull request that
makes it. It has to land first and be proven afterwards.

### F66 — PR #42 was merged from the web UI without a trailer, and the guard that went red could not see the commit being blamed for it

Three checks went red on `develop` at `2026-09-22T07:55`: `push-guard`, `trailer-guard`, and
`pester` at 178/179. The diagnosis handed to this pass was that merge commit `25aae04` carried no
`who:` trailer and had been made from the GitHub web UI. Both halves of that are true —
`25aae04`'s committer is `GitHub <noreply@github.com>` and its trailer is empty — and it accounts
for exactly one of the three failures.

`scripts/ci/Test-Trailers.ps1` runs `--no-merges` in CI. **It cannot see `25aae04` at all.** That
exclusion is deliberate and is argued in `docs/plans/2026-09-21-repo-policy/FINDINGS.md` §4: a
merge commit is created by GitHub at merge time, could not be repaired if it landed bare, and would
hold the gate red on every later pull request whose range contained it. What actually failed
`trailer-guard` was the merge's *second parent*, `db785857`, a non-merge commit:

```
docs(grok): DeepSeek induction into the Beverly Hills polycule — who: grok
```

`who: grok` is welded onto the subject line behind an em-dash. A trailer is a line of its own in
the final paragraph; `%(trailers:key=who,valueonly)` — which is what both guards read — returned
empty. `pester`'s *"passes when the only trailerless commit is the grandfathered seed"* failed on
the same commit, from the other direction: 69 commits walked, 1 grandfathered, 1 non-compliant.

So the prescribed repair — amend the merge tip and force-push — would have turned `push-guard`
green and left the other two red, after rewriting published history to achieve it. Recorded because
a plausible diagnosis that explains one visible symptom out of three is more dangerous than no
diagnosis, and the check names were enough to tell them apart before anything was touched.

**There was no repair that only adds history.** `db785857` sits inside the pull request range
(`af696620..HEAD`) and inside the full-history walk permanently; `git revert` appends a commit and
removes nothing from either. Grandfathering was refused on the grandfather file's own terms —
*"Nothing is ever added here to make a red build green. The only commits that belong are ones that
predate the guard and cannot be repaired"* — and `db785857` postdates the guard by months. That
left one move, forbidden by `docs/POLICY.md`: *"never force-push, never amend anything already
pushed."* The pass halted there and Jerry authorised the rewrite.

What was done, values measured rather than asserted:

| | before | after |
|---|---|---|
| content commit | `db785857` | `40bd87c1` |
| merge commit | `25aae04b` | `b1e2ca8c` |
| `who:` on content | *(empty)* | `grok` |
| `who:` on merge | *(empty)* | `jerry` |
| merge parents | 2 | 2 (`6b5a5e34`, `40bd87c1`) |
| tree of the merge | `68d1c9f5` | `68d1c9f5` |

The subject's em-dash suffix was removed and `who: grok` written as the last line; the author
(`Jerry Balmer`, original date) and the tree were preserved by `--amend`. The merge was rebuilt
from `6b5a5e3` and the new commit with `who: jerry`, because Jerry merged it and the trailer is
operator-asserted. `git diff 25aae04 b1e2ca8` is empty — not one byte of content moved. The old tip
is kept locally at `backup/develop-pre-repair-2026-09-22`.

The forensic chain was checked first and is untouched: no record cites either hash, and
`scripts/forensic.ps1 -Verify` reads `records: 10`, tip `7b8cb70c…`, identical before and after.
Measured green locally before the push, not after: `trailer-guard` 69 checked / 1 grandfathered /
**0 non-compliant**, `push-guard` 2 of 2 gates, `pester` **179/179**.

The hole this leaves open is the one §4 closed for merge commits only. A *non-merge* commit that
lands without a trailer — through the web UI, or through any path that does not run the local
hook — wedges `trailer-guard` and the full-history test permanently, and the only exits are a
history rewrite or an exemption the exemption file forbids. §4's reasoning ("a gate that its own
tooling can wedge into permanent failure is a trap, not a gate") applies unchanged to this case; it
was simply not the case §4 was looking at.

who: grok on its own last line. The em-dash cost a force-push to `develop`.

---

## substrate-finish, PR A (retire + F44 TEST 10 + arena-utterance)

### F67 — the cross-platform lying snake was called impossible, the runner said otherwise, and it is built

**F44 TEST 10 is closed on both platforms.** `LedgerResultMismatch` was the one id in the ledger
module's pinned vocabulary with nothing behind it. It now has a test that runs on Windows *and* on
`ubuntu-latest`, with nothing skipped.

This finding is in two parts, because the first attempt was wrong and the way it was caught is the
part worth keeping.

#### What is in the tree

`modules/ledger/tests/fixtures/lying-snake/` holds `result-mismatch.ndjson` — one `result` event,
`"mode": "live"`, whose `sha256` is the genuine hash of its own `output` so the force reaches the
identity check on merit — and two stubs, chosen on `$IsWindows` exactly as step 6.6 Option A asked:

| Stub | Mode | Mechanism |
|---|---|---|
| `lie.cmd` | `100644`, CRLF | `@echo off` / `type "%~dp0result-mismatch.ndjson"` |
| `lie` | **`100755`** | `#!/usr/bin/env pwsh`, `[Console]::Out.Write`; execute bit via `git update-index --chmod=+x` |

Seven `It`s, **all green on both platforms, none skipped**. Ledger **84 → 91**, repository total
**179 → 186**.

| `It` | Asserts |
|---|---|
| the fixture lies about exactly one thing | one event, `mode` differs, `validator`/`model` agree, `sha256` is real, both stubs present |
| the stub itself emits the payload | exit 0 and exactly one line equal to the payload, invoked directly with the module's argv shape and stdin — the layer below the force, isolated |
| the force raises `LedgerResultMismatch` | the id, the message naming `dry-run`→`live`, and that no receipt was written |
| the stub resolves as an `Application` | anti-vacuity: without this, a `LedgerPythonMissing` would look like a pass on the id regex alone. Also asserts `.cmd` on Windows, extensionless **and executable** elsewhere |
| `pwsh -File` rejects a non-`.ps1` **on Windows only** | exit 64 there, exit 0 here — the fact that forces two stubs |
| a `.ps1` is an `ExternalScript` on every platform | why the non-Windows stub has no extension, against the run order's `lie.ps1` |
| the module still resolves `-PythonPath` as an `Application` | by AST, so the two above cannot become true-but-irrelevant in silence |

#### Why the non-Windows stub is `lie` and not `lie.ps1`

The run order specified `lie.ps1` with a shebang. That cannot work, and this constraint is the one
that survived scrutiny: `ledger.psm1:650` resolves the stub with

```powershell
$exe = Get-Command -Name $PythonPath -CommandType Application -ErrorAction SilentlyContinue
```

and a `.ps1` is an `ExternalScript` on **every** platform, execute bit or not. `Get-Command
-CommandType Application` never returns one, so a `lie.ps1` is not found at all and the force dies
as `LedgerPythonMissing` — the wrong error, from the wrong guard, proving nothing about
`LedgerResultMismatch`. A file with no PowerShell extension and the execute bit *is* an
`Application`, and the kernel resolves its shebang to `pwsh /path/to/lie`, which `-File` accepts
outside Windows.

#### SUPERSEDED, kept for the record: this finding first said the twin was impossible

The first version of F67 claimed that **no** PowerShell-interpreted stub could exist on any
platform, and closed the `migration.json` row on Option B's *formal acceptance* limb with the
mismatch `It` marked `-Skip:(-not $IsWindows)`. It rested on a second wall alongside the `.ps1`
one:

> `pwsh -NoProfile -File <file with no extension>` → exit **64**,
> `Processing -File '…' failed because the file does not have a '.ps1' extension`

That measurement is real. **It is Windows-only**, and the finding presented it as a fact about
PowerShell. On `ubuntu-latest` the same command exits **0** and runs the file — which is precisely
the mechanism that makes a shebang stub work there. The conclusion drawn from the pair of walls was
therefore false, and everything built on it was too: the skip, the release-notes text, the
manifest evidence, and an argument that two CI runs would have been "theatre".

**This is FINDINGS F26 arriving from the far side.** F26's lesson was that a suite green on a
Windows workstation can be red on `ubuntu-latest`, so measure on the gate. The failure here is the
mirror image and was not on anyone's list: a *refusal* observed on a Windows workstation, promoted
to a property of every platform, and used to argue that a test **should not be written**. A false
green and a false impossibility are the same error about the same missing measurement, and only one
of them was being watched for.

#### What caught it, and why the fix cost one push rather than a rewrite

The falsifier that was committed **alongside the wrong claim**:

```powershell
$code | Should -Not -Be 0 -Because 'if this ever exits 0, the Linux twin is buildable and should be built'
```

PR #54's first CI run, `pester` red, one failure, that line, `Expected 0 to be different from the
actual value … but got the same value`. The `-Because` string named the remedy before anyone knew
it would be needed, and the next commit built the twin.

Three things are worth stating plainly about that:

1. **The wrong claim was falsifiable, and that is why it survived only 60 seconds of CI.** Had F67
   asserted impossibility in prose alone — as F44 did, for two phases — the hole would still be
   open and the run order's Option A would still be recorded as unbuildable.
2. **Option B was invoked to avoid two pushes, and the first push is what disproved it.** The
   original text argued that running CI twice to collect run ids would be theatre. One run of CI
   was worth more than the entire argument. `F8`'s rule cuts both ways: a test that cannot pass
   proves nothing, and so does a proof that was never run on the thing it describes.
3. **No document escaped.** The skip, the fixture README, `RELEASE-NOTES.md` known gap 1, the
   `migration.json` F44 row and `README.md`'s status table all repeated the false claim and all
   are corrected in the same commit as the fix. A finding that is wrong in six places is wrong in
   six places.

#### The second red: the twin ran, exited 0, and said nothing

Building it was not the end of it. The next CI run failed on the row below the one that had failed
before:

```
[-] a snake that lies about the run it performed raises LedgerResultMismatch
Expected regular expression '^LedgerResultMismatch' to match 'LedgerNoResult,Invoke-LedgerForce'
```

`LedgerNoResult` is *"Snake exited 0 but emitted no result event"*. So the stub was found — the
`Application` resolution `It` was green — and it ran, and it exited 0, and the module parsed
nothing out of its stdout.

**The first diagnosis was wrong.** It guessed the output formatter: the payload is one
~250-character JSON line, the module reads stdout line by line, so a line wrapped at the host's
console width would arrive as two non-JSON lines. Plausible, cheap to fix, and not what was
happening. Two changes went in on that guess — `[Console]::Out.Write` instead of `Get-Content
-Raw`, and `$ErrorActionPreference = 'Stop'` — plus a seventh `It` that runs the stub **directly**
with the module's argv shape and stdin, asserting exit 0 and exactly one line, printing the stub's
real output in its `-Because`.

The third run named it in one line:

```
[-] the stub itself writes the payload verbatim on one line and exits 0
Expected 0, because the stub must exit 0; it wrote:
  Split-Path: Line 31 | … iptRoot) { $PSScriptRoot } else { Split-Path -Parent $PSCommandPath }
  Cannot bind argument to parameter 'Path' it is an empty string.
```

**A shebang-invoked script has no `$PSScriptRoot` and no `$PSCommandPath`.** Both are empty when
the kernel resolves `#!/usr/bin/env pwsh` and pwsh runs the file, so the stub could never locate a
payload sitting beside itself — and that, not the formatter, is what produced the silent run 1 as
well: `Join-Path ''` failed, the default `$ErrorActionPreference` sent it to stderr, and the script
exited 0 with an empty stdout. `lie.cmd` was never affected, because `%~dp0` is cmd.exe's own
answer to the same question.

Fixed by embedding the event in the stub. `result-mismatch.ndjson` stays the single source of
truth — `lie.cmd` prints it, and the direct-run `It` asserts `lie`'s output is byte-equal to its
one line, so the copy cannot drift without going red.

**Three rounds of CI, and the third is the only one that said anything useful.** Run 1 reported a
true fact about the module (*the snake said nothing*) that was useless: `LedgerNoResult` cannot
distinguish a broken stub from a broken module, so it invited a guess, and the guess was wrong.
Run 3 named the file, the line and the variable — because of the `Stop` and the direct-run `It`
that had been added between them. The repairs made on a wrong diagnosis are kept, because both are
right on their own terms; but the thing that actually closed this was **making the fixture fail
loudly**, not making it work. A test fixture gets the same treatment as the code under it, and
this Context has now been taught that twice in one pass.

The `migration.json` row still flips, but on the limb the condition actually names first: *"has a
cross-platform Pester equivalent"*. It has one.

### F68 — the retire condition for policy is written as a grep that cannot pass and cannot see

Step 6.5b asked for a script behind this `retire_when` row on `claude.build.policy`:

> "no other repo imports claude.build.policy by sibling path
> (grep `../claude.build.policy` across the parent folder)"

The parenthesised grep was written first and run first. It is wrong in **both** directions at once,
and the second direction is the dangerous one.

**It cannot pass.** A literal sweep for `../claude.build.policy` and `..\claude.build.policy` across
tracked files in all 12 sibling work trees returns 9 hits for policy, of which two are:

| File | Line |
|---|---|
| `docs/migration/migration.json` | 46 — *the condition's own text* |
| `docs/migration/MIGRATION.md` | 64 — the same sentence, generated |

A condition whose statement violates itself is unsatisfiable by any state of the world. Deleting
every real import in the workspace would still leave it red, and the only way to green it is to stop
writing the condition down. This is `F32` exactly — a check that went red on its own explanation —
and `F64`'s shape as well: a detector keyed to a string rather than to a fact.

**It cannot see.** The one real importer in the workspace produces **no hit**:

```powershell
# claude.build.inspector/src/claude.build.inspector/claude.build.inspector.psm1:20
(Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath
    '..', '..', 'claude.build.policy', 'src', 'claude.build.policy', 'claude.build.policy.psd1')
```

That is a live sibling-path import, resolved at module load for the inspector's optional `-Policy`
path, and the substring `../claude.build.policy` does not occur in it. Seven of the grep's nine
policy hits are prose; the eighth and ninth are the condition describing itself; and the import the
condition exists to forbid is invisible to it.

**What `scripts/Test-SiblingImports.ps1` does instead.** Tracked files only (`git ls-files`, the
reason `Test-Runtimes.ps1` gives). Three buckets, one of which gates:

- **PATH IMPORT** — in a `.ps1`/`.psm1`, a **non-comment** string literal that contains
  `../<target>`/`..\<target>`, or that equals `<target>` while sitting in a `Join-Path` whose
  **immediately preceding segment is `..`**. Parsed, not grepped, so writing down *why* a dependency
  exists is not punished — `F32` again.
- **NAME REF** — a non-comment literal equal to `<target>` anywhere else. `Get-Module -Name
  'claude.build.policy'` is a lookup of something already loaded, not a path, and the condition is
  about paths. Reported, never gating.
- **PROSE** — non-code files and comment tokens. Counted and printed so the zero is not mistaken for
  silence.

The `..`-must-immediately-precede rule is what separates a sibling from a vendored copy. Without it
the sweep flags `image.builder/src/LedgerReceipt.ps1:104`,
`Join-Path $PSScriptRoot '..' 'vendor' 'claude.build.ledger' …` — up one, then **down into its own
`vendor/`** — and lands a finding on a repository that does not have one.

**Measured 2026-09-22 across 12 work trees** (`_run01_cleanclone@f3daad8`, `claude.agent.docs@2c7b0db`,
`claude.agent.images@no-commits`, `claude.agent.interrogator@0bae655`, `claude.agent.substrate@f18c615`,
`claude.agent.tools@d411a3d`, `claude.build.fuzzer@1cf2c63`, `claude.build.inspector@cf5105f`,
`claude.build.ledger@d57938d`, `claude.build.orchestrator@17d7a33`, `claude.build.policy@3be10c4`,
`claude.pwsh.image.builder@5f71173`):

| Target | Path imports | Prose mentions |
|---|---|---|
| `claude.build.policy` | **1** — inspector `psm1:20` | 7 |
| `claude.build.ledger` | **0** | 17 |

The row therefore **stays unmet**, and now says so with evidence instead of a bare `false`. The
ledger count is recorded because 6.5b asked for it even though no row consumes it; zero is the
answer, and the one apparent hit is the vendored path above, which is not a sibling import.

The condition's wording is **not edited** here. Rewriting the rule on the branch that fails it is the
move this repository keeps catching itself at, and the row is unmet on the merits regardless of how
the sentence is phrased. `docs/BACKLOG.md` carries the rewording.

### F69 — neither source retires, and the run order's own gate is what says so

Step 6.5d: *"status → retired, context_policy → do-not-load for claude.build.ledger and
claude.build.policy."* Neither happened. The step's own sentence is the reason:

> `Invoke-Pester tests/Migration.Tests.ps1` — the suite refuses the retire if any `retire_when` is
> unmet.

**`claude.build.policy`** — 3 of 4 met before this pass; the fourth is F68's, measured unmet, and it
is unmet because of a real dependency that is working as designed. `claude.build.inspector` resolves
the policy manifest by sibling path on purpose, fail-open, documented in its own README. Retiring
policy would be declaring dead a repository that another repository loads at runtime.

**`claude.build.ledger`** — this pass moves it from 3 of 7 to **6 of 7**. Rows 6.1, 6.3 and F44 all
flip with evidence. The seventh cannot:

> "the four not-substrate suites have landed in, or been formally dropped by, their destination
> repos"

| Suite | Destination | State |
|---|---|---|
| `continuity.ps1` | `none` | formally dropped, F37 |
| `no_sabotage.ps1` | `none` | formally dropped, F37 |
| `fuzzer_import.ps1` | `claude.agent.tools` | **not dropped, not landed** |
| `hook_pre_tool.ps1` | `claude.agent.images` | **not dropped, not landed** |

`claude.agent.tools` now exists — `d411a3d`, read by the sweep above — but carries two tracked files,
a README and one planning document, and no migration block for `fuzzer_import.ps1`.
`claude.agent.images` is a directory beside this repo with **no commits at all**. Both are placed out
of scope by the substrate-finish run order's own "Out of scope — findings only" list, so this packet
cannot land the suites and has no standing to drop them on those repos' behalf.

**This is a conflict inside the run order, resolved in favour of the gate**, per the same step's
instruction to let the suite refuse. Step 6.5d assumed three rows were all that stood between the
ledger and retirement; a fourth was already there when the run order was written, and nothing in
Phases 6.1–6.6 addresses it.

**Corrections the sweep forced into `destinations[]`.** `AGENTS.md` says measurement beats
expectation, and three `exists: false` claims were measured false-in-the-other-direction:
`claude.agent.tools` (`d411a3d`), `claude.agent.interrogator` (`0bae655`) and `claude.agent.docs`
(`2c7b0db`) all exist and are now `true`, each with a note naming the sha and stating that nothing is
dispositioned to it yet. `claude.agent.images` stays `false`: a directory with no commits is not a
repository, and that is now written down rather than left to coincide.

**The stubs landed anyway**, because 6.5c is not conditional on the retire and a redirect file is
worth more in a repo that is still absorbing than in one nobody opens:

| Repo | Commit | Sits after |
|---|---|---|
| `claude.build.policy` | `54d46ed3f4cf055720f8b07786a70a7558675c9c` | `3be10c4`, its pin — exactly one commit, as VERIFY check 5 asks |
| `claude.build.ledger` | `f6bd9777c9660a26f71e3b013fba0933b4c8f9e4` | `ed9c9d7`, the tip of `main` |

Each adds only `MIGRATION-SOURCE.md`, and each states that its repository is **not** retired and
names the condition that is not met.

**VERIFY check 5 cannot be satisfied literally for the ledger, and the reason is upstream of this
pass.** It asks for one commit after the pin `d57938d`, but `d57938d` is the tip of
`feature/grok-confession-record` and is **not an ancestor of `main`** — `main` was `ed9c9d7`, its
parent. Substrate copied from an unmerged feature commit. 6.5c says "on its default branch", so the
stub is on `main`, where an agent opening the repository actually lands; a redirect parked on an
unmerged branch redirects nobody. The mismatch is recorded in the stub itself and here, and merging
or re-pinning is not this packet's to do.

---

## substrate-finish, PR B (Phase 7 — plans at the consumer's validator)

### F70 — what the validator rewrite changed, measured fixture by fixture, including the two rules nobody scheduled to lose

Phase 7 repoints `modules/plans/PlanValidator.ps1` from blob `8e5da768` to `ff7b2baf`. The old copy
restated the plan rules in PowerShell; the new one reads `schemas/plan.schema.json`. F5, F27 and F28
all close, because the module can now make the claim they forbade it from making. This is what it
cost, measured against every fixture in `modules/plans/tests/fixtures/` before a single test was
edited.

**The falsification table.** Old = blob `8e5da768`. New = blob `ff7b2baf`, schema passed explicitly.

| Fixture / input | Old | New | Moved? |
|---|---|---|---|
| `valid-plan.json` | PASS | PASS | — |
| `no-skills.json` | PASS | PASS | — |
| `missing-id.json` | THROW `Plan missing required field: id` | THROW `plan is missing required property 'id'` | message only |
| `missing-steps.json` | THROW `Plan missing required field: steps` | THROW `plan is missing required property 'steps'` | message only |
| `missing-expected-output.json` | THROW `Plan missing required field: expected_output` | THROW `plan is missing required property 'expected_output'` | message only |
| `step-without-action.json` | THROW `Plan step missing action.` | **PASS** | **LOOSER** |
| `blank-skill.json` | THROW `Plan skills_to_build contains an empty skill name.` | **PASS** | **LOOSER** |
| `id-not-a-string.json` | PASS | **THROW** `plan property 'id' must be a string, got Int64` | **STRICTER** |
| `-SchemaPath <does not exist>` | PASS — nothing opened it | **THROW** `plan schema missing: <path>` | **new failure mode** |
| plan as a `hashtable` | PASS | PASS | — |
| `skills_to_build = @('one')` | PASS | PASS | — the copy's own comments are about this trap and it holds |

Three behaviour changes and one new failure mode. The run order predicted **one** of them.

**The one it predicted.** 7c says *"the step-shape rule is GONE (F4 inverted — a step with no action
passes if the schema allows it; measure, do not assume)"*. Measured: it does. F4 recorded that the
validator and the schema disagreed about what a step is, and resolved it in the validator's favour
because the validator was what image.builder ran. `ff7b2baf` resolves it the other way by
construction — its own header says *"the rules are read from schemas/plan.schema.json rather than
restated here. Two copies of a contract is one copy of a contract plus a bug"* — and the schema says
`steps` is an array with `minItems: 1` and nothing whatever about the shape of a step.

**The one it did not.** `blank-skill.json` also flipped, and nothing in the run order, `FINDINGS` or
`RELEASE-NOTES` anticipated it. The schema declares
`"skills_to_build": { "type": "array", "items": { "type": "string" } }`, and `"   "` is a string.
The old copy rejected any entry that was blank once cast to string; the new one has no notion of
blankness for array items at all. The check did not move — **the contract it reads did**, and the
schema was always the looser of the two. This is the exact shape of F4, found a second time in the
same file, and it is worth saying plainly: bumping to a schema-reading validator does not make the
module stricter, it makes the module *honest about the schema*, and this repository's schema is
permissive.

Neither loss is repaired here. Editing `plan.schema.json` to add `minLength` would be writing a new
plan contract on a branch whose job is to change which validator reads the old one, and the schema
is a `landed` item with a recorded blob that `tests/Migration.Tests.ps1` asserts byte-for-byte.
`docs/BACKLOG.md` carries the question.

**What could not be copied: `Get-PlanSchemaPath`.** 7c says to add it to `FunctionsToExport`. The
copy's own version cannot be the exported one, and this is measured rather than argued:

```
copy's Get-PlanSchemaPath      -> modules/schemas/plan.schema.json      (does not exist)
module's schema                -> modules/plans/schemas/plan.schema.json
```

The copy resolves `Join-Path $PSScriptRoot '..' 'schemas' 'plan.schema.json'`, which is correct in
image.builder — validator in `src/`, schema in `schemas/` at the repository root — and wrong here,
because `modules/plans/` is self-contained and `..` climbs out of it. Re-exporting it would export a
function naming a file that is not there. So `plans.psm1` defines its own, with no parent hop, and
the copy stays unedited. `It j` asserts **both** sides: the exported function finds the real schema,
and the copy's answer does not exist. It also asserts the two disagree — if they ever agree, the
re-implementation is dead weight and should be deleted, and the test says so.

The wrapper passes `-SchemaPath` explicitly on every call, so the copy's broken default is never the
expression that gets evaluated. That is why `It g` and `It i` can assert the parameter is *read*
without the module ever depending on the copy's idea of where the schema is.

**Two smaller measurements, recorded because they were checked rather than assumed.**

- `ff7b2baf` opens with `Set-StrictMode -Version Latest`. It is dot-sourced in a child scope, and
  measured, strict mode does **not** leak out of that scope into the module or a caller.
- The copy still does not call `Test-Json`. It hand-rolls a *subset* of JSON Schema: `required`,
  `type: string` (non-blank), `type: array` with `minItems` and `items.type`. No
  `additionalProperties`, no nested object shapes, no `pattern`, no `enum`. The old `It g` asserted
  the absence of `Test-Json` as a way of proving the module could not claim schema validation; that
  claim is now true on the merits, so the `It` is replaced by the behavioural pair rather than kept
  as a fact about a word in a file. The **subset** is written into the manifest description and the
  `.DESCRIPTION`, because "validates against the schema" is now a sentence this module is allowed to
  say and it must not be allowed to say more than it does.

**Pester: 179 → 180.** `plans` **11 → 12**. Net one `It`: two removed (`g` and `i` in their F27
inertness form), three added (`g` and `i` as behavioural assertions, plus `j`). `d` and `f` inverted
in place, each gaining an anti-vacuity guard first — and both guards were **wrong on their first
run**, which is the reason they are there: `step-without-action.json` has two steps and it is the
*second* that lacks an action, and `blank-skill.json`'s blank entry is `"   "`, not `""`. A guard
written from the fixture's name rather than its contents would have passed while proving nothing.

**F24 closed as well**, 7e's second option declined: `modules/policy/examples/parse-here.ps1` is
fixed rather than deleted. It imported `../src/claude.build.policy/claude.build.policy.psd1`, a path
substrate never had — the `src/<repo-name>/` nesting is gone and the manifest was renamed in Phase 5
(F47) — so the example could not be run at all. The import is now
`Join-Path $PSScriptRoot '..' 'policy.psd1'` and the `.DESCRIPTION` is corrected to match, which is
why its manifest row moves `landed` → `adapted`, tree blob `6e605f63`. Measured after the fix: exit
0, **14 rules** printed from `modules/policy/docs/do-not.md`. An example that runs is worth more than
a row that says `not_migrated`.

**`verify.ps1` now fails two checks, by design, and is NOT edited.** The cutover plan's self-check
hardcodes two facts Phase 7 deliberately moves:

| Line | Expects | Now |
|---|---|---|
| check 7, plans row | exports `Test-PlanStructure` | exports `Get-PlanSchemaPath,Test-PlanStructure` |
| check 8, plans row | `PlanValidator.ps1` is blob `8e5da768` | `ff7b2baf` |

`verify.ps1` is the **2026-09-22 cutover** plan's artifact, and it verifies the tree *that plan*
released. Editing it so that it describes a later tree would falsify the record of what the cutover
actually verified, which is the one thing a verification artifact must not do — and the run order
forbids editing it in two places (F61 records both). It is also not a required check, so nothing in
CI turns red on it. The finish run order's own VERIFY section already anticipates the new state: its
check 8 asks for `ff7b2baf` and for `Get-PlanSchemaPath` to be exported. A future plan directory
gets its own `verify.ps1`; this one stays the receipt it is, and these two lines are the expected
residue, named here so that a reader can tell them apart from a regression.

**Not in this step, and named so nobody assumes otherwise:** repointing image.builder's `Plan.Check`
and `Test.FailFirst` from its local `src/PlanValidator.ps1` at the submodule (F31). That is
image.builder's work, after substrate tags `v0.2.0`, and the manifest row for it stays unmet.

---

## substrate-finish, PR C (definition of done clause 3, the automerge repair, the backlog)

### F71 — `HASHES.txt` went stale a second time, in the commit that recorded F65

`verify.ps1` check 1 was **already red on `develop`** when this packet started, and nothing had
noticed. Measured on `develop` at `705438f`, with the plan directory clean and matching the index:

| File | Recorded in `HASHES.txt` | On disk |
|---|---|---|
| `FINDINGS.md` | `2a5c61d4…` | `e232032a…` |
| the other ten | — | all match |

```
HASHES.txt   last written by  74fc96f  docs: DoD clauses 1-2 measured green in-container; F60
FINDINGS.md  last written by  942a7c0  docs: F65 the draft-PR automerge trap, F66 …
```

`942a7c0` is PR #53. It appended F65 and F66 to `FINDINGS.md` and did not regenerate the manifest
that describes the directory `FINDINGS.md` lives in.

**This is F61 happening again, and the recurrence is the finding.** F61 measured exactly this —
`HASHES.txt` last written by `ef5f08d`, two later commits moving files in the same directory, check
1 red and nobody looking — regenerated the manifest, and got `verify.ps1` to 19/19 for the first
time. Two commits later it was stale again. F61 also named the reason it can keep happening:

> Nothing in `tests/` covers `HASHES.txt` — the Pester suite is 179/179 green with it stale — so
> `verify.ps1` is the only thing that reads it, and `verify.ps1` is not a required check.

So the manifest is guarded by a script that runs only when a human remembers to run it, and the
correct response to "somebody forgot" twice in a row is not to remember harder. It is either a
required check or a Pester `It`, and **neither is added here** — `.github/**` is in this packet's
scope for exactly one line (F65's `ready_for_review`) and no more, and widening it to add a seventh
required check would be the kind of scope creep the packet's stop conditions exist to prevent.
`docs/BACKLOG.md` B1 is adjacent but not the same thing; this wants its own line and gets one.

Regenerated on this branch, as F61 did, with the same construction `verify.ps1` uses. The three
branches of this packet each regenerate it, because each changes `FINDINGS.md`, and whichever lands
last regenerates it once more over the merged directory — the number in a merged tree is not the
number in any branch that fed it, which is itself a small argument for the check being automated.

### F72 — #54's merge commit carries no trailer, and grandfathering it was refused on three measurements

The run order for this reconciliation said: check `develop`'s tip for a `who:` trailer, and if it is
missing, *"that is F66 recurring: add the sha to `config/trailer-grandfather.txt`."* The trailer is
missing — `22db2d32`'s `%(trailers:key=who,valueonly)` is empty, confirmed. **Nothing was added.**
Three measurements say the prescribed repair is aimed at the wrong thing, and AGENTS.md's
*"measurement beats expectation"* makes writing this down the required move rather than an optional one.

**1. The gate is green and structurally cannot see it.** `scripts/ci/Test-Trailers.ps1` runs
`--no-merges` on every path that gates a pull request, which is the whole of §4's argument, restated
in the script's own `.DESCRIPTION`. Measured on this branch before the merge was committed:

```
trailer-guard: range HEAD, key 'who', allowed [claude, grok, fable, jerry]
trailer-guard: 71 commit(s) checked, 1 grandfathered, 0 non-compliant
trailer-guard: PASS
```

No exemption is needed for a commit the guard never walks. Adding one would appear in the output as
`note: grandfather entry 22db2d32 was not needed in this range` on every future run.

**2. It is not alone, so the exemption makes nothing green.** The only path that does see merges is
`-IncludeMerges`, which `docs/plans/2026-09-21-repo-policy/verify.ps1` runs against `origin/main`.
Measured over `develop` at `22db2d32`:

| Commit | Merge of | `who:` |
|---|---|---|
| `22db2d32` | PR #54 `feature/retire-ledger-policy` | *(empty)* |
| `705438fe` | PR #53 `feature/trailer-repair-findings` | *(empty)* |

```
trailer-guard: 119 commit(s) checked, 1 grandfathered, 2 non-compliant
trailer-guard: FAIL
```

**Two**, not one. The instruction names only `22db2d32`, and exempting it alone leaves that run red on
`705438fe` — a commit that predates this packet and that no step in this run order mentions. An
exemption that does not change any exit code is not a repair.

**3. The file forbids it, and F66 already invoked that clause to refuse this exact move.**
`config/trailer-grandfather.txt`'s header: *"Nothing is ever added here to make a red build green. The
only commits that belong are ones that predate the guard and cannot be repaired."* F66 refused
grandfathering `db785857` on those terms and took a Jerry-authorised history rewrite instead. Both
merges here postdate the guard by months.

**And it would turn a green test red.** `tests/Trailers.Tests.ps1` → *"exists and lists exactly one
hash"* asserts `$hashes.Count | Should -Be 1` and `$hashes[0] | Should -Be $script:Seed`. That
assertion is the file's stated point — *"a list of forty-character strings has a length you can
assert"* — so adding a second hash without editing the test lands a red PR, and editing the test to
expect two is the quiet widening the guard's `.DESCRIPTION` names as the thing to avoid.

**This is not F66 recurring.** F66's red was `db785857`, a **non-merge** commit with `who: grok`
welded onto its subject line behind an em-dash, which `%(trailers:...)` reads as empty. That defect
wedges the everyday PR gate permanently. A bare **merge** commit is the ordinary, deliberate,
documented case `--no-merges` exists for. The two share a symptom and have nothing else in common.

**What is actually open.** `.github/workflows/automerge.yml` writes `who: claude` into the merge
commit body; a merge made any other way does not. #53 and #54 were both merged outside automerge, so
both landed bare. The defect is in the merge path, not in the exemption list, and the honest repair is
either a trailer on the merge button's output or a formal acceptance that `-IncludeMerges` over
`main` is advisory. `docs/BACKLOG.md` carries it; this branch does not widen its scope to fix it.

---

## substrate-finish, PR D (closing the definition of done)

### F73 — the `develop == main` release gate is unreachable by construction, and the five counter-examples are one branch cut from the wrong base

The previous packet gated the release on `develop == main` — the two refs resolving to the same
sha. **No release can ever satisfy it**, for the same reason F55 retired the old definition of done:
the condition describes a shape the flow does not produce.

The release flow is `develop -> main`, merged with a merge commit. That commit's first parent is
`main`'s prior tip and its second parent is `develop`'s tip, so **the merge commit exists only on
`main`**. `develop` is left pointing at the second parent. `main` is therefore always exactly one
merge commit ahead, `develop` never fast-forwards to it, and the two shas are never equal — not
transiently, not after a delay, not ever, without a back-merge that this flow does not perform.

Measured over every release merge in the repository, `origin/main` at `3218eb8`:

```
3218eb85  p1=af696620  p2=b1e2ca8c   reachable from develop: NO
af696620  p1=48f938f9  p2=039d4a37   reachable from develop: NO
48f938f9  p1=a34ee07a  p2=565e1657   reachable from develop: NO
a34ee07a  p1=c03c5ad2  p2=e5e7bbfd   reachable from develop: NO
c03c5ad2  p1=e679feff  p2=09c4b066   reachable from develop: NO
e679feff  p1=3933dccf  p2=728db2f6   reachable from develop: NO
3933dccf  p1=b04a2c4d  p2=1c0d068e   reachable from develop: YES
b04a2c4d  p1=9dfe772c  p2=7d9aa99f   reachable from develop: YES
9dfe772c  p1=970ab5f6  p2=912c1c9e   reachable from develop: YES
970ab5f6  p1=a2c86ec5  p2=e4d0e6f2   reachable from develop: YES
a2c86ec5  p1=1e694df7  p2=5e0acd55   reachable from develop: YES
```

Eleven release merges, every one of them `p1 = main`, `p2 = develop`.

**The five `YES` rows are not the flow working, and finding out which was the point of measuring.**
They are not back-merges: no merge commit on `develop` names `main` at all. They trace to a single
irregularity. `git rev-list --children` gives `3933dccf` — `main` at `v0.1.0` — exactly two
children:

```
e679feff  Merge pull request #34 from develop        <- the next release merge, on main
edc3c7a5  docs: substrate analysis and hello to all agents
```

`edc3c7a5` is the first commit of `feature/substrate-analysis-2026-09-21`, and it was **branched off
`main`, not off `develop`**. PR #44 merged that branch into `develop`, and main's history rode in
behind it. Every release merge up to and including `v0.1.0` became reachable from `develop` as a
side effect of one branch cut from the wrong base. Every release merge after that event is `NO`,
which is the flow behaving exactly as designed.

So the gate is unreachable, and the only history that ever looked like it satisfied the gate is
history that got there by breaking the branch rule. A gate whose sole precedent is a defect is not
a gate.

**The replacement gate is a different claim and is correct.** `git merge-base --is-ancestor develop
main` asks whether `develop` is *reachable from* `main`, not equal to it. Immediately after a
release merge `develop`'s tip **is** the second parent, so it is an ancestor and the check exits 0.
It goes to 1 only when `develop` has advanced past the release, which is the thing worth stopping
for. Ancestry is the right relation; equality was never available.

**This is the second instance of the same defect in two days, in two repositories.** The
`claude.agent.tools` A0 preflight in the run order of 2026-09-22 opens with
`git -C ../claude.agent.substrate rev-parse v0.2.0 main develop`, required to *"print one sha three
times"*. Two of those three refs are `main` and `develop`, so that gate is unsatisfiable here for
precisely the reason above, independently of `v0.2.0` not existing yet. It halted that run order at
A0. Recorded together because the pattern — writing a gate that asserts two branch refs are equal
under a flow that guarantees they are not — is the reusable mistake, not either instance.

Neither gate is edited by this finding. F55's precedent applies: the condition is recorded as
unreachable and the replacement is stated, and the frozen artifact keeps saying what it said.
