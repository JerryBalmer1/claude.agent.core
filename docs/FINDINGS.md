# FINDINGS — claude.agent.core

This repository's own findings. Numbering continues from the cutover that produced it:
F1–F73 are in [`docs/plans/2026-09-22-substrate-cutover/FINDINGS.md`](plans/2026-09-22-substrate-cutover/FINDINGS.md)
and belong to the source repository. Nothing below renumbers them.

---

## F74 — core is a clean copy of `claude.agent.substrate@e40ba414` (tag `v0.2.0`)

The working tree was copied; the history was not. The initial commit is the one commit in this
repository's life that is not a merge, and it is a root commit with no parents. Every commit after
it arrives through `feature/* -> develop -> main` and is a merge.

`push-guard` is therefore **red on the root commit, by design**. It asserts two parents and a
`who:` trailer, and a root commit has no parents to assert; the trailer half passes. It is not a
required check, it goes green from the second commit onward, and the red is left standing rather
than special-cased — a tripwire with an exception for the one commit nobody could route through
the flow is a tripwire with an exception.

**Not carried:**

| Path | Why |
|---|---|
| the git history | a copy is not a fork; the chain of custody is `source_sha` in forensic seq 1, not 137 commits of someone else's branch names |
| `.agents/` | a roster of four agents, their correspondence, and the arena. This repository has one writer |
| `.continuity/forensic.jsonl` | the source's chain stays with the source at 11 records. This one starts at seq 1 |
| `config/trailer-grandfather.txt` | it exempted one trailerless root commit that does not exist here. An exemption list with nothing to exempt is an attack surface, not a control |
| `docs/migration/` and `schemas/migration.schema.json` | plus `scripts/New-MigrationReport.ps1`, `scripts/Measure-MigrationSymbols.ps1` and `scripts/Test-SiblingImports.ps1`. The manifest tracked a migration *into* the source repository. Core is the result of that migration, not a participant in it |
| `docs/plans/2026-09-21-closeout/`, `docs/plans/2026-09-21-repo-policy/`, `docs/plans/2026-09-22-public-release/` | closed run orders for work that predates this tree. `PROTECTION.md` was moved out to `docs/PROTECTION.md` first, because CI and two test files cite it as live evidence |
| every `TRANSCRIPT.log`, `PHASE-2-PROMPT.md`, `PHASE-3-PROMPT.md` | session transcripts and prompts, not evidence about this tree |
| `ANALYSIS.md`, `docs/BREADCRUMBS.md` | correspondence addressed to agents that do not write here |

**Core's suite is the source's minus every test that asserts a fact about the source's own git
history.** That is the whole of the difference, it is 27 tests, and F78 names them one by one.

`docs/plans/2026-09-22-substrate-cutover/` and `docs/plans/2026-09-22-substrate-finish/` **are**
carried, verbatim, including the agent names, legacy repository names and pull-request numbers in
them. They are the archived record of the migration and they are not rewritten to match this
repository's naming. A quoted trailer, a measured branch name and a captured stdout block are
evidence; editing evidence so it reads more tidily is the failure mode this repository exists to
make visible.

## F75 — the runtime rule was wrong and is now data

The source said "PowerShell only". The repository was never that: it has shipped a Python engine
under `modules/ledger/python/` since the ledger module landed. A rule the tree has always violated
is not a rule, it is a sentence nobody reread.

The corrected rule is in `config/repo.json` → `runtimes.rule`, rendered verbatim into
`docs/POLICY.md` by `scripts/Generate-Policy.ps1`, restated in `AGENTS.md`, and bounded by
`runtimes.python.allowed_under`, which `scripts/ci/Test-Runtimes.ps1` measures. Prose that lives
only in a generated file is prose the config cannot be held to; the rule is now config, and the
generated file is its evidence.

The process boundary is load-bearing, not incidental: `LedgerPythonMissing`, `LedgerSnakeFailed`,
`LedgerNoResult` and `LedgerResultMismatch` exist because the module receives strings from another
process and cannot attest to a retry count it never observed. An in-process port deletes four
pinned error ids and leaves the lying-snake fixture nothing to lie to.

**`tenacity` remains declared in `modules/ledger/python/requirements.txt` at birth.** It is never
imported and never installed — CI deliberately does not run `pip install -r requirements.txt`, and
`python.Tests.ps1` asserts both that the SDK is absent and that the dry-run works anyway. It stays
because `requirements.txt` is one of the eleven blobs pinned in
`modules/ledger/tests/fixtures/copied-blobs.psd1`: removing a line would break a provenance claim
in order to tidy a dependency that costs nothing. Retirement is BACKLOG **B10** — both edits in one
pull request, with a receipt.

## F76 — `ModuleVersion` is `0.2.0` here and `0.1.0` there, deliberately

All three manifests report `0.2.0`. The source's report `0.1.0`, and that is not staleness: its
`modules/ledger/ledger.psd1` is a byte-level provenance proof, and one `It` there reconstructed the
source manifest in memory to show the only difference was the `RootModule` filename.

Core makes no such copy claim about its manifests, so that assertion is **deleted, not left
failing** — `modules/ledger/tests/ledger.Tests.ps1` no longer carries *"ledger.psd1 differs from
the source manifest by exactly the RootModule filename"*. The other ten blob rows and the
falsification control are untouched and still pass: `ledger.psd1` was deliberately absent from that
table to begin with.

`policy.Tests.ps1`'s *"the oracle is never rewritten"* holds from core's birth at `0.2.0` rather
than from a version bump applied later.

**`verify.ps1` changed in four places**, not the one the run order allowed, and each is named here
because a verification script edited quietly verifies nothing:

| Line | Change | Why |
|---|---|---|
| `:257` | version pin `0.1.0` → `0.2.0` | it reads the **live manifest** via `Import-Module`, not a dated receipt. Left alone it would red all three manifests |
| `:55` | `$Seed` removed | it held the source's trailerless root commit sha. That object does not exist here |
| `:136` | `Test-Trailers` loses `-Base $Seed` | with no seed to skip past, the range is the whole history, which is one commit, and it carries a trailer |
| `.DESCRIPTION` | the sentence describing that invocation | a description that contradicts the code is worse than no description |

**The branch-name blind spot.** `verify.ps1` derives its branch with
`git rev-parse --abbrev-ref HEAD` and passes it to `Test-BranchFlow`. `config.flow` has rows for
`feature/* -> develop` and `develop -> main` and nothing else, so the check passes **only from a
branch named `develop`**. From `main` it reports 16/19; from a detached checkout at a tag it reports
16/19 with head literally `HEAD`. Neither is a result about the tree. Run verify from `develop`.
BACKLOG **B9**.

## F77 — `claude.build.orchestrator` was created and deleted

Created 2026-09-19, one commit made through the web UI, no pull requests, no content. Deleted. It
is recorded here so a future reader who finds the name in a log does not go looking for a
repository that never held anything.

## F78 — the guard suites tested the source's history, not the guard

`tests/PushGuard.Tests.ps1` and `tests/Trailers.Tests.ps1` pinned **live commit shas** from the
source repository as fixtures — `e4d0e6f2…` (two parents, `who:` trailer), `3e1e4dc6…` (one
parent), `852f8c7d…` (the trailerless root) — and read `config/trailer-grandfather.txt` for an
exemption list naming that root.

A clean copy has none of those objects, and that is worse than absent. In a tree without them, the
assertions expecting a **non-zero** exit went green off `git`'s own `fatal: bad object` rather than
off the guard refusing anything. Measured, not assumed: a shallow clone of the source reproduced it
— nine reds across these two files, plus one silent false green in *"does not consult the
grandfather file, because a push is not history"*, which asserts only `ExitCode | Should -Be 1` and
got it from git failing to resolve a sha.

The guards themselves — `scripts/ci/Test-PushGuard.ps1` and `scripts/ci/Test-Trailers.ps1` — are
carried unchanged and still run in CI, where the pull-request event supplies real base and head
shas. What is gone is the local fixture suite around them.

**Removed at birth, 27 tests.**

`tests/Migration.Tests.ps1` — whole file, 12, because `docs/migration/` is not carried:

1. exists, parses, and is version 1
2. validates against `schemas/migration.schema.json`
3. names substrate as its own authority at this path
4. every landed or adapted item exists in this tree
5. every pending item does NOT yet exist in this tree
6. no not-substrate suite file exists under `modules/`
7. every `allowed_in_tree` path exists and really does share the leaf it excuses
8. every landed item with a blob is byte-identical to that blob in this tree
9. every adapted item really does differ from its recorded source blob
10. a source is only retired when every `retire_when` condition is met
11. a source with unmet retire conditions is not marked do-not-load unless it is deleted
12. `MIGRATION.md` is the generator output for the current manifest

`tests/Trailers.Tests.ps1` — whole file, 8, the pinned seed plus the grandfather file:

13. exists and lists exactly one hash
14. every hash in it is a full 40-character sha that really is a commit here
15. exempts only commits that actually lack a trailer
16. passes when the only trailerless commit is the grandfathered seed
17. still fails a trailerless commit that is not in the grandfather file
18. fails when the grandfather file is empty
19. fails when the grandfather file is missing entirely
20. the pull-request range still passes without needing the exemption at all

`tests/PushGuard.Tests.ps1` — the second `Describe`, 5, all three pinned fixtures:

21. passes a merge commit that carries a `who:` trailer
22. fails a single-parent commit even though its trailer is perfect
23. fails a commit with no trailer
24. names both failures rather than stopping at the first
25. does not consult the grandfather file, because a push is not history

`tests/Skeleton.Tests.ps1` — 1, `.agents/` is not carried:

26. has one folder per agent under `.agents/`

`modules/ledger/tests/ledger.Tests.ps1` — 1, see F76:

27. `ledger.psd1` differs from the source manifest by exactly the `RootModule` filename

The first `Describe` in `tests/PushGuard.Tests.ps1` survives and still asserts the wiring: the
workflow exists, it watches both long-lived branches read from config, and it is never a required
check.

**What is now untested.** The guards' negative path — a trailerless commit, or a single-parent
commit arriving on a long-lived branch, must exit 1 — has no local test in this repository. The
guards run in CI and would still catch it there; nothing here proves they would. BACKLOG **B11**
rebuilds these against repositories the test constructs in `TestDrive`, with a trailerless root, a
one-parent commit and a two-parent merge built on the spot and no pinned shas, so the suite tests
the guard instead of testing that a sha still resolves.

## F79 — the copy carried bytes and not modes

`modules/ledger/tests/fixtures/lying-snake/lie` is `100755` in the source repository and landed
here as `100644`. The copy was written with `[System.IO.File]::WriteAllBytes`, which reproduces
content exactly and knows nothing about a git file mode. The blob sha is identical in the source,
in the birth commit and after the repair — `8727348e41a05a22cc1f591a0ba4b9b8c6f73de8` — so nothing
about the file's content was ever wrong. One bit in the index was.

**Windows cannot observe it.** The assertion that existed,
*"the stub the module will actually resolve is an Application, and it is the right one for this
platform"*, reads `[System.IO.File]::GetUnixFileMode` and is inside an `if (-not $IsWindows)`
branch. On the machine the copy was made on, that branch never ran. The local suite was 161/161
and the tree was wrong at the same time.

**CI on `ubuntu-latest` caught it**, as three reds that each looked like a different bug:

- `the stub itself writes the payload verbatim on one line and exits 0`
- `a snake that lies about the run it performed raises LedgerResultMismatch` — raised
  `LedgerSnakeFailed` instead, because a stub without the execute bit cannot be run at all
- `the stub the module will actually resolve is an Application…` — *"Expected UserExecute… but got
  None"*, the only one of the three that named the actual cause

161 total, 158 passed, 3 failed. A green Windows run and a red Linux run on the same commit, and
the difference was a permission bit that the green runner has no concept of.

**Repaired through the flow, not by amendment.** `git update-index --chmod=+x` on
`feature/restore-lie-mode`, merged to `develop` and then to `main`. The birth commit still carries
the wrong mode and is not rewritten. A repository that force-pushes over its first mistake has no
standing to demand evidence from anything else.

**The missing test now exists.** *"lie is tracked as 100755, so the execute bit survives a copy
that carries only bytes"* reads `git ls-files -s` and asserts the mode in the **index**, so it is
the same assertion on every runner instead of one that quietly abstains on Windows. It was run
against `develop` before the chmod and failed with
`'100644 8727348e… lie'`, and passes after. A test added without being watched fail is a test
nobody has evidence about.

**A full mode audit was run**, every tracked path present in both trees compared against the
source: exactly one difference before the repair and zero after. Both trees hold exactly one
executable, and it is this file.

**One more thing this commit does not fix.** The birth commit's message carries a
`Co-Authored-By:` line above its `who: claude` trailer, which the run order's template did not
have. It is left alone for the same reason the mode is: a pushed commit is not rewritten here.
`AGENTS.md` → *The trailer rule* now says the only trailer is `who:`, with no footer beneath it,
so it does not recur.

## F80 — v0.2.0 is cut against a `main` that cannot be protected

`claude.agent.core` is private, the account is on the **free** plan, and branch protection and
rulesets are paid features for private repositories. Five calls were made against this repository
on **2026-09-22T23:15:42Z** — `PUT branches/main/protection`, the same for `develop`,
`POST rulesets`, and read-backs of the first and third — and all five returned **HTTP 403**,
`"Upgrade to GitHub Pro or make this repository public to enable this feature."` The repository's
settings were read back afterwards and were unchanged by any of them. `docs/PROTECTION.md` carries
the transcripts verbatim.

**403 is not 404, and the difference is the finding.** A 404 would mean the feature exists and the
branch is simply unprotected — something a person can go and fix. A 403 is the tier declining to
offer the feature at all. There is no setting anybody can toggle here, which is why this is
recorded as a property of the tag rather than as a task somebody forgot.

Substrate's copy of `PROTECTION.md` carried a caveat at this point: its `develop` did not exist on
origin when the call was made, so its 403 could in principle have been standing in for a 404. That
confound does not apply here. `develop` existed on this repository's origin before the call, having
been pushed at birth and merged into twice since.

**What the pin actually rests on.** Anything that pins `v0.2.0^{commit}` — the images repository as
a submodule, tools at Phase 0 — is trusting that `main` will not be rewritten underneath it. That
trust is held up by:

| Control | Strength |
|---|---|
| `push-guard` | after the fact. It cannot refuse a push; it makes one loud, dated and public |
| the flow rules in `AGENTS.md` | convention. Never squash, never rebase, never force-push, never amend anything pushed |
| the merge-method lock | a real server-side refusal, and the only one here: `mergeCommitAllowed true`, `squashMergeAllowed false`, `rebaseMergeAllowed false`, `deleteBranchOnMerge true`. It reverses with one `gh repo edit` |
| branch protection | **absent, and not available** |

None of those stops a direct or force push to `main`. A consumer pinning this tag should pin by
`v0.2.0^{commit}` — a commit sha is the same object whatever a ref later says — and should not read
the tag as evidence that the branch beneath it is immutable. **Anything pinning this tag inherits
this.**

This is stated before the tag is cut, not discovered after. A pin whose weakness is documented is
a different thing from one whose weakness is found later by whoever trusted it.

**Closes** when the account is Pro or the repository is public *and* the three calls in
`docs/PROTECTION.md` → "What was attempted" succeed, re-run unchanged. BACKLOG **B12**.
