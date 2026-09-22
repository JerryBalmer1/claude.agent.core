# plans

**What it is.** A structural validator for plan objects: one exported function,
`Test-PlanStructure`, returns `$true` for a plan that has a non-blank `id` and `expected_output`,
a `steps` array holding at least one step, a non-blank `action` on every step, and no blank entry
in `skills_to_build`. Anything else throws, naming the first fault.

**What it is not.** It does **not** validate against `schemas/plan.schema.json`. The schema ships
here as provenance and as the document the validator disagrees with; nothing opens it. The
`-SchemaPath` parameter exists because run order 3.2 asks for it, defaults to this module's schema
relative to `$PSScriptRoot`, and is inert — `tests/plans.Tests.ps1` proves that by behaviour as
well as by grepping both source files for `Test-Json`. See
`docs/plans/2026-09-22-substrate-cutover/FINDINGS.md` F5 and F27. It also does not run plans,
resolve skills, or list them.

**Where the validator and the schema disagree.** The validator requires an `action` on every step;
the schema says nothing about step shape. The validator accepts `id: 42`; the schema says `id` is
a string. The **validator's behaviour is the contract**, because it is what image.builder actually
ran — F4. Neither file was edited to make them agree.

**Copied from.** `claude.pwsh.image.builder@a6b61dd6ab3d4e2a61e05de6be92f2dfebcd72c1`,
byte-identical, in `04bcfe8`:

| Source | Here | Blob |
|---|---|---|
| `src/PlanValidator.ps1` | `PlanValidator.ps1` | `8e5da7682f212499e4fb33c2cdaafe1fb1aa2a09` |
| `schemas/plan.schema.json` | `schemas/plan.schema.json` | `ad219cb0a4503ca1854f612df84abe267413dc6a` |
| `plans/README.md` | `docs/plan-contract.md` | `b9c435354abf28f6511bee8d1dde2fe8ae6f915c` |

`plans.psm1` dot-sources `PlanValidator.ps1` and never edits it; its blob sha is asserted by the
suite. `docs/plan-contract.md` is the copied contract document and is stale at the source — it
names `tests/plan.failfirst.ps1`, which image.builder deleted (F8), and it calls `skills_to_build`
required, which neither the schema nor the validator does (F3). It is kept as it was copied.
