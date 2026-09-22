# claude.agent.substrate v0.1.0

**One library, three modules: `ledger`, `policy`, `plans`.** Tagged on the `develop` → `main`
merge commit at the end of Phase 5 of the substrate cutover.

This is a library release. Substrate is not a container, has no entrypoint and builds no image —
`claude.pwsh.image.builder` is the thing that builds containers, and substrate is the thing it
consumes. Nothing in this release changes that.

---

## What is in it

| Module | Import path | What it does | Copied from |
|---|---|---|---|
| `ledger` | `modules/ledger/ledger.psd1` | the receipt chain and the Python snake behind it | `claude.build.ledger@d57938d` |
| `policy` | `modules/policy/policy.psd1` | markdown law → content-hashed `PolicyRule` objects; parses, never enforces | `claude.build.policy@3be10c4` |
| `plans` | `modules/plans/plans.psd1` | `Test-PlanStructure` over a plan document | `claude.pwsh.image.builder@a6b61dd` |

Every module's first commit is a **byte-identical copy** of its source, committed alone before a
single line was adapted, so the adaptation is a diff a reviewer can read. `FLOW-PROOF.md` lists
every blob sha and the command that reproduces it; the ledger and plans suites re-assert theirs
from the bytes on disk on every run.

`modules/policy`'s manifest was renamed in this release — `claude.build.policy.psd1` became
`policy.psd1`, and the module name is now `policy`. `FINDINGS.md` F47 has the before and after of
both assertions that changed, and what it did not change: `policy.psm1` is still the byte-identical
copy, still hashing to blob `72dc1ec6`.

## The two tables, and why they are not the same measurement

This is the part most likely to be read wrong, so it is stated before the numbers.

**`BASELINE.md`'s 127 and this release's 167 are not the same kind of thing, and 167 is not a
successor to 127.** They count different assertions, written in different frameworks, executed in
different places, against different trees. Neither number can be subtracted from, compared to, or
substituted for the other.

### The baseline — 127, in-container

Measured on 2026-09-21 by `scripts/Measure-Baseline.ps1`, inside
`claude.pwsh.image.leash:run-01` and `claude.pwsh.image.developer:run-01`, against the tree
image.builder **pins as its submodule** (`ed9c9d7`) — which is behind `claude.build.ledger`'s HEAD.

| Suite | Passed | Total | Status |
|---|---|---|---|
| `continuity.ps1` | 77 | 77 | GREEN |
| `forensic_chain.ps1` | 28 | 28 | GREEN |
| `no_sabotage.ps1` | 22 | 22 | GREEN |
| **3 suites producing a count** | **127** | **127** | |
| `hook_pre_tool.ps1` | 11 | — | ABORTED, partial, excluded |
| `fail_path.ps1` | — | — | could not start |
| `fuzzer_import.ps1` | — | — | could not start |
| `ledger_chain.ps1` | — | — | could not start |

These are hand-rolled `Assert-That` sandbox scripts run with `pwsh -NoProfile -File` inside a
container that has the whole ledger repository mounted at `/work`. **127 is the number the
README's definition of done is measured against, and Phase 6 is what measures it.**

### This release — 167, on a runner

Measured by `scripts/Measure-Modules.ps1`, Pester 5.7.1 pinned from `config/repo.json`, on
`ubuntu-latest` in CI and on the workstation:

| Bucket | Tests |
|---|---|
| `ledger` | **84** — `ledger.Tests.ps1` 66, `python.Tests.ps1` 18 |
| `plans` | **11** |
| `policy` | **10** |
| the repository's own `tests/` | **62** — six files |
| **total** | **167** |

```powershell
pwsh -NoProfile -File scripts/Measure-Modules.ps1
```

### Why they cannot be compared

- **Different suites.** Of the three suites that produce the baseline's 127, **none** is in this
  release. `continuity.ps1` and `no_sabotage.ps1` were triaged as not-substrate (`FINDINGS.md`
  F37); `forensic_chain.ps1`'s subject is covered by substrate's own `forensic-verify` check and
  `tests/Skeleton.Tests.ps1` instead (F42).
- **Different trees.** The baseline measures the submodule pin. This release measures substrate at
  `v0.1.0`.
- **Different granularity.** A Pester `It` and a sandbox `Assert-That` line are not the same unit.
  Phase 4 turned one original assertion into eleven where the subject deserved eleven, and that
  alone makes any arithmetic between the two columns meaningless (`FINDINGS.md` F43, F44).
- **Different place.** One runs in a container with siblings mounted; the other runs on a bare
  runner with no sibling repository anywhere.

The run order asked Phase 4 for a per-suite `sandbox count | pester count` comparison. It could not
be produced honestly — the three sandbox originals in the tree **cannot run here at all** (F43) —
so what is published instead is F44: a subject-by-subject table of what each original asserted and
where that assertion now lives, including the four subjects that are not covered.

## In-container, measured after PR #9 (5f71173)

This is clause 2 of the definition of done, and clause 3's row-by-row comparison. Measured
2026-09-22 against `claude.pwsh.image.builder` at `develop` =
`5f711736e028f0078d8b32b732ec37cb224258be`, the merge commit of PR #9, with
`git submodule status` reporting
`3933dccf4013f9427a2e14206899ec8eede155cd vendor/claude.agent.substrate (v0.1.0)`.

`Invoke-Build Bootstrap, Build.Image` — **4 tasks, 0 errors, 0 warnings**.

| Image | Id |
|---|---|
| `claude.pwsh.image.leash:run-01` | `sha256:968f1ce9e04a65864afd0f625a9a83f2eca62c05d705646ce385217477a50a3a` |
| `claude.pwsh.image.developer:run-01` | `sha256:165da90f527dde047de0c45eaa7d6d233a4bc85f8e978a52b4de840f84d9e057` |

The leash id is **identical** to the one image.builder's `0b47155` recorded. The developer id is
**not** — that commit recorded `sha256:d587a1a1…` — and the reason is measured rather than waved
at in `FINDINGS.md` **F62**: `__pycache__` is gitignored but not dockerignored, so host-generated
Python bytecode rides into both images through `COPY …/modules/ledger/python/`. Every tracked
input to that image is byte-identical between `0b47155` and the merge commit.

| Run | Total | Passed | Failed | Exit |
|---|---|---|---|---|
| developer container | 167 | **167** | 0 | 0 |
| leash container | 167 | **156** | 11 | 1 |
| non-`python.Tests.ps1`, either container | 149 | **149** | 0 | — |

**167, not 179.** The submodule is pinned at `v0.1.0`, which predates the twelve tests in
`tests/Migration.Tests.ps1` that `README.md`'s table counts on `develop`. Same suite, two trees.

The exact command, run once per image with only the tag changed:

```powershell
docker run --rm `
  -v "${root}:/work" `
  -w /work/vendor/claude.agent.substrate `
  -e GIT_CONFIG_GLOBAL=/work/output/substrate.gitconfig `
  --entrypoint pwsh `
  claude.pwsh.image.developer:run-01 `
  -NoProfile -File /work/vendor/claude.agent.substrate/scripts/ci/Invoke-Tests.ps1
```

Both images declare `USER claude`, so this is the non-root user without a `-u` flag, which
`docker image inspect --format '{{.Config.User}}'` states. `GIT_CONFIG_GLOBAL` points at a
throwaway file written to image.builder's gitignored `output/`, naming four `safe.directory`
entries: `/work`, `/work/.git`, `/work/vendor/claude.agent.substrate` and
`/work/.git/modules/vendor/claude.agent.substrate`. `build/container.gitconfig` names only the
first two, and without the last two git exits 128 on the bind mount and roughly ten unrelated
tests fail on "detected dubious ownership" — `0b47155` records the same trap and the false
157/10 it produced before the file was added. That file was not edited.

**The 11 leash failures, all in `modules/ledger/tests/python.Tests.ps1`, expected by design.**
The leash image ships neither `python` nor `python3`, because it never spawns the snake: its
entrypoint verifies and its sentinel appends, and both are PowerShell. The names are identical
to the eleven `0b47155` listed:

- `a python interpreter is on PATH`
- `and it is at least the version config/repo.json declares`
- `cli.py --help exits 0`
- `cli.py refuses a protocol it does not speak, with a usage exit code`
- `all four engine modules compile`
- `the anthropic SDK is genuinely not installed`
- `snake.py imports anthropic lazily, inside the live path only`
- `a full dry-run force runs the retry loop, appends one receipt, and never touches the network`
- `the receipt records the hash of the output that was actually returned`
- `an exhausted retry cap throws LedgerSnakeFailed and returns nothing`
- `live mode with no API key throws before the snake is spawned, and writes no receipt`

No file outside that one has a red in either container.

**image.builder's own host suite, `Invoke-Build Test.Unit`: 174 passed / 2 failed of 176.** Both
reds are in its `tests/Trailers.Tests.ps1`, and both are an artifact of *where the measurement was
taken*, not of the cutover: the three tests in `the trailer guard over the pull-request range`
drive `origin/develop..HEAD`, which on a clone parked on `develop` after the merge contains **zero
commits**, so the guard prints `PASS -- no commits in range` and the two falsification tests that
require exit 1 cannot fire. Proven both ways in `FINDINGS.md` **F63**. This is image.builder's to
fix, and Phase 6.2 is read-only.

## Known gaps

Named at the tag, because a version number is where known gaps go to be forgotten.

1. **`LedgerResultMismatch` is unexercised.** The ledger module raises it when the snake's result
   event does not describe the run that was asked for. Nothing in the port proves it. The original
   drove it with a stub snake that returns a doctored event, and that stub is a Windows `.cmd`;
   `ubuntu-latest` is this repository's only gate, a shell replacement is banned by `AGENTS.md`,
   and a Python one would land a `.py` outside `runtimes.python.allowed_under`. The error id is in
   the pinned vocabulary with nothing behind it. `FINDINGS.md` F44 and F51.

   **CLOSED on 2026-09-22, on both platforms.** The gap statement above stands as written at the
   tag. `modules/ledger/tests/fixtures/lying-snake/` now gives the id a test: a stub that answers a
   `dry-run` request with `"mode": "live"`, after which `Invoke-LedgerForce` raises
   `LedgerResultMismatch` and writes no receipt. Six `It`s, green on Windows **and on
   `ubuntu-latest`**, none skipped. The stub is chosen on `$IsWindows` — `lie.cmd` there, and an
   extensionless `#!/usr/bin/env pwsh` script with mode `100755` everywhere else. It cannot be the
   `lie.ps1` the finish run order specified, because a `.ps1` is an `ExternalScript` and
   `Get-Command -CommandType Application` — the lookup `ledger.psm1` uses for `-PythonPath` —
   never returns one.

   An earlier version of this entry said the non-Windows half was **impossible** and marked the
   test skipped. That was wrong: it generalised a Windows-only `pwsh -File` refusal to every
   platform. The falsifier committed beside the claim went red on the runner and the twin was
   built. `FINDINGS.md` F67 keeps both the claim and the correction.
2. **Three more subjects are not covered by the ledger port** — the `-Policy`/`-Halt`
   pass-through and the halt-writes-no-receipt rule, both of which need the Inspector sibling on
   disk, and the forensic chain, which substrate covers its own way. F44.
3. **`-SchemaPath` is inert** in the plans module: the copied validator never reads the schema, so
   a plan the schema rejects still passes. Recorded, not fixed, by instruction. F5, F27, F28.

   **CLOSED on 2026-09-22 by Phase 7.** The gap statement above stands as written at the tag.
   `modules/plans/PlanValidator.ps1` is now blob `ff7b2baf` — image.builder's schema-reading
   rewrite — so `-SchemaPath` is read: a plan the schema rejects fails, and a schema path that
   does not exist throws. F5, F27 and F28 are all closed by taking the bytes the caller those
   findings were measured against actually calls. It cost two rules their strictness, both
   measured: a step with no `action` now passes, and so does a **blank** entry in
   `skills_to_build`, because the schema constrains neither. `FINDINGS.md` F70.
4. **The definition of done is not met by this tag.** It is met in Phase 6, when image.builder's
   submodule points at `v0.1.0` and its in-container suite matches `BASELINE.md` per suite.
   Clauses 1 and 2 were measured green on **2026-09-22** against image.builder `develop` at
   `5f71173`, and clause 3 is the section above; the gap statement stands as written at the tag,
   because the tag is where it was true.
5. **The three sandbox originals under `modules/ledger/tests/sandbox/` and
   `modules/policy/tests/sandbox/` do not run here.** They are kept byte-identical as the
   provenance the ports were written from, and they are excluded from the suite by Pester's own
   `*.Tests.ps1` filter. F24, F43.
6. **Enforcement is CI, not branch protection.** Free tier; protection was attempted once and
   refused. A human with push access can still push straight to `main`.

## Verifying this release without trusting it

```powershell
pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/verify.ps1
```

Eight checks, printed as 19 PASS/FAIL lines: `HASHES.txt` recomputes from the files on
disk; every CI check script passes against `HEAD`; `BASELINE.md` still has exactly one commit; only
the three named modules exist and the two not-substrate suites are nowhere under `modules/`; no
tracked `.py` sits outside `runtimes.python.allowed_under`; the README's per-module table equals a
live Pester run; the three manifests import and export what they claim; and the three provenance
blobs — including `modules/ledger/ledger.psm1` at `37d63403` — are unchanged.

The forensic chain carries this release as record **seq 6**, `substrate-modules-landed`, whose
evidence is the `COMBINED` hash over this plan directory plus the three module totals plus the
Phase 1–4 merge commits:

```powershell
pwsh -NoProfile -File scripts/forensic.ps1 -Verify
pwsh -NoProfile -File scripts/forensic.ps1 -Anchor
```

The chain is tamper-**evident**, not tamper-proof: anyone with write access can rewrite the file
and recompute every hash. What it buys is that a partial edit is detectable and a full rewrite
moves the tip — so the anchor line is worth printing somewhere no agent can reach.
