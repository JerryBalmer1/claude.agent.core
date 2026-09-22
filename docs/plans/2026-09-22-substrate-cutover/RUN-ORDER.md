# RUN ORDER — substrate-cutover-2026-09-22

Handoff file per surface rules 8–9. `ledger:paste` blocks are for Jerry. The `ledger:prompt` block is for Claude Code verbatim.

This run order **authorises module code** in `claude.agent.substrate`. Until it merged, AGENTS.md's wall ("no module code without a run order that says to") stood. It now says to — in the order, and only the order, below.

Written by Claude (chat) on 2026-09-21 from a read of the four source repositories over the GitHub API. Decisions taken by Jerry the same day: **Python is allowed in substrate for now** (Ledger's compute engine stays Python); staged cutover, baseline first.

**Already done before this order — do not redo.** The Phase 0 closeout (`docs/plans/2026-09-21-closeout/`, PRs #8–#11) moved the review-mode read to the **base** branch (`scripts/AutoMerge.Lib.ps1`), made the trailer exemption a data file (`config/trailer-grandfather.txt`), added the push tripwire (`push-guard`, deliberately not a required check), and fixed automerge's 404 stand-down. Pester stood at **47** at the end of it. Phase 1 below records that number; it does not re-earn it.

---

## WHERE

**THIS takes place HERE:** `C:\__Code\____Claude.Build\claude.agent.substrate`

Source repositories are **read**, never written, until Phase 6:

| Repo | Local path | What substrate takes from it |
|---|---|---|
| `claude.build.ledger` | `C:\__Code\____Claude.Build\claude.build.ledger` | `src/ledger/` (Ledger.psd1, Ledger.psm1, `python/`), `tests/sandbox/*.ps1`, `docs/` |
| `claude.build.policy` | `C:\__Code\____Claude.Build\claude.build.policy` | `src/claude.build.policy/`, `tests/sandbox/policy_suite.ps1`, `docs/do-not.md`, `examples/parse-here.ps1` |
| `claude.pwsh.image.builder` | `C:\__Code\____Claude.Build\claude.pwsh.image.builder` | `src/PlanValidator.ps1`, `schemas/plan.schema.json`, `plans/README.md`; and it is the **consumer** whose in-container suite defines done. Note: it has ported substrate's automerge pattern since the skeleton run — measure its current branch flow in 1.0, do not assume it. |

```powershell ledger:paste
#Requires -Version 7.4
$ErrorActionPreference = 'Stop'
Set-Location 'C:\__Code\____Claude.Build'; "PWD: $PWD"
foreach ($r in 'claude.agent.substrate','claude.build.ledger','claude.build.policy','claude.pwsh.image.builder') {
  "--- $r"; git -C $r rev-parse --abbrev-ref HEAD; git -C $r rev-parse HEAD; git -C $r status --short
}
Set-Location 'claude.agent.substrate'; git switch develop; git pull --ff-only; git log --oneline -3
gh auth status
"Expect: all four clean; substrate on develop, fast-forwarded; ledger/policy/image.builder on their default branches"
```

---

## WHAT

The README's definition of done, verbatim:

> substrate is done when `claude.pwsh.image.builder`'s submodule points here and its in-container suite is green at the same pass count it had at cutover

That sentence has a hole: **the cutover pass count has never been recorded.** image.builder's own `tests/` holds one file, `plan.failfirst.ps1`, which is designed to fail red. The suites that actually run inside the container come from the vendored `claude.build.ledger` (`tests/sandbox/`: `ledger_chain`, `forensic_chain`, `hook_pre_tool`, `continuity`, `fuzzer_import`, `fail_path`, `no_sabotage`). Phase 1 exists to close that hole before anything is moved.

Six phases. **Each phase is one feature branch and one PR into `develop`.** Do not start a phase until the previous phase's PR has merged. Each phase ends parked.

| Phase | Branch | Lands |
|---|---|---|
| 1 | `feature/cutover-baseline` | `BASELINE.md` — per-suite pass counts measured in-container, with source commit hashes. `runtimes` declared in config and CI-checked. Starting Pester total recorded. |
| 2 | `feature/module-policy` | `modules/policy/` — `claude.build.policy` source, unchanged in behaviour, with its 10-check suite ported to Pester and wired into the `pester` CI check. |
| 3 | `feature/module-plans` | `modules/plans/` — `PlanValidator.ps1` + `plan.schema.json` wrapped as a module with a manifest and a Pester suite. |
| 4 | `feature/module-ledger` | `modules/ledger/` — `src/ledger/` from `claude.build.ledger` including `python/`; the suites that belong to a *library* ported to Pester; the ones that belong to a container or a sibling recorded as **not migrated, by design**. |
| 5 | `feature/release-0.1.0` | `develop → main` PR, then tag `v0.1.0` on the merge commit. Release notes = per-suite pass table from Phase 1 vs. substrate's own table. |
| 6 | (in image.builder) `feature/submodule-substrate` | `.gitmodules` repointed to substrate at `v0.1.0`; in-container suite rerun; per-suite table compared to `BASELINE.md`. Then in substrate: `review.mode` → `human`. |

**Governing rule** (from the consolidation decision): *receipts are libraries, judgments are containers.* Anything that decides, halts, hooks a tool call, or imports a sibling by path is not substrate's. It is recorded as a finding with its destination (`claude.agent.tools` or `claude.agent.images`) and left where it is.

**Out of scope — findings only:**
- Writing to `claude.build.ledger`, `claude.build.policy`, `claude.build.fuzzer`, `claude.build.inspector` (Phases 1–5). image.builder is written **only in Phase 6, only `.gitmodules` and the submodule pointer**.
- Rewriting the Python engine in PowerShell. Python stays.
- Any Dockerfile, entrypoint, hook, or image content in substrate.
- `claude.build.fuzzer`'s corpus, `claude.build.inspector`'s observer, `hooks/`, `Skills.Audit`, `Invoke-Build` tasks. Those are `claude.agent.tools` / `claude.agent.images` work.
- Re-doing anything the Phase 0 closeout already landed (base-branch review read, grandfather file, push tripwire).
- Signing, `.gitallowedsigners`, `LEDGER_PRINCIPAL`.
- Retrying branch protection.
- Squash or rebase merges anywhere, ever.

**Standing law:** PowerShell 7.4+ for every repo-owned script. Python 3.10+ is permitted **only** under `modules/ledger/python/`, and is declared in `config/repo.json` (Phase 1) so the permission is written down once. No bash, no heredocs. `$ErrorActionPreference = 'Stop'`. Every commit carries `who: claude`. Where this order states an expected value and your measurement disagrees, **your measurement wins** and the discrepancy goes to FINDINGS.

---

## HOW

```text ledger:prompt
You are Claude Code working in C:\__Code\____Claude.Build\claude.agent.substrate.
Read AGENTS.md, then docs/plans/2026-09-22-substrate-cutover/RUN-ORDER.md,
then skim docs/plans/2026-09-21-closeout/FINDINGS.md so you know what is
already done. The WHAT table is the scope; the Out-of-scope list is a
wall. This run order authorises module code in modules/ — nothing else does.

Rules that override anything you think is a better idea:
- PowerShell 7.4+ only for every .ps1/.psm1. No bash, no sh, no heredocs.
  Python 3.10+ only under modules/ledger/python/, only in Phase 4.
- Every commit: conventional subject, trailer `who: claude` as the last line.
- Merge commits only. Never --squash, --rebase, force-push, or amend pushed.
- One phase per PR. Do not start phase N+1 until phase N's PR is MERGED
  (gh pr view <n> --json state,mergedAt). If automerge does not merge
  within 10 minutes, read the run log, fix on the same branch, push,
  repeat. Never merge by hand.
- Copy source files BYTE-IDENTICAL from the sibling repo first, commit that
  copy alone ("scaffold: copy <x> from <repo>@<sha>, unmodified"), and only
  then edit in a second commit. A reviewer must be able to diff the second
  commit against the sibling and see exactly what changed in transit.
- Every number in BASELINE.md, REPORT.md and FINDINGS.md must be
  reproducible by a script in the repo. No measured number, no line.
- Measurement beats expectation. If a suite listed below does not exist,
  does not run, or gives a different count, write down what you saw.
- Park at the end of every phase: develop, clean, ff, state printed last.

=====================================================================
PHASE 1 — BASELINE + RUNTIME DECLARATION  branch: feature/cutover-baseline
=====================================================================

1.0 PREFLIGHT (no commit)
   Start-Transcript docs/plans/2026-09-22-substrate-cutover/TRANSCRIPT.log
   Record HEAD of all four repos (git -C <path> rev-parse HEAD) — these go
   into BASELINE.md as the source pins. Record `docker version` and
   `pwsh --version`. Run scripts/ci/Invoke-Tests.ps1 on develop and record
   the Pester total (expect 47; measurement wins). Record image.builder's
   default branch and whether it has config/repo.json — it ported the
   automerge pattern, so Phase 6 must go through whatever flow it has now.
   If docker is not available, STOP: Phase 1 cannot be measured without
   the container, and a baseline that is not measured in-container is not
   the baseline the definition of done names. Write the finding and park.

1.1 MEASURE THE CONSUMER, IN-CONTAINER
   In C:\__Code\____Claude.Build\claude.pwsh.image.builder (READ ONLY —
   do not commit there):
   a. `git submodule status` — record the pinned ledger sha. Record
      whether it equals claude.build.ledger's current HEAD; if not, the
      pin is the baseline, not HEAD, and say so.
   b. Build the image the way its README says (Invoke-Build Images.Build
      or docker build). Record the image id.
   c. Inside the container, run every suite under
      vendor/claude.build.ledger/tests/sandbox/*.ps1 with
      `pwsh -NoProfile -File <suite>` and capture, per suite: exit code,
      the suite's own pass/fail line(s), and total checks. Also run
      tests/plan.failfirst.ps1 and record that it fails red (that is its
      contract; a green there is a finding).
   d. Write scripts/Measure-Baseline.ps1 in substrate: takes -ImageBuilderPath
      and -Image, runs the same loop, emits one JSON object per suite
      {name, exit, passed, failed, total, seconds}. BASELINE.md is
      generated from that JSON, not typed. Suites that cannot run
      in-container (e.g. fuzzer_import needs the fuzzer sibling mounted)
      are recorded as SKIPPED with the reason, not omitted.
   e. BASELINE.md sections: source pins (four shas + submodule pin),
      image id, per-suite table, SKIPPED table, substrate's own starting
      Pester total, the exact command used. This file is the number the
      definition of done is measured against. Nothing in Phases 2–6
      edits it.
   Commit: "baseline: in-container suite counts at cutover"

1.2 RUNTIME DECLARATION
   a. Add to config/repo.json:
        "runtimes": {
          "powershell": "7.4",
          "python": { "version": "3.10", "allowed_under": ["modules/ledger/python/"] }
        }
      Update schemas/repo.schema.json. Extend scripts/ci/Test-RequiresHeader.ps1
      (or add scripts/ci/Test-Runtimes.ps1 under the same required check —
      do NOT add a new required check name in this phase) so that any *.py
      outside an allowed_under prefix fails the check. Prove it: drop a
      throwaway .py in scripts/, red; remove, green. Record.
   b. Run scripts/Generate-Policy.ps1; commit the regenerated POLICY.md and
      PR template with the config. If the generator does not render
      runtimes, add a "Runtimes" section to it — the policy doc must say
      Python is allowed and where, or the permission is not written down.
   Commit: "config: runtimes declared; python allowed under modules/ledger/python only"

1.3 PR
   gh pr create --base develop --fill. Wait for automerge. Record PR number
   and merge commit in FLOW-PROOF.md (started this phase, appended each
   phase, hashed in Phase 5). Park.

=====================================================================
PHASE 2 — POLICY MODULE                   branch: feature/module-policy
=====================================================================

2.1 COPY (unmodified)
   From claude.build.policy@<sha>:
     src/claude.build.policy/**   -> modules/policy/**
     tests/sandbox/policy_suite.ps1 -> modules/policy/tests/sandbox/policy_suite.ps1
     docs/do-not.md               -> modules/policy/docs/do-not.md
     examples/parse-here.ps1      -> modules/policy/examples/parse-here.ps1
   Record the sha256 of every copied file in the commit body. Do not
   rename the module yet.
   Commit: "scaffold: copy claude.build.policy@<sha>, unmodified"

2.2 ADAPT
   - Manifest: rename to modules/policy/policy.psd1 / policy.psm1 — the
     README names the three modules bare (ledger, policy, plans). Record
     the old import path in modules/policy/README.md under "Renamed from".
   - Port policy_suite.ps1 (10 checks) to modules/policy/tests/policy.Tests.ps1
     as Pester 5.7.1 with tag 'policy'. Every original check becomes one
     It block; do not merge or drop any. The sandbox script stays in place
     and still passes — it is the oracle the Pester port is checked
     against: both must report 10.
   - Wire scripts/ci/Invoke-Tests.ps1 to discover modules/*/tests/*.Tests.ps1
     in addition to tests/. Assert the total count went up by exactly 10
     over the Phase 1 recorded total.
   - modules/policy/README.md: three lines — what it is, what it is not
     (parses, never enforces — verbatim from the source README), renamed
     from.
   Commit: "feat(policy): module + pester suite, 10/10"

2.3 PR into develop. Automerge. Record. Park.

=====================================================================
PHASE 3 — PLANS MODULE                    branch: feature/module-plans
=====================================================================

3.1 COPY (unmodified) from claude.pwsh.image.builder@<sha>:
     src/PlanValidator.ps1     -> modules/plans/PlanValidator.ps1
     schemas/plan.schema.json  -> modules/plans/schemas/plan.schema.json
     plans/README.md           -> modules/plans/docs/plan-contract.md
   Do NOT copy src/LedgerReceipt.ps1 — it writes receipts, it belongs
   with the ledger module in Phase 4 if anywhere. Record as a finding
   whether its logic duplicates Ledger.psm1's receipt writer.
   Commit: "scaffold: copy plan validator from image.builder@<sha>, unmodified"

3.2 ADAPT
   - Wrap as modules/plans/plans.psd1 + plans.psm1 exporting the entry
     function PlanValidator.ps1 actually defines — measure, don't assume
     its name. Schema path resolved relative to $PSScriptRoot.
   - modules/plans/tests/plans.Tests.ps1, tag 'plans': a valid plan
     passes; each required field (id, steps[], expected_output,
     skills_to_build[]) missing fails; a plan with an unknown skill is
     accepted but the skill is listed (that is the contract: "listed, not
     ignored").
   - Note in FINDINGS: image.builder's Plan.Check and Test.FailFirst tasks
     still point at their local src/PlanValidator.ps1. Repointing them to
     the submodule is Phase 6 or later, in image.builder, not here.
   Commit: "feat(plans): module + pester suite"

3.3 PR into develop. Automerge. Record. Park.

=====================================================================
PHASE 4 — LEDGER MODULE                   branch: feature/module-ledger
=====================================================================

4.1 TRIAGE FIRST (no commit) — decide, per suite, library or not:
   ledger_chain.ps1    -> library. Migrates.
   forensic_chain.ps1  -> library (chain verify). Migrates. Compare its
                          forensic logic to substrate's scripts/forensic.ps1
                          (copied from image.builder, known to drift —
                          repo-policy FINDINGS #13). If they diverge, the
                          MODULE's version wins and scripts/forensic.ps1
                          is replaced by a thin wrapper that imports it.
   fail_path.ps1       -> library. Migrates.
   no_sabotage.ps1     -> library. Migrates.
   continuity.ps1      -> read it. If it tests .continuity/ chain
                          semantics, library; if it tests agent session
                          handoff behaviour, it is tools. Decide, record.
   fuzzer_import.ps1   -> NOT substrate. Imports claude.build.fuzzer by
                          sibling path. Destination: claude.agent.tools.
                          Record, do not copy.
   hook_pre_tool.ps1   -> NOT substrate. Tests the PreToolUse hook — a
                          container concern. Destination:
                          claude.agent.images. Record, do not copy.
   Write the triage table into FINDINGS.md before copying anything.

4.2 COPY (unmodified) from claude.build.ledger@<sha>:
     src/ledger/Ledger.psd1, Ledger.psm1, python/** -> modules/ledger/**
     tests/sandbox/<migrating suites>  -> modules/ledger/tests/sandbox/
     docs/**                           -> modules/ledger/docs/
     requirements.txt                  -> modules/ledger/python/requirements.txt
   Commit: "scaffold: copy claude.build.ledger@<sha> src+docs+suites, unmodified"

4.3 ADAPT
   - Rename manifest to modules/ledger/ledger.psd1 / ledger.psm1 per the
     same naming rule as Phase 2. Every internal path that assumed
     src/ledger/ is fixed; grep for 'src/ledger' and 'src\ledger' and
     list every hit in the commit body.
   - Port each migrating sandbox suite to Pester, one .Tests.ps1 per
     suite, tag 'ledger'. Sandbox originals stay and stay green — they
     are the oracle. Per suite, the Pester count must equal the sandbox
     count. Any difference is a finding, not a rounding.
   - Python: modules/ledger/tests/python.Tests.ps1 asserts `python
     --version` >= 3.10 and that cli.py --help exits 0 in dry-run.
     CI: add python setup to the pester job ONLY (actions/setup-python
     pinned by sha). pip install -r requirements.txt is NOT run — dry-run
     needs no SDK; assert that too.
   - ConvertTo-Json/ConvertFrom-Json ban on the chain (from the ledger
     README) — carry the ban as a Pester assertion that greps ledger.psm1's
     chain-writing functions for those cmdlets and fails on a hit.
   Commit: "feat(ledger): module + pester suites, python engine under modules/ledger/python"

4.4 REPORT for this phase: a table, one row per original sandbox suite:
   sandbox count | pester count | status (migrated / not-substrate / diff)
   Commit with FLOW-PROOF append. PR into develop. Automerge. Park.

=====================================================================
PHASE 5 — RELEASE v0.1.0                  branch: feature/release-0.1.0
=====================================================================

5.1 README.md: replace the "Status" section — no longer a skeleton;
   three modules present; per-module suite counts (from the Phase 4
   table and Phase 2/3); definition of done unchanged and still open
   until Phase 6. Update AGENTS.md's wall: "Module code" is no longer
   forbidden; replace with "Module code outside modules/<n>/ for a
   module this run order did not name".
5.2 Write REPORT.md (one section per phase: what landed, PR, merge
   commit, suite counts), finalise FINDINGS.md and FLOW-PROOF.md, then
   HASHES.txt + verify.ps1 exactly as the 2026-09-21 run order specified
   (same COMBINED join). Stop-Transcript before hashing.
5.3 Forensic seq N+1: subject substrate-modules-landed, evidence =
   COMBINED + the three module suite totals + Phase 1..4 merge commits.
   Verify chain.
5.4 PR into develop. Automerge. Then `gh pr create --base main --head
   develop --fill`. Automerge. Then, on the MAIN merge commit:
   git tag -a v0.1.0 -m "substrate v0.1.0: ledger, policy, plans" ;
   git push origin v0.1.0. Record the tagged sha in your final message.
   Park.

=====================================================================
PHASE 6 — CUTOVER (image.builder)         branch: feature/submodule-substrate
=====================================================================
This phase writes to claude.pwsh.image.builder. It is the ONLY phase that
does. Nothing else in image.builder is edited — not .build.ps1, not the
Dockerfile, not Plan.Check. If the switch cannot be made without editing
anything else, STOP and write a finding: that is real information about
how tightly image.builder is coupled to the old layout.

6.1 In image.builder, on a feature branch per ITS flow (measured in 1.0):
   git submodule deinit vendor/claude.build.ledger ; git rm
   vendor/claude.build.ledger ; git submodule add
   https://github.com/JerryBalmer1/claude.agent.substrate.git
   vendor/claude.agent.substrate ; cd there ; git checkout v0.1.0 ; cd ..
   Commit: "chore: submodule ledger -> substrate@v0.1.0" with who: claude.
6.2 Rebuild the image. Rerun scripts/Measure-Baseline.ps1 (from substrate)
   against the new image with the suite root now
   vendor/claude.agent.substrate/modules/ledger/tests/sandbox.
6.3 Compare to BASELINE.md, per suite. Expected: identical counts for
   every MIGRATED suite; fuzzer_import and hook_pre_tool absent here and
   present in BASELINE as the two known removals. Any other difference is
   a failed cutover: do not merge; write the finding; park both repos.
6.4 If identical: PR in image.builder per its own flow. Then in substrate,
   feature/review-human: config review.mode -> "human", regenerate, PR
   into develop (this is the last automerged PR — the base still says
   auto), then develop -> main (this one waits for Jerry). Final message
   FIRST line: "CUTOVER GREEN: <n>/<n> suites match baseline;
   image.builder PR #<n>; substrate develop->main PR #<n> waiting on
   Jerry" — or the failure in one line.

PARK after every phase:
   git switch develop; git pull --ff-only; git branch -vv; git status;
   gh pr list --state all --limit 5
   Final message per phase: FIRST line = phase number, PR number, merged
   or waiting and why. LAST block = the git state above, verbatim.
```

---

## VERIFY (Fable / Grok)

```powershell ledger:paste
#Requires -Version 7.4
Set-Location 'C:\__Code\____Claude.Build\claude.agent.substrate'; "PWD: $PWD"
git fetch origin --prune --tags; git switch develop; git pull --ff-only
Get-ChildItem modules -Directory | Select-Object Name
& ./scripts/ci/Invoke-Tests.ps1; "pester exit: $LASTEXITCODE"
& ./docs/plans/2026-09-22-substrate-cutover/verify.ps1; "verify exit: $LASTEXITCODE"
Get-Content ./docs/plans/2026-09-22-substrate-cutover/BASELINE.md | Select-String '^\|' | Select-Object -First 20
git tag -l 'v*'; git rev-list -n1 v0.1.0 2>$null
git -C ../claude.pwsh.image.builder submodule status
gh pr list --state all --json number,title,state,baseRefName,headRefName,mergeCommit --jq '.[] | "\(.number) \(.state) \(.headRefName)->\(.baseRefName) \(.mergeCommit.oid // "-") \(.title)"'
```

Checks that don't trust the report:

1. `BASELINE.md` was committed in Phase 1's PR and has **not changed since** — `git log --oneline -- docs/plans/2026-09-22-substrate-cutover/BASELINE.md` shows exactly one commit.
2. Every phase is one merged PR into `develop` with a two-parent merge commit; phases are in order by merge time.
3. For every module, the first commit touching `modules/<n>/` is a byte-identical copy — diff it against the sibling at the sha named in the commit subject and get an empty diff.
4. Per migrating suite, sandbox count == Pester count, and both are reproducible by running them now.
5. `fuzzer_import.ps1` and `hook_pre_tool.ps1` do **not** exist anywhere under `modules/`. FINDINGS names their destination repos.
6. No `.py` file exists outside `modules/ledger/python/`; `config/repo.json` `runtimes.python.allowed_under` says so; the CI check fails when one is planted; `docs/POLICY.md` states the permission.
7. The Phase 0 closeout's guarantees still hold after all six phases: `Get-ReviewConfigRef` returns the base ref, `config/trailer-grandfather.txt` still lists exactly one hash, `push-guard` is still not in `required_checks`. None of these files was touched by this run except as a finding says.
8. `v0.1.0` points at a commit on `main`, and image.builder's submodule status shows that exact sha under `vendor/claude.agent.substrate`.
9. Phase 6's per-suite comparison table shows every migrated suite at its baseline count; the only rows absent are the two recorded removals.
10. No sibling repo other than image.builder has a commit after Phase 1's source-pin shas. image.builder has exactly one commit on the topic: the submodule switch.

Grok signs off on 1–10. Fable audits the forensic chain from the closeout's final seq through this run's final seq, and checks the copy-then-adapt commit pairs in Phases 2–4 against TRANSCRIPT.log.
