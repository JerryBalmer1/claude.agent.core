# RUN ORDER — substrate-finish-2026-09-22

Handoff file per surface rules 8–9. `ledger:paste` blocks are for Jerry. The `ledger:prompt`
block is for Claude Code verbatim.

Written by Claude (chat) on 2026-09-22 over the GitHub API from a read of `claude.agent.substrate`
at `develop` (`fcb03b6`) and `claude.pwsh.image.builder` PR #9 (`572a6b3`, all six checks green,
`mergeable_state: clean`). Nothing here was run on a host; every number below is quoted from a
commit body or a PR body that names the script that produced it, and step 0 re-measures the ones
this run order depends on.

**What this closes.** `README.md`'s definition of done, in its three-clause form (F55, adopted
2026-09-22). Clause 1 is measured green on PR #9. Clause 2 is measured red on PR #9 for exactly
one reason, F10. Clause 3 is the row-by-row table in `RELEASE-NOTES.md`, which needs the
in-container numbers filled in. Then `review.mode` flips, the two absorbed source repos retire,
and Phase 7 repoints `modules/plans` at the validator its only consumer actually carries.

---

## WHERE

**THIS takes place HERE:** `C:\__Code\____Claude.Build\claude.agent.substrate` (Phase 6.4, 6.5,
Phase 7) and `C:\__Code\____Claude.Build\claude.pwsh.image.builder` (Phase 6.2, 6.3). The two
legacy repos `claude.build.ledger` and `claude.build.policy` are **written once each** in Phase
6.5 — one file at the root — and never otherwise.

```powershell ledger:paste
#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-Location 'C:\__Code\____Claude.Build'; "PWD: $PWD"
foreach ($r in 'claude.agent.substrate','claude.pwsh.image.builder','claude.build.ledger','claude.build.policy') {
  "--- $r"; git -C $r rev-parse --abbrev-ref HEAD; git -C $r rev-parse --short HEAD; git -C $r status --short
}
gh pr view 9 --repo JerryBalmer1/claude.pwsh.image.builder --json state,mergedAt,mergeCommit --jq '"PR9 \(.state) merged=\(.mergedAt) \(.mergeCommit.oid // "-")"'
"Expect: all four clean; PR9 MERGED with a merge commit. If PR9 is OPEN, stop: it is Jerry's click, not the agent's."
```

---

## WHAT

| Step | Repo | Branch | Lands |
|---|---|---|---|
| 0 | substrate | (none) | `Measure-Modules.ps1` re-run; README status table corrected to the measurement |
| 6.2 | image.builder | (on merged `develop`) | both images rebuilt from the merge commit of PR #9; image ids recorded |
| 6.3 | image.builder | `feature/f10-python-shim` | F10 decided **image-side**: developer image gets `python` resolving to `python3`; leash image records that `python.Tests.ps1` cannot run there and why. Substrate suite in-container: developer expected 167/167 (PR #9 measured that with a shim), leash expected 156/167 with the 11 reds named |
| 6.4 | substrate | `feature/review-human` | `config/repo.json` `review.mode` → `"human"`, regenerate, PR to develop (last automerge), then develop → main (waits on Jerry) |
| 6.5 | substrate + 2 legacy roots | `feature/retire-ledger-policy` | `migration.json` retire rows flipped with evidence; `MIGRATION-SOURCE.md` dropped into `claude.build.ledger` and `claude.build.policy`; both sources → `retired`, `do-not-load` |
| 6.6 | substrate | same branch as 6.5 | F44 TEST 10 closed one of two ways: a cross-platform lying-snake stub, or a formal acceptance in FINDINGS |
| 7 | substrate | `feature/plans-schema-validator` | `modules/plans` pin bumped to image.builder's `ff7b2baf`; `Get-PlanSchemaPath` exported; `-SchemaPath` un-inerted; `examples/parse-here.ps1` (policy, F24) fixed or removed |

**Governing rule** unchanged: *receipts are libraries, judgments are containers.*

**Out of scope — findings only:**
- Editing `modules/ledger/ledger.psm1`, `modules/policy/policy.psm1`, or any `landed` blob. F10 is
  fixed in the image, not in the library; the provenance claim is worth more than a default.
- Anything under `.agents/`. The arena traffic is not this run order's.
- `claude.build.fuzzer`, `claude.build.inspector`, and `claude.agent.tools`. Their migration
  block waits for the tools repo to exist.
- Renaming image.builder to `claude.agent.images`. That is its own run order.
- Squash, rebase, force-push, amend. Ever.

**Standing law:** `AGENTS.md`. PowerShell 7.4+ only, `who: claude` on every commit, merge commits
only, park after every step, measurement beats expectation, numbers come from scripts.

---

## HOW

```text ledger:prompt
You are Claude Code in C:\__Code\____Claude.Build\claude.agent.substrate.
Read AGENTS.md, then docs/migration/MIGRATION.md, then this file, then
docs/plans/2026-09-22-substrate-cutover/FINDINGS.md F10, F27, F28, F44,
F51, F53, F54, F55, F59. Do not start until image.builder PR #9 is
MERGED (gh pr view 9 --repo JerryBalmer1/claude.pwsh.image.builder
--json state). If it is OPEN, print that as your first line and stop.

Rules that override anything you think is a better idea: AGENTS.md.
PowerShell 7.4+ only. No bash, no sh, no heredocs. who: claude trailer,
last line. Merge commits only. One step per PR; do not start step N+1
until step N's PR is MERGED. Park after every step. Every number you
write must come from a script in the repo; if a script does not exist
for it, write the script first.

=====================================================================
STEP 0 — RE-MEASURE (substrate, no branch yet)
=====================================================================
   git switch develop; git pull --ff-only
   pwsh -NoProfile -File scripts/ci/Invoke-Tests.ps1
   pwsh -NoProfile -File scripts/Measure-Modules.ps1
   The chat author expects ledger 84, policy 10, plans 11, repo 74,
   total 179 (167 + the 12 in tests/Migration.Tests.ps1 measured by
   1f5c5f3). Measurement wins. Whatever the script prints is what
   README.md's status table says; if the table is wrong, fix it on the
   6.4 branch below and say in the commit body which number moved.
   pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/verify.ps1
   Record which of its 19 lines are red on today's develop (check 6 is
   expected red until the table is corrected). Do not edit verify.ps1.

=====================================================================
STEP 6.2 — REBUILD FROM THE MERGE (image.builder, read-only)
=====================================================================
   Set-Location ..\claude.pwsh.image.builder; git switch develop;
   git pull --ff-only; git submodule update --init
   git submodule status   -> expect 3933dccf... vendor/claude.agent.substrate (v0.1.0)
   Invoke-Build Bootstrap, Build.Image
   docker image inspect for both images -> record ids.
   Run substrate's suite in BOTH containers exactly as PR #9's body did
   (its "substrate's own suite, in developer container" rows). Record
   total/passed/failed per container and the name of every failing It.
   If any failure is outside python.Tests.ps1, STOP and write the
   finding: that is a regression PR #9 did not have.

=====================================================================
STEP 6.3 — F10, DECIDED IMAGE-SIDE   branch: feature/f10-python-shim
=====================================================================
   In image.builder, per ITS flow (feature/* -> develop, automerge).
   a. images/developer/Dockerfile: make `python` resolve to python3.
      Prefer the distro's python-is-python3 package over a hand symlink;
      if the base image has no such package, a symlink in /usr/local/bin
      with a comment naming F10. One line either way, plus the comment.
   b. Leash image: NO python is added. Record in image.builder's own
      FINDINGS (or docs/) that substrate's python.Tests.ps1 is expected
      red there by design -- the leash has no snake -- and that the 11
      reds are all in that one file. The non-python count (PR #9: 149)
      is the leash number.
   c. Rebuild; rerun 6.2's measurement. Expected: developer 167/167,
      leash 156/167 with every red in python.Tests.ps1. Measurement wins.
   d. Run image.builder's own Test.Unit and Test.InContainer; both must be
      at or above PR #9's counts (175/1 host, 154/1/21 in-container). The
      one pre-existing red PR #9 names (trailer guard over the PR range)
      is allowed to stay red only if it is the same test for the same
      reason; anything else is a finding.
   e. PR into develop. Automerge. Record PR number + merge commit.
   f. Copy the per-container table into substrate's
      docs/plans/2026-09-22-substrate-cutover/RELEASE-NOTES.md under a
      new heading "In-container, measured after PR #9 + F10 shim", with
      the image ids and the exact command. That edit rides on the 6.4
      branch below, not on a separate PR.

=====================================================================
STEP 6.4 — REVIEW MODE -> HUMAN          branch: feature/review-human
=====================================================================
   Back in substrate. git switch develop; git pull --ff-only;
   git switch -c feature/review-human
   a. config/repo.json: review.mode "auto" -> "human". Update the note.
   b. pwsh -NoProfile -File scripts/Generate-Policy.ps1 ; commit the
      regenerated docs/POLICY.md and .github/PULL_REQUEST_TEMPLATE.md.
   c. README.md status table: the numbers from step 0. RELEASE-NOTES.md:
      the table from 6.3f. Nothing else in README.md.
   d. verify.ps1 must now be 19/19 (check 6 was the only expected red).
   e. Forensic seq N+1: subject substrate-definition-of-done-measured,
      evidence = image.builder PR #9 merge commit + 6.3 PR merge commit
      + both image ids + the three per-container totals. -Verify. -Anchor
      printed in the commit body.
   f. PR into develop. This is the LAST automerged PR: the base still
      says auto. Wait for it. Then gh pr create --base main --head develop
      --fill. That one waits for Jerry. First line of your message:
      "6.4: develop->main PR #<n> waiting on Jerry".
   Park. Do not proceed to 6.5 until main has it.

=====================================================================
STEP 6.5 — RETIRE LEDGER AND POLICY   branch: feature/retire-ledger-policy
=====================================================================
   a. docs/migration/migration.json, claude.build.ledger block:
        6.1 row -> met, evidence: image.builder PR #9 merge commit
        6.3 row -> met, evidence: the 6.3 table (per-suite, not a total;
                   name the four removals; name the python.Tests reds in
                   leash as expected-by-design)
      claude.pwsh.image.builder block: rows 6.1 and 6.3 the same way.
      Row "Plan.Check repointed" stays UNMET -- that is Phase 7's.
   b. claude.build.policy row "no other repo imports ... by sibling
      path": write scripts/Test-SiblingImports.ps1 that greps every
      sibling under C:\__Code\____Claude.Build for '../claude.build.policy'
      and '..\claude.build.policy' in tracked files (git ls-files, not
      the working tree) and prints hits. Exit 2 if a sibling is missing.
      Flip the row only on zero hits, evidence = the script name and
      the sibling shas it read. Same script, same run, for
      '../claude.build.ledger' -- record the count even though no ledger
      row asks for it; a hit is a finding.
   c. docs/migration/SOURCE-STUB.md -> claude.build.ledger/MIGRATION-SOURCE.md
      and claude.build.policy/MIGRATION-SOURCE.md, fields filled from the
      JSON. ONE commit in each legacy repo, on its default branch, per
      ITS flow if it has one, who: claude. Record both shas. These are
      the only writes to those repos this run order allows.
   d. Then and only then: status -> retired, context_policy -> do-not-load
      for claude.build.ledger and claude.build.policy. Regenerate
      MIGRATION.md. Invoke-Pester tests/Migration.Tests.ps1 -- the suite
      refuses the retire if any retire_when is unmet, and the F44 row
      (6.6) is still unmet at this point, so DO 6.6 ON THIS BRANCH FIRST
      and retire in the last commit.

=====================================================================
STEP 6.6 — F44 TEST 10, CLOSED ONE OF TWO WAYS   (same branch as 6.5)
=====================================================================
   Option A, preferred: a cross-platform lying snake.
     modules/ledger/tests/fixtures/lying-snake/  containing
       lie.cmd      (Windows: @echo off / type <payload>)   -- the original
       lie.ps1      (Linux: first line #!/usr/bin/env pwsh, then
                     Get-Content <payload>; chmod +x recorded via
                     git update-index --chmod=+x)
     One It in ledger.Tests.ps1: Invoke-LedgerForce -PythonPath <stub>
     where the stub is chosen on $IsWindows, the payload is a result
     event whose mode does not match the run requested, and the
     FullyQualifiedErrorId is LedgerResultMismatch*. No .sh. No .py.
     Prove it on the runner (push, read the pester log) before calling
     it green -- F26 is the reason.
   Option B, if A cannot be made to fire on ubuntu-latest within two
     pushes: append F60 to FINDINGS.md formally accepting the hole,
     with the two pushes' run ids as the evidence of the attempt, and
     flip the row with F60 as evidence.
   Either way: the row flips, and RELEASE-NOTES.md known-gap 1 is
   edited to say which way.

   PR into develop. review.mode is human now: first line of your message
   "6.5/6.6: PR #<n> green, waiting on Jerry". Park.

=====================================================================
STEP 7 — PLANS AT THE CONSUMER'S VALIDATOR   branch: feature/plans-schema-validator
=====================================================================
   This step edits modules/plans, which the cutover run order named, so
   the wall permits it. It does NOT edit modules/ledger or modules/policy
   except the one file named in 7e.
   a. Measure first: in image.builder on develop (post PR #9),
      git rev-parse HEAD:src/PlanValidator.ps1 -> expect ff7b2baf...
      Record the full sha. If it is not ff7b2baf, STOP and write the
      finding: F59's prediction was wrong and the pin target moved.
   b. Copy commit, unmodified: src/PlanValidator.ps1 -> modules/plans/
      PlanValidator.ps1 as bytes from that blob. Commit alone:
      "scaffold: copy plan validator from image.builder@<sha>, unmodified".
   c. Adapt commit: plans.psd1 FunctionsToExport adds Get-PlanSchemaPath;
      plans.psm1 wrapper passes -SchemaPath through for real; remove the
      F27 inertness Its (checks g and i) and replace with: -SchemaPath
      is READ (a plan the schema rejects fails; a missing schema path
      throws), and the step-shape rule is GONE (F4 inverted -- a step
      with no action passes if the schema allows it; measure, do not
      assume). Record the Pester delta.
   d. migration.json image.builder block: pin -> the new sha, the
      PlanValidator item's blob -> ff7b2baf..., note names F27/F28/F59
      as resolved. Symbols: rerun scripts/Measure-MigrationSymbols.ps1
      -- exported_in_source now has two names; substrate must match.
      Regenerate MIGRATION.md.
   e. modules/policy/examples/parse-here.ps1: apply F24's one-line fix
      (Join-Path $PSScriptRoot '..' 'policy.psd1' -- note the Phase 5
      rename, F47) and move its migration row from landed to adapted
      with the new tree blob; or delete it and move the row to
      not_migrated with reason "broken example, F24". Either is fine;
      say which.
   f. FINDINGS.md: F60 (or F61) recording what the rewrite changed in
      behaviour, with the falsification table.
   g. PR into develop. Human gate. First line: "Phase 7: PR #<n> green,
      waiting on Jerry; Pester <before> -> <after>". Park.

   NOT in this step: repointing image.builder's Plan.Check at the
   submodule. That is image.builder's, after substrate tags v0.2.0.

PARK after every step:
   git switch develop; git pull --ff-only; git branch -vv; git status
   gh pr list --state all --limit 5
   Final message per step: FIRST line = step, PR number, merged or
   waiting and why. LAST block = the git state above, verbatim.
```

---

## VERIFY (Fable / Grok)

```powershell ledger:paste
#Requires -Version 7.4
Set-Location 'C:\__Code\____Claude.Build\claude.agent.substrate'; "PWD: $PWD"
git fetch origin --prune --tags; git switch develop; git pull --ff-only
(Get-Content config/repo.json -Raw | ConvertFrom-Json).review.mode
& ./scripts/ci/Invoke-Tests.ps1; "pester exit: $LASTEXITCODE"
& ./scripts/Measure-Modules.ps1
& ./docs/plans/2026-09-22-substrate-cutover/verify.ps1; "verify exit: $LASTEXITCODE"
& ./scripts/New-MigrationReport.ps1 -Check; "migration check exit: $LASTEXITCODE"
(Get-Content docs/migration/migration.json -Raw | ConvertFrom-Json -Depth 20).sources | Select-Object repo,status,context_policy,@{n='met';e={($_.retire_when | Where-Object met).Count}},@{n='of';e={$_.retire_when.Count}} | Format-Table
git -C ../claude.pwsh.image.builder submodule status
Test-Path ../claude.build.ledger/MIGRATION-SOURCE.md; Test-Path ../claude.build.policy/MIGRATION-SOURCE.md
pwsh -NoProfile -File scripts/forensic.ps1 -Verify; pwsh -NoProfile -File scripts/forensic.ps1 -Anchor
```

Checks that don't trust the report:

1. `review.mode` is `human` on `develop` **and** on `main`, and `docs/POLICY.md` says so.
2. The README status table equals `Measure-Modules.ps1`'s live output — `verify.ps1` check 6 green.
3. image.builder `develop` has `vendor/claude.agent.substrate @ 3933dcc`, and its developer
   Dockerfile has exactly one line that makes `python` resolve, with F10 in the comment.
4. `RELEASE-NOTES.md`'s in-container table names both image ids and three per-container totals,
   and every leash red is in `python.Tests.ps1`.
5. `claude.build.ledger` and `claude.build.policy` each have exactly **one** commit after their
   pins (`d57938d`, `3be10c4`) and it adds only `MIGRATION-SOURCE.md`.
6. Both sources are `retired` / `do-not-load` and `tests/Migration.Tests.ps1` is green — the
   suite is what refused it until every row was met.
7. F44's row cites either a test that raises `LedgerResultMismatch` on the runner (read the CI
   log) or F60 with two run ids.
8. Phase 7: first commit touching `modules/plans/PlanValidator.ps1` is a byte-identical copy of
   `ff7b2baf…`; `Get-PlanSchemaPath` is exported; a schema-rejected plan now fails.
9. No commit in any of the above is a squash or a rebase; every one carries `who:`.
10. The forensic chain verifies and has one new record per step that says it appends one.

Grok signs off on 1–10. Fable audits the chain from seq 9 through the last record this run
appends.
