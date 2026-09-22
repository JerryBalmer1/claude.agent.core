# FINDINGS — claude.agent.core

This repository's own findings. Numbering continues from the cutover that produced it:
F1–F73 are in [`docs/plans/2026-09-22-substrate-cutover/FINDINGS.md`](plans/2026-09-22-substrate-cutover/FINDINGS.md)
and belong to the source repository. Nothing below renumbers them.

---

## F74 — core is a clean copy of `claude.agent.substrate@e40ba414` (tag `v0.2.0`)

The working tree was copied; the history was not. The initial commit is the one commit in this
repository's life that is not a merge, and it is a root commit with no parents. Every commit after
it arrives through `feature/* -> develop -> main` and is a merge.

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
