# DECISIONS — claude.agent.core

The register of decisions that have **teeth**: rules that are currently true of this repository
and that something, somewhere, enforces. Not a log of every choice made. A choice nobody checks
is a preference, and preferences live in prose.

**How this differs from the two files beside it.**
[`docs/FINDINGS.md`](FINDINGS.md) records **measurements taken at a date** — what was true when
somebody looked, including things that have since changed. This file records **rules that are
true now**. [`docs/IDEAS.md`](IDEAS.md) records what was **said and might be done**; nothing here
is speculative, because every entry names the thing that would go red if the rule were broken.

**Shape of an entry.** A stable ID (`D001` upward, **never reused**, never renumbered), the
decision in one sentence, the date it became true, what enforces it and **where** — a measured
`file:line`, not a recalled one — what retiring it would cost, and the reasoning as it stood at
the time rather than as it reads now.

**Leaving this file.** An entry leaves only when its enforcement is removed, and the removal gets
a row in `FINDINGS.md` citing the D-number. A decision that quietly stops being enforced and
quietly leaves this register is exactly the failure this repository exists to make visible.

One entry is deliberately here **without** enforcement — D005 — and says so in the same words it
would use if it had some. An honest register has to be able to record a rule that is policy and
nothing else, or it becomes a list of tests with a nicer heading.

---

## D001 — Six required checks, and no seventh

**Decided** 2026-09-22, carried into core at its birth commit `46debc4`. Origin: F17.

**Enforced by**

| Where | What it does |
|---|---|
| `tests/Runtimes.Tests.ps1:141-145` | the test named *"has not added a seventh required check"*: `required_checks` counts **6**, contains `requires-header`, and does **not** contain `runtimes` |
| `config/repo.json:21-28` | the six names themselves: `requires-header`, `trailer-guard`, `branch-flow`, `generated-match-config`, `pester`, `forensic-verify` |
| `scripts/ci/Test-GeneratedMatchesConfig.ps1:66-83` | the set of `ci.yml` job keys must equal `config.required_checks` exactly — this is what makes adding a job a red rather than a surprise |
| `.github/workflows/ci.yml:25-29`, `:41-47`, `:87-89` | three comment blocks restating it at the three places a seventh job would most naturally have been added |
| `scripts/ci/Test-Runtimes.ps1:12-14` | restates it from the check's own side |

**Cost of retiring it.** Every new required check is a name branch protection has never seen. On
a repository where branch protection is refused outright (F80, `docs/PROTECTION.md`) the cost is
different from the one F17 priced, and that is the open half of this entry, below.

**Reasoning at the time.** F17, at
`docs/plans/2026-09-22-substrate-cutover/FINDINGS.md:231`: *"A newly required check name that
branch protection has never seen is a check that can go red while the merge proceeds anyway."*
So a second runtime rule arrives as a **step** of an existing job, never as a new job key.

**The argument for lifting this, recorded because it has not been made.** F17's mechanism assumes
branch protection exists and has a list of check names that can fall out of date. In core it does
not: protection was attempted and refused with HTTP 403 five times on 2026-09-22 (F80, B12), and
**CI is the enforcement**. A check name branch protection has never seen costs nothing when
branch protection does not exist. On that reading F17's mechanism does not bite here and D001 is
being held for a reason that is true of a repository other than this one.

Both halves are recorded on purpose. The argument is not the decision — nobody has made it, and
until somebody does, the six stand. If they are ever lifted, this paragraph is the head start.

## D002 — The ledger module is not byte-pinned

**Decided** 2026-09-22, at commit `d182cbe` (*"test: retire the ledger.psm1 byte pin"*), forensic
receipt **seq 4**, subject `retire-ledger-psm1-pin`.

**Enforced by an absence, which is the hard part to see.** There is **no row** for `ledger.psm1`
in the `Files` array at `modules/ledger/tests/fixtures/copied-blobs.psd1:41-51`. Nine rows are
there; that one is not, and neither is `ledger.psd1`. The tenth was `docs/commands.md`, retired at
`88d507b` under this decision, one axis over. Nothing asserts the module's bytes against
`claude.build.ledger@d57938d` at HEAD, and that is the enforcement: the check that would fail if
core edited its own ledger module does not exist, deliberately.

Say it as an absence rather than leave it to be noticed. The reasoning is written into the
fixture itself at `modules/ledger/tests/fixtures/copied-blobs.psd1:15-26`, so a reader who opens
the file finds it; a reader who only runs the suite sees nothing at all, which is the point and
also the risk.

**Cost of retiring it** — that is, of re-pinning. Core could never again change its own ledger
module without breaking a provenance claim, and the claim it would be protecting is one the birth
commit already records permanently.

**Reasoning at the time.** Birth fidelity to the source is a fact about the **birth commit** and
is recorded there for good. Re-asserting it at every HEAD does not add evidence; it adds a veto.
F76 set the precedent when `ModuleVersion` diverged on purpose. From `d182cbe` onward core's
ledger module diverges from upstream **on purpose**, and no row in that file claims otherwise.

## D003 — The forensic record shape is frozen

**Decided** at the chain's genesis record; `scripts/forensic.ps1:35` states it as *"Schema
forensic-v1, eight keys, in this order, frozen from birth"*. Core's genesis is seq 1,
subject `core-born`, 2026-09-22.

**Enforced by**

| Where | What it does |
|---|---|
| `scripts/forensic.ps1:96` | the frozen list: `ts, seq, actor, kind, subject, evidence, prev, self` |
| `scripts/forensic.ps1:205-207` | the record must have exactly eight keys — a ninth or a missing one is a terminating error naming the count it found |
| `scripts/forensic.ps1:208-212` | key **order** is asserted position by position, case-sensitively (`-cne`), because the canonical payload is built in that order and a reordered record hashes to something else |
| `scripts/forensic.ps1:201-204` | a duplicate key is rejected before the count is taken |
| `.github/workflows/ci.yml:102-107` | `forensic-verify` runs `scripts/forensic.ps1 -Verify` as one of the six |
| `tests/Skeleton.Tests.ps1:141-152` | the chain must also be **non-empty** — an absent chain verifies green, which is the loudest tampering producing the quietest signal |

**Cost of retiring it.** A ninth key invalidates every `self` already written, because `self` is
the sha256 of the canonical payload over exactly those eight fields in exactly that order. There
is no migration that preserves the existing hashes; the chain would restart.

**Reasoning at the time.** `scripts/forensic.ps1:27-32`: a continuity or forensic entry must
never be forced into the receipt schema, for the same reason — one shared format means one shared
freeze. Two chains, two schemas, both frozen, neither able to break the other.

## D004 — Branch flow is `feature/*` -> `develop` -> `main`, and nothing else

**Decided** 2026-09-22, carried at birth.

**Enforced by**

| Where | What it does |
|---|---|
| `config/repo.json:9-12` | `flow` is the only place the pairs are written: `["feature/*", "develop"]` and `["develop", "main"]` |
| `scripts/ci/Test-BranchFlow.ps1:38-48` | the pull request's (head, base) pair must match a row; anything else exits 1 with *"work goes feature/* -> develop -> main. Nothing skips develop."* |
| `.github/workflows/ci.yml:62-68` | the `branch-flow` job, one of the six |

**Cost of retiring it.** `feature/x -> main` becomes expressible, and `develop` stops being a
place every change has been seen. The hotfix path people usually want this for has not been
asked for.

**Reasoning at the time.** `scripts/ci/Test-BranchFlow.ps1:7-11`: the flow is data in one file
rather than prose in several, so the rule and the check cannot drift. There is no path that skips
`develop`.

**Known limitation, not a retirement.** The check derives the head from
`git rev-parse --abbrev-ref HEAD`, which is literally `HEAD` on a detached checkout, so a verify
run from a tag reports a failure that is about the branch name and not about the tree — F76,
BACKLOG B9.

## D005 — Old repositories are frozen, and history is never rewritten

**Decided** as standing policy; stated in `AGENTS.md:48-52` (*"The merge rule"*) and
`README.md:105-106`.

**Enforced by — nothing in this repository.** This is the one entry in this register whose
enforcement is a sentence rather than a check, and it is here rather than omitted because a
register that only lists enforced rules would suggest the unenforced ones do not exist.

What exists is not enforcement of this rule:

- `scripts/ci/Test-PushGuard.ps1` asserts two parents and a `who:` trailer on pushes to this
  repository's long-lived branches. It is **not** in `config/repo.json:21-28` — it is not one of
  the six — and `.github/workflows/push-guard.yml` is advisory. F74 records that it is red on the
  root commit by design.
- Nothing in core can observe, let alone refuse, a force-push in `claude.agent.substrate`,
  `claude.pwsh.image.builder` or any other sibling. `AGENTS.md:114-116` puts siblings behind the
  wall, which stops *this* agent touching them; it does not freeze them.
- Branch protection, which is where a server-side refusal would live, returned HTTP 403 five
  times on 2026-09-22 and changed nothing (F80, `docs/PROTECTION.md`, BACKLOG B12).

**Cost of retiring it.** Nothing mechanical, which is the finding. The cost of *breaking* it is
that every sha quoted in this repository's findings, receipts and pull request bodies stops
resolving, and the evidence those documents are made of becomes unverifiable prose.

**Reasoning at the time.** Hashes are evidence here. `README.md:106`: *"a squash destroys the
evidence and a rebase forges it."* The reasoning is sound and unimplemented, and both facts
belong in the register.

## D006 — The PR template's banner URL points at `develop`, not at a pinned sha

**Decided** 2026-09-22, at commit `4ae560a` (*"fix: banner URL a private repo will actually
serve"*). Origin: F81.

**Enforced by** `scripts/Generate-Policy.ps1:122` — the generator line, which builds the URL from
`$Config.branches.develop` and not from any commit sha:

```powershell
return 'https://github.com/{0}/blob/{1}/assets/header.svg?raw=true' -f $Config.repo, $Config.branches.develop
```

The rendered result is `.github/PULL_REQUEST_TEMPLATE.md:7`, and
`scripts/ci/Test-GeneratedMatchesConfig.ps1` fails the build if the two disagree.

**This is the one non-pinned reference in the system, and it is deliberate.** Everywhere else a
path in a pull request body must be a 40-hex permalink — `scripts/ci/Test-PrBodyLinks.ps1:227-231`
rejects any ref that is not 40 hex characters, with *"is not a 40-hex commit sha, so the link is
not pinned"*. The banner is the exception because a pull request body should
show the banner as it **is**, not as it was when the template was generated. A pinned banner in a
template is a picture of the past on every future pull request.

**Cost of retiring it** — that is, of pinning it. Every regeneration of the template becomes a
banner change, and the image in an old pull request stops matching the repository it describes.

**Reasoning at the time.** F81: the `github.com/<slug>/blob/...?raw=true` host is a private-repo
workaround, not a preference; `raw.githubusercontent.com` costs one redirect fewer and is
revisited when this repository goes public (BACKLOG **B13**). The *host* is under review. The
*branch-rather-than-sha* choice is not, and that is what this entry pins down.

## D007 — `pr-body-links` is a second step of `trailer-guard`, not a seventh check

**Decided** 2026-09-22, at commit `747735e` (*"ci: sha-pinned permalinks required for paths in PR
bodies"*). A direct consequence of **D001**.

**Enforced by** `.github/workflows/ci.yml:48-60` — the `trailer-guard` job, with
`Test-Trailers.ps1` at `:55-56` and `Test-PrBodyLinks.ps1` at `:57-60` as a second step under the
same job key. The comment stating why is at `.github/workflows/ci.yml:41-47`, and the check
restates it from its own side at `scripts/ci/Test-PrBodyLinks.ps1:14-20`.

**Cost of retiring it.** Splitting the step into its own job adds a seventh required check name,
which is the thing D001 forbids. The two cannot be retired independently: lifting D001 is what
makes this entry a free choice rather than a consequence.

**Reasoning at the time.** `scripts/ci/Test-PrBodyLinks.ps1:19-20`: `trailer-guard` is the right
host because both steps judge the **pull request object** rather than the tree, and that job
already runs only on `pull_request`. The placement is not merely the cheapest way to obey D001;
it is also where the check belongs.

One detail worth keeping: `PR_BODY` is passed to the step as an environment variable
(`.github/workflows/ci.yml:58-59`) and never interpolated into `run:`. A pull request body is
attacker-controllable text and `${{ }}` inside a shell command is an injection waiting for a
backtick.

## D008 — `scripts/verify.ps1` verifies HEAD; the cutover's `verify.ps1` stays archived and red

**Decided** 2026-09-24, on `feature/verify-green`.

**The decision.** The cutover's verifier, `docs/plans/2026-09-22-substrate-cutover/verify.ps1`,
is not edited. It is one of the files its folder's `HASHES.txt` hashes, so editing it would
falsify the archive it belongs to. It keeps reporting **15 of 19**, and those four reds are the
record of what moved after the release. `scripts/verify.ps1` is its successor for HEAD. It runs the same eight
checks, adds `scripts/Measure-Modules.ps1` as a line of its own, and treats the four reds like
this:

| Archived red | Now | Why |
|---|---|---|
| `ledger.psd1` exports five, pin expects four | **re-pinned** to the five, `ledger.psd1:9` | `Add-LedgerRecord` was exported on purpose at `33e81e9` (D002) |
| `plans.psd1` exports `Get-PlanSchemaPath` too | **re-pinned** to the two, `plans.psd1:10` | the Phase 7 rewrite exported it on purpose, and core was born with it at `46debc4` (cutover F70) |
| `ledger.psm1` is not the copied blob | **retired**, `SKIP SkipWhen:retired-by-d002` | D002: the ledger module is not byte-pinned |
| `PlanValidator.ps1` is not the copied blob | **retired**, `SKIP SkipWhen:retired-by-d008` | this entry: the Phase 7 rewrite moved these bytes on purpose (F70), and a provenance pin on a file core rewrote is a veto on the rewrite, the same argument D002 makes for the ledger |

`policy.psm1` stays byte-pinned, because it has not moved.

**Enforced by** `scripts/verify.ps1`, check 7 (`$expectedExports`) and check 8 (`$provenance`,
`RetiredBy`). A retired row prints `SKIP` with its `SkipWhen:` reason, and it prints `FAIL` if
the decision it names has no `## D00n` heading in this file. So a retirement can't outlive its
record. The status lines in `README.md` and `docs/FINDINGS.md` are written by
`scripts/Update-Status.ps1` from one run of `scripts/verify.ps1 -Json`, not typed.

**Cost of retiring it.** Pointing the README back at the archived verifier means a reader sees
four reds that nobody is going to fix. The other way to reach green is to edit the archive,
which falsifies it. **Reasoning at the time.** A measurement kept next to a claim goes stale.
A measurement that runs against HEAD has to account for every difference by a decision you can
point at. That is what this entry is for.

## D009 — `Invoke-Core.ps1` refuses a request that carries `sig`

**Decided** 2026-09-24, on `feature/json-stdio`.

**The decision.** The request schema is open: it has no `additionalProperties: false`, so a future
`sig` field can be added without a breaking schema change. But until something verifies a signature,
`scripts/Invoke-Core.ps1` answers any request that has a `sig` key with `ok: false`,
`error.code: sig-not-implemented` and exit 1. It doesn't ignore the field.

**Enforced by** `tests/InvokeCore.Tests.ps1`: *refuses a request carrying sig as
sig-not-implemented*, and *is open for a future sig field*. The second asserts both halves: the
schema admits `sig`, and the schema has no `additionalProperties` key.

**Cost of retiring it.** If an ignored `sig` is accepted, a caller who signs a request gets a
success that sounds like verification and isn't. **Reasoning at the time.** A signature that is
silently dropped is worse than no signature field at all. Signed receipts are I15. Until then,
refusing the field is the honest answer.

## D010 — `Invoke-LedgerForce -Policy` refuses as `policy-not-implemented`, and loads nothing from outside core

**Decided** 2026-09-24, on `feature/policy-refuses` (R1 PR 1).

**The decision.** `-Policy` no longer resolves `claude.build.inspector`, either as a command
already in the session or as a sibling folder at `<repo>/../claude.build.inspector`. Core's own
`modules/policy` can't judge an action (F96), so `-Policy` refuses. It raises the terminating
`LedgerPolicyNotImplemented` (category `NotImplemented`, message starting
`reason=policy-not-implemented:`) before Python is spawned and before any receipt is written.
`-Halt` and `-PolicyPath` refuse with it. A missing module is never answered with a warning
followed by a force. That was the removed path, and F98 records it.

**Enforced by** `modules/ledger/ledger.psm1:550-563`, and by the Context *-Policy refuses as
policy-not-implemented, and nothing fails open (D010)* at `modules/ledger/tests/ledger.Tests.ps1:1079`.
It asserts the ErrorId, category and reason, that no warning is written, that the refusal
comes before the Python lookup and before the append, and that `-Halt` and `-PolicyPath` refuse
too. It also asserts that an `Invoke-ClaudeInspector` already in the session isn't consulted. The
falsification at `:1154` copies the module into a throwaway repo root and forces in a child pwsh,
once with no sibling folder and once with a clean-reporting stub sibling. Both must refuse.
`LedgerPolicyNotImplemented` is in the pinned error vocabulary in the same file.
`tests/sandbox/ledger_chain.ps1` TEST 6 and TEST 9 were rewritten to the same behaviour, and its
byte pin in `modules/ledger/tests/fixtures/copied-blobs.psd1` was retired, on the D002 precedent.

**Cost of retiring it.** Bringing back a sibling lookup makes the verdict depend on what folder
happens to sit next to the checkout. With the folder absent, the caller gets a force that looks
evaluated and wasn't. **Reasoning at the time.** A switch named `-Policy` is a request for a
judgment. A refusal tells the caller there is none. A warning followed by a force tells them
nothing they will read. When `modules/policy` gains a function that takes an action and returns
a verdict, this entry is replaced by one that routes `-Policy` through it, and the refusal
becomes the path for when that function can't decide.

## D011 — `scripts/Measure-Baseline.ps1` is retired: every call refuses with `reason=retired`

**Decided** 2026-09-25, on `feature/retire-measure-baseline` (R1 PR 5).

**The decision.** The script measured the Ledger sandbox suites inside the images
`claude.pwsh.image.builder` shipped. Its three required inputs are checkouts of that repository,
of `claude.build.ledger` and of `claude.build.policy`. All three are retiring. The first is
archived at `5f71173`, and the other two were folded into this repository's `modules/`. The
baseline it produced is `docs/plans/2026-09-22-substrate-cutover/BASELINE.md`. That file is
archived and hashed, and it stays as the record. So the script is retired rather than repointed.
Pointing `-ImageBuilderPath` at a clone URL and sha would fix one of three inputs and re-measure
a layout nothing ships any more (`vendor/claude.build.ledger`, `tests/sandbox/` run in the image).

The file is kept, not deleted, because `BASELINE.md` names it as the command that produced the
baseline, and a reader should be able to open it. Its first statement after `Set-StrictMode`
raises the terminating `MeasureBaselineRetired` (category `NotEnabled`, message starting
`reason=retired:`). No git, docker or file operation runs. Its four path parameters lose
`Mandatory` so that a call with no arguments reaches the refusal instead of a prompt. None
gains a default, so F95 holds.

**Enforced by** `scripts/Measure-Baseline.ps1:115` and `tests/MeasureBaseline.Tests.ps1`. The
test runs the script in a child pwsh with no arguments, and again with the full historical
argument set. It asserts a non-zero exit and `reason=retired`, and that no file appears in the
working directory, including the `-Json` it was given. Against the script before this entry,
both tests fail: one on the missing-mandatory prompt, one on `no gitlink at vendor/claude.build.ledger`.

**Cost of retiring it.** The cutover's in-container baseline can't be re-measured from this
repository. **Reasoning at the time.** A measurement script whose inputs are archived
repositories measures the archive. The number it produced is already frozen where it belongs.
`scripts/New-BaselineMarkdown.ps1` is unchanged. It renders from the archived `baseline.json`
and needs no retired repository.

## D012 — `push-guard` judges a merge by the commits it brings in; the merge commit's own message is exempt

**Decided** 2026-09-25, on `feature/f93-push-guard-merge-button` (I15 PR 2). Origin: F93.

**The decision.** A merge commit into `develop` or `main` passes `push-guard`'s trailer gate when
every non-merge commit it brings in carries an allowed `who:` trailer. Those are the commits of
`git rev-list --no-merges <merge> --not <first parent>`. The merge commit's own message is not
judged. The merge gate (two or more parents) is unchanged. A merge that brings in no non-merge
commit fails, because there is nothing on it to judge. A one-parent commit is still judged on its
own trailer, and fails the merge gate anyway.

**Why the exemption.** `review.mode` is `human`. Jerry clicks every merge into `develop` and
`main`, and GitHub's merge button writes that message with no trailer. Judging it made the guard
red by construction on every merge this configuration allows (F93), so a red meant nothing. The
work in a merge is the commits it brings in, and `trailer-guard` already holds each of them to the
trailer on the pull request. Push-guard now checks the same thing again after the push, when it is
too late to stop it and early enough to record it.

**Enforced by** `scripts/ci/Test-PushGuard.ps1:87-104`, and by `tests/PushGuard.Tests.ps1:61`,
*the push guard judges a merge by the commits it brings in*. That test builds a synthetic repository
in `TestDrive` (the PushGuard half of BACKLOG B11). A human-authored merge with no trailer, over two
compliant commits, passes. The same merge over one commit without the trailer fails, and the
commit is named. A one-parent commit fails, and so does a merge that brings in nothing. Every case
asserts the guard's own output line, not only its exit code. The script before this entry, placed
in a synthetic repository and run on the same kind of merge, exits 1 with *no 'who:' trailer*.
This version exits 0 on it. Over core's history, the new rule passes 12 of the last 12
first-parent merges on `origin/develop` and 3 of 3 on `origin/main`.

**Cost of retiring it.** Push-guard goes back to red on every clicked merge, and a red that means
nothing is ignored. **Reasoning at the time.** The trailer is a claim about who did the work. A
merge commit made by a button does no work, and the work is in its commits.
