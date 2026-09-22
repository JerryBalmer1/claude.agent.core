# REPORT — substrate-finish 2026-09-22

What `RUN-ORDER.md` in this folder said, and what actually happened. One row per step. Every number
here was printed by a script in this repository; none was carried over from a prediction.

Measured on `develop` at `a57fbe6a16f55294f2f19c3bc2f3fa18a7fc5e06`, the merge commit of PR #55.

## Said vs did

| Step | Said | Did | Findings |
|---|---|---|---|
| 0 — re-measure | expect ledger 84, policy 10, plans 11, repo 74, total **179**; correct the README table if it disagrees | measured 179 on the day; the table was corrected on the 6.4 branch as instructed. The step also turned up something the run order did not ask about: `verify.ps1` was **already red on `develop`** before the pass began, check 1, because `HASHES.txt` had gone stale two commits earlier | F58, F61 |
| 6.2 — rebuild from the merge | rebuild both images from PR #9's merge commit, record ids; stop if any failure sits outside `python.Tests.ps1` | rebuilt at image.builder `5f71173`; 4 tasks, 0 errors. Leash id **identical** to the one `0b47155` recorded; developer id **not** identical, and the reason is a real defect rather than noise — `__pycache__` is gitignored but not dockerignored, so host bytecode rides into the image. No failure outside `python.Tests.ps1`. image.builder's own `Test.Unit` read 174/2, both reds an artifact of an empty PR range on a parked clone | F62, F63 |
| 6.3 — F10 decided image-side | open `feature/f10-python-shim` in image.builder, add the shim, rebuild, PR, merge | **no such PR was opened, and none was needed.** The shim had already landed *inside* PR #9 at `0b47155`. The run order was written against a state that no longer existed by the time it ran. Developer **167/167**, leash **156/167**, all 11 reds in `python.Tests.ps1` | F60 |
| 6.4 — review mode → human | flip `review.mode`, regenerate, last automerged PR, then `develop → main` | PR #51 flipped it; release PR #52 carried it to `main`. Flipping the value **broke the test that proves the schema rejects a bad `review.mode`** — the falsification had been keyed to the literal string `auto`, so changing the config made the guard vacuous. Caught and repaired in the same pass. Forensic seq 10 appended | F64 |
| 6.5 — retire ledger and policy | flip the retire rows, drop `MIGRATION-SOURCE.md` into both legacy repos, then `status → retired`, `context_policy → do-not-load` | PR #54. Six of seven ledger rows flipped and the stubs landed — but **6.5d did not execute: neither source retired.** `tests/Migration.Tests.ps1` refused it, which is the suite doing its job. The policy repo's fourth condition is written as a grep that matches its own text in `migration.json` and misses the one real importer, so it can never pass as phrased; `scripts/Test-SiblingImports.ps1` was written to measure the real thing | F68, F69 |
| 6.6 — F44 TEST 10 | option A (cross-platform lying snake) or, after two failed pushes, option B (formally accept the hole) | **option A, green on both platforms.** The finding is worth reading for how it got there: the first version of it declared the non-Windows twin impossible, and was corrected by its own falsifier going red on the runner. No option B was needed | F67 |
| 7 — plans at the consumer's validator | pin to image.builder's `ff7b2baf`, export `Get-PlanSchemaPath`, un-inert `-SchemaPath`; stop if the blob is not `ff7b2baf` | PR #55. Blob matched the prediction. The validator now reads the schema — and **two rules were lost that nobody scheduled to lose**: the step-shape rule and the rejection of a blank `skills_to_build` entry, both of which the old hand-written validator enforced and the schema does not. Measured fixture by fixture rather than inferred. Parked as `docs/BACKLOG.md` **B5**, because restoring them is a change to the plan contract, not a fix. `verify.ps1` drops to **17/19** by design, checks 7 and 8, and is not edited | F70, B5 |
| reconciliation | (not in the run order) | the three packet branches were authored in parallel against the same base. **#54 merged first**, so #56 and #55 were each merged over it in turn, one merge commit apiece, `FINDINGS.md` reassembled into numerical order across all three. `migration.json` was predicted key-disjoint and **measured** key-disjoint — 19 keys from one side, 18 from the other, empty intersection, all 37 present afterwards | F71, F72 |
| release gate | (not in the run order) | the previous packet's `develop == main` gate is **unreachable by construction** and was replaced with an ancestry check. Recorded below | F73 |

## The release gate, recorded as F55 was

The previous packet gated the release on `develop == main`. No release can satisfy it. The flow
merges `develop` into `main` with a merge commit whose second parent is `develop`'s tip, so that
commit lives only on `main`; `main` is always one merge commit ahead and `develop` never
fast-forwards to it. Measured across all eleven release merges in the repository, every one is
`p1 = main`, `p2 = develop`.

Five of those eleven *are* reachable from `develop`, and the reason is not a back-merge — no merge
commit on `develop` names `main` at all. `git rev-list --children` shows `3933dccf` (`main` at
`v0.1.0`) with two children, one of which is `edc3c7a5`, the first commit of
`feature/substrate-analysis-2026-09-21` — **a feature branch cut from `main` instead of `develop`**,
later merged into `develop` as PR #44. Every release merge before that event became reachable as a
side effect; every one after it is not. The only history that ever resembled the gate being
satisfied is history produced by breaking the branch rule.

The replacement gate, `git merge-base --is-ancestor develop main`, asks a different and answerable
question: is `develop` *reachable from* `main`. Immediately after a release merge it is, because
`develop`'s tip is the second parent. It fails only once `develop` has advanced past the release,
which is exactly the condition worth stopping for.

The same mistake appears a second time, in another repository, within the same day: the
`claude.agent.tools` A0 preflight requires
`git -C ../claude.agent.substrate rev-parse v0.2.0 main develop` to print one sha three times. Two
of those refs are `main` and `develop`, so it is unsatisfiable here for this reason alone,
independently of `v0.2.0` not yet existing. It halted that run order at A0.

Neither gate is edited. F55's precedent holds: record the condition as unreachable, state the
replacement, leave the frozen artifact saying what it said. Full detail and the measurement tables
are `FINDINGS.md` **F73**.

## Numbers

| | value | printed by |
|---|---|---|
| Pester, host | **188 / 188**, 0 failed | `scripts/ci/Invoke-Tests.ps1` |
| per module | ledger 91, policy 10, plans 12, repo 75 | `scripts/Measure-Modules.ps1` |
| `verify.ps1` | 19 checks, **17 passed, 2 failed** — checks 7 and 8, both F70's, both by design | `docs/plans/2026-09-22-substrate-cutover/verify.ps1` |
| migration manifest | `MIGRATION.md` matches `migration.json` | `scripts/New-MigrationReport.ps1 -Check` |
| in-container, developer | **167 / 167** | `scripts/ci/Invoke-Tests.ps1` under `claude.pwsh.image.developer:run-01` |
| in-container, leash | **156 / 167**, 11 reds all in `python.Tests.ps1` | same, under `claude.pwsh.image.leash:run-01` |
| retirement | ledger **6 of 7**, policy **3 of 4** — neither retires | `docs/migration/migration.json` |

## What is open

- **Neither source repository retires.** `claude.build.ledger` waits on `claude.agent.tools`
  (`fuzzer_import.ps1`'s destination) and `claude.agent.images` (`hook_pre_tool.ps1`'s);
  `claude.build.policy` waits on the inspector's sibling-path import moving to `claude.agent.tools`.
  Both are blocked on repositories that do not exist yet, not on work anybody declined.
- **B5** — whether the plan schema should restore the two rules Phase 7 dropped.
- **B8** — merge commits made outside automerge carry no `who:` trailer. Three instances so far
  (#53, #54, #56). F72 refused to paper over it with a grandfather entry.
- **F62** — the developer image is not reproducible until `__pycache__` is dockerignored (B6).
- **F63** — image.builder's trailer tests cannot all be green on a clone parked as its own rules
  require (B7).
