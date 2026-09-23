# PRE-PUBLIC — claude.agent.core

An **open checklist** of what must be true before this repository is published. Not a plan:
nothing here is scheduled, owned, or sequenced, and several lines are conditions somebody has to
decide rather than work somebody has to do.

Each line states the condition and, where it is knowable, **where the current state was
measured**. Where an item is already a `docs/BACKLOG.md` row it cites the B-number instead of
restating it, so there is one owner-facing list and not two.

Measured 2026-09-23 at `1990d90` unless a line says otherwise.

---

## The name

- [ ] **The public name must not contain "claude".** No tracked *path* contains the string today
      — 0 of 108 — but **59 of 108 tracked files contain it in their contents**, including
      `config/repo.json:3` (the repository slug), `config/repo.json:62` (the banner title),
      `README.md`, `AGENTS.md`, every workflow, and the generated `docs/POLICY.md` and
      `.github/PULL_REQUEST_TEMPLATE.md`. A rename is not a `git mv`; it is a regeneration plus a
      sweep of prose, and the generated files must be regenerated rather than edited or
      `generated-match-config` goes red.

      Measured:

      ```powershell
      git ls-files | Measure-Object                 # 108
      git ls-files | Where-Object { $_ -match 'claude' } | Measure-Object   # 0
      git grep -li 'claude' -- . | Measure-Object   # 59
      ```

## Licensing

- [ ] **The licensing boundary is unresolved, and no license file exists.** `git ls-files` matches
      no `LICENSE`, `LICENCE` or `COPYING` at any path. The shape under discussion is an MIT
      commodity layer with a closed verification engine, and **which files fall on which side has
      not been decided.** Publishing without deciding publishes everything under whatever the
      absence of a license means, which is "all rights reserved" and not what either half of that
      split intends.

## Evidence that has no independent witness

- [ ] **The `claude.agent.images` anchor has no home outside any repository.** The value
      `915be889a0cc5fbf3d5af557b89b24f885afe78addf66ef07f1a893ac8d8715a` is the `self` of seq 1 —
      the only record in that chain — and it is stored at `.continuity/forensic.jsonl` **inside
      `claude.agent.images` itself**, measured at that repository's HEAD `f1aeb60`. An anchor kept
      only in the repository it attests is witnessed by the thing it exists to witness.

      F82 measured this and BACKLOG **B14** holds the judgement it feeds — whether a
      `claude.agent.meta` repository gets built, or whether one file outside every repository does
      the same job for nothing. Until either exists, the images chain has **no independent
      witness**, and that is a claim this repository should not make in public with a straight
      face.

## Verification that is not wired to anything

- [ ] **`docs/plans/2026-09-22-substrate-cutover/verify.ps1` is not a required check, and it
      measures a subset of the claims.** `config/repo.json:21-28` lists six required checks and
      none of them is this script; nothing in CI runs it. Its own header
      (`docs/plans/2026-09-22-substrate-cutover/verify.ps1:7-8`) states its scope: *"Eight checks,
      printed as 19 PASS/FAIL lines."* Eight subjects is not the repository.

      It is also **archived evidence and is not rewritten** to match a later tree, so it will go on
      reporting reds that are correct about the past and wrong about the present. That is the right
      behaviour for a record and the wrong behaviour for a gate, and publishing it as though it
      were a gate would be the misreading. If a live equivalent is wanted, it is a new script.

## Documentation that has drifted

- [ ] **The ledger module's docs still describe a four-name export list.** Measured against
      `modules/ledger/ledger.psd1`, which exports **five**: `Invoke-LedgerForce`,
      `Get-LedgerStatus`, `Get-LedgerVerify`, `Get-LedgerEntry`, `Add-LedgerRecord`.

      | File | State |
      |---|---|
      | `modules/ledger/README.md:10-17` | **corrected at `71463a0`** — five rows, and the prose now names the `ledger.psd1` and `ledger.psm1` lines it was measured against |
      | `modules/ledger/docs/commands.md:3-8` | **stale, twice** — *"Four exported functions and one alias"* plus the literal four-name `FunctionsToExport` line, and it cites `../src/ledger/Ledger.psd1`, a path that does not exist in this layout |
      | `modules/ledger/docs/theory-of-operation.md` | **not stale on this axis** — it states no export list at all, and names `Add-LedgerRecord` at `:123` |
      | `docs/theory-of-operation.md` | **does not exist.** The seed list named it; there is no such file at the repository root |

      The two are not the same job. `modules/ledger/docs/commands.md` **is a pinned blob**
      (`modules/ledger/tests/fixtures/copied-blobs.psd1:37`), so correcting it is the same shape of
      problem as BACKLOG **B10** — the edit and the pin move together or neither moves.
      `modules/ledger/README.md` is **not** pinned; no row in that file names it, so it can simply
      be corrected.

      **Half of this is done, and the half that is not got measured.**
      `modules/ledger/README.md` was corrected at `71463a0`. That commit also found two false
      claims in the same file that this line did not measure, because this line measures one axis
      and a file has more than one: a byte-identity claim about `ledger.psm1` that
      `git hash-object` refutes, and a test F76 deleted. **F86.**

      `modules/ledger/docs/commands.md` is untouched. Retiring its pin **alone** turns
      `modules/ledger/tests/ledger.Tests.ps1:348` red — measured, *"Expected 10, because the table
      must not be empty, but got 9"*, suite `206` to `205 passed / 1 failed`. So the move is three
      files, not two, and the third is a `.ps1`. BACKLOG **B16** holds it; **F88** holds the
      measurement.

## Seed items that were not found where they were claimed

Recorded rather than dropped, because "we looked and it is not there" is a measurement and
silence is not.

- **`.ALLAGENTS.md` — not found.** The string appears in **zero** tracked files
  (`git grep -c ALLAGENTS` → no matches). Neither `AGENTS.md` nor anything else instructs reading
  it first.
- **`FLOW.md` — does not exist**, at the root or under `docs/`.
- **`tests/Repo.Tests.ps1` and `config/contracts.json` — neither exists**, so the old-lineage
  hashes said to be pinned in them are pinned nowhere.

What **is** there, and is a different problem, is old-lineage *naming* rather than old-lineage
pins:

- [x] **`AGENTS.md:3` opened "Law for any agent working in `claude.agent.substrate`"** — the
      governing file of this repository named a different repository in its first sentence.
      **Resolved at `cbb8dbf`.** It now names `claude.agent.core`, which is the slug at
      `config/repo.json:3` and the one the `origin` remote resolves to.
      `git grep -n substrate -- AGENTS.md` went `2` to `1`; the remaining match is `AGENTS.md:108`,
      which cites `docs/plans/2026-09-22-substrate-cutover/RUN-ORDER.md` — a directory that exists,
      so the string is a live path and not a naming defect.
- [ ] **`tests/AutoMerge.Tests.ps1:81` and `:96`** pass `JerryBalmer1/claude.agent.substrate` as
      the repository argument. The tests pass; the string is a fixture, not a pin, and it is the
      wrong repository.
- [ ] **Prose and comments carrying the old name**: `tests/Skeleton.Tests.ps1:87`, `:117`, `:119`;
      `schemas/repo.schema.json:101`; `scripts/ci/Test-Runtimes.ps1:7-8`, `:33`, `:62`;
      `scripts/forensic.ps1:10`; `scripts/Generate-Policy.ps1:486` (which renders into the shipped
      PR template as *"substrate is never a container"*); `scripts/Invoke-AutoMerge.ps1:50`.

      **`AGENTS.md:117` belongs on this list and was missed.** Added 2026-09-23 while resolving
      `AGENTS.md:3`: the wall reads *"Substrate is never a container"*, which
      `git grep -in substrate` finds and the case-sensitive `git grep -n substrate` does not. It
      is the same sentence `scripts/Generate-Policy.ps1:486` renders into
      `.github/PULL_REQUEST_TEMPLATE.md:66`, so the law text and the generated template text move
      together or they disagree — which is what puts `AGENTS.md:117` in this bullet rather than in
      the resolved one above.

      `docs/plans/**` also carries it throughout and is **excluded from this line on purpose**:
      F74 and `AGENTS.md:95-99` freeze the archived record, and a rewritten measurement is a
      falsified one.

## External sources

- [ ] **Analysis sources 1–25 — verify every URL before public.** `docs/analysis/` cites 25
      external sources. 1–16 are inline and unnumbered across `docs/analysis/landscape.md`,
      `docs/analysis/gaps.md` and `docs/analysis/refusal.md`; 17–25 are numbered in
      `docs/analysis/suppressed-outputs.md`, which assigns the numbers rather than continuing a
      register that exists on disk. **None has been fetched from this tree.** A citation that 404s
      in public is worse than no citation, because it reads as a fabricated one — and the set's
      whole convention is that an external claim carries its source in the sentence that makes it,
      which puts the weight on the URL being real.

## Known and deferred

- [ ] **Banner URL host.** The `github.com/.../blob/...?raw=true` form is required while the
      repository is private; it is revisited on the day that changes. BACKLOG **B13**, F81. The
      *branch-rather-than-sha* half of that URL is deliberate and is not up for revision —
      `docs/DECISIONS.md` **D006**.

## Platform portability

- [ ] **Name the portability boundary before v1.** Everything enforcing today is GitHub-shaped:
      the `gh` CLI, required check names, a PR template file, branch flow expressed as pull request
      head/base pairs. Azure DevOps names these differently — **branch policies** rather than
      required checks, no template file at all, and no generated-workflow artifact for
      `generated-match-config` to compare against.

      **Not solving this now.** What is owed before v1 is the boundary itself: what is
      platform-neutral (the ledger, the chain, the gate logic, the preflight logic), what is
      adapter code, and where the seam sits. **v1 cannot claim generality while one platform is
      proven**, and stating the boundary is cheaper and more honest than either claiming generality
      or silently implying it.

## Open questions with no owner

Not checklist items — nobody has to answer these before publication. They are here so that
publication does not imply they were settled.

- **What the evidence a gate leaves behind costs.** `docs/IDEAS.md` (*cost of proof*), narrowed
  after the literature was read: gate **latency** is published — seven sources, listed in
  [`analysis/suppressed-outputs.md`](analysis/suppressed-outputs.md) → *"Correction — cost of proof
  is partly published"*. What is **unpublished** is receipt size per action and verify time as a
  function of chain length. Overhead is a security property because an expensive gate gets switched
  off. **F91** is one point on the second half and **B17** is the harness that would give it a
  slope; the per-call latency question is not ours.
- **Whether the adversarial catalogue becomes a conformance suite.** `docs/IDEAS.md` ends the
  catalogue with the condition — *"if the receipt format and the policy schema are ever published
  as a spec"* — and neither has been.
