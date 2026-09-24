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
