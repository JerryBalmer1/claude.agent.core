# RELEASE NOTES — v0.2.0

What changed since `v0.1.0` (`3933dccf4013f9427a2e14206899ec8eede155cd`), written for somebody who
consumes this repository as a submodule rather than for somebody who worked on it.

Headline: **`modules/plans` now reads its JSON schema instead of restating it in PowerShell.** That
is the only behavioural change to a shipped module. Everything else is tests, fixtures, tooling and
governance.

## Breaking, or behaviour you may be relying on

**`Test-PlanStructure` accepts two plans it used to reject.** The validator was rewritten to read
`schemas/plan.schema.json`, and two rules that the old hand-written version enforced are not in the
schema, so they are gone:

| Rule | v0.1.0 | v0.2.0 |
|---|---|---|
| a step must have an `action` | rejected | **accepted**, if the schema allows it |
| a blank entry in `skills_to_build` | rejected | **accepted** |

Neither removal was scheduled. Both were measured fixture by fixture and recorded in `FINDINGS.md`
**F70**, and restoring them is parked as `docs/BACKLOG.md` **B5** — putting them back is a change to
the *plan contract*, not a bug fix, so it is not being done quietly inside a patch release. If you
depend on either rule, validate for it yourself until B5 is decided.

## Added

- **`Get-PlanSchemaPath` is exported from `modules/plans`.** v0.1.0 exported `Test-PlanStructure`
  and nothing else.
- **`-SchemaPath` is read.** In v0.1.0 the parameter existed and was inert: passing it changed
  nothing. It now selects the schema, a plan the schema rejects fails, and a missing schema path
  throws rather than silently falling back (F27, F28).
- **`modules/policy/examples/parse-here.ps1` runs.** It resolved its manifest by a path that did not
  survive the Phase 5 rename; it is fixed, not deleted (F24, F47).
- **`scripts/forensic.ps1` accepts `arena-utterance`** as a record kind, alongside `finding`,
  `confession`, `repair`, `decision` and `verification`.
- **`.github/workflows/automerge.yml` triggers on `ready_for_review`.** A pull request opened as a
  draft previously parked automerge permanently, and the stand-down looked green (F65).
- **A cross-platform `LedgerResultMismatch` fixture.** `modules/ledger/tests/fixtures/lying-snake/`
  ships a `.cmd` and an extensionless `#!/usr/bin/env pwsh` stub, chosen at runtime on `$IsWindows`.
  F44's TEST 10 hole, open at the v0.1.0 tag, is closed on both platforms (F67).

## Unchanged

`modules/ledger` and `modules/policy` export exactly what they exported at `v0.1.0`:

```
ledger   Invoke-LedgerForce, Get-LedgerStatus, Get-LedgerVerify, Get-LedgerEntry
policy   Get-PolicyRules
```

No API in either module changed. The ledger's additions are all under `tests/`.

**`ModuleVersion` in all three manifests reports `0.2.0` here.** In `claude.agent.substrate` the
same three report `0.1.0`, and that is deliberate rather than stale: its `ledger.psd1` is a
byte-level provenance proof against the repository the module was copied from, and moving the
version would have broken the assertion that reconstructs the source manifest. Core makes no such
copy claim, so it carries the version its tag says. A consumer pinning against substrate should
still pin by the tag or the submodule sha, not by `(Get-Module plans).Version`. See
`docs/FINDINGS.md` F76.

## Measured at this tag

```
Pester, host            188 / 188, 0 failed        scripts/ci/Invoke-Tests.ps1
per module              ledger 91, policy 10, plans 12, repo 75
in-container developer  167 / 167                  claude.pwsh.image.developer:run-01
in-container leash      156 / 167                  11 reds, all python.Tests.ps1, by design
verify.ps1              19 checks, 17 passed       checks 7 and 8 red by design, F70
```

`verify.ps1` belongs to the 2026-09-22 cutover plan and verifies the tree *that* plan produced. Its
two reds are the plans export list and the `PlanValidator.ps1` blob — both changed on purpose by
Phase 7. It is a frozen receipt and is not edited to agree with a later release.

## For consumers

**`claude.pwsh.image.builder`.** Its `Plan.Check` and `Test.FailFirst` still point at its own local
`src/PlanValidator.ps1` rather than at the submodule. Repointing them is that repository's work,
under its own run order, **after** this tag exists — it is deliberately not done from here (F31).
Its `migration.json` row stays unmet until it happens.

**`claude.agent.tools`.** Its cutover plan names substrate `v0.1.0` as the pin. It should pin to
**`v0.2.0`** instead: `modules/plans`' export list changed at this tag, so a `v0.1.0` pin would be
wrong on the day the repository is created. That plan is not edited from here; this note is the
record that the pin target moved, and the tools run order supersedes its own plan document.

**Everyone else.** `v0.1.0` → `v0.2.0` is safe unless you call `Test-PlanStructure` and depend on
either rule in the table at the top.
