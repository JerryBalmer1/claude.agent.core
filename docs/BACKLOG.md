# BACKLOG

Work that is named but **not** scheduled. Nothing on this list was built by the packet that created
the file, and nothing here is a commitment to build it.

One line each. `owner` is who picks it up, not who is blamed for it. No dates: a date on a backlog
item is a promise nobody made, and this repository has enough of those written down already.

A line earns its place here by being a thing someone already measured and chose not to do. If it
has no finding number and no measurement behind it, it is an idea, and ideas go in a prompt.

## core

| # | Item | Owner | Why it is not done yet |
|---|---|---|---|
| B1 | `docs/plans/2026-09-22-substrate-cutover/FINDINGS.md` gets a generated index, plus a drift test that fails when the index and the headings disagree | claude | the file is past 2000 lines and 70 findings; the index has to be generated or it becomes the eighth place to forget |
| B2 | Prompts and run orders cite findings **by number**, and a check that fails on a bare "see FINDINGS" | claude | citation by number is what made F59, F61 and F67 traceable; nothing enforces it |
| B3 | `scripts/Measure-Cadence.ps1` — commits, PRs and findings per phase, measured rather than recalled | claude | every cadence claim so far has been a memory, and this repository does not accept those anywhere else |
| B5 | Decide whether `modules/plans/schemas/plan.schema.json` should constrain a step's shape and forbid a blank `skills_to_build` entry | claude | F70: both rules were lost when the validator started reading the schema instead of restating it. Adding `minLength` and a step object shape is a change to the **plan contract**, not a fix, and the schema is a `landed` item with a recorded blob |
| B8 | The merge button writes no `who:` trailer, so `-IncludeMerges` over `main` goes red on every merge not made by automerge | claude | F72: `.github/workflows/automerge.yml` writes the trailer into the merge body; the two release merges at the end of the cutover were merged another way and landed bare, so a full-history run with `-IncludeMerges` measured 2 non-compliant. Grandfathering was refused on the exemption file's own terms, and exempting one of the two would not have changed the exit code. Either the merge path writes the trailer or the `-IncludeMerges` claim is formally downgraded to advisory. Core starts clean — its root commit carries the trailer — so this is a rule to hold, not a debt to repay |
| B9 | `scripts/ci/Test-BranchFlow.ps1` accepts a `-Ref`, or falls back to `git branch --contains`, so a detached checkout at a tag can verify | claude | F76: `verify.ps1` derives the head from `git rev-parse --abbrev-ref HEAD`, which is literally `HEAD` when detached and `main` on the settled branch. Neither matches a row in `config.flow`, so verify reports 16/19 for a reason that is about the branch name and not about the tree. Run it from `develop` until this lands |
| B10 | Retire `tenacity` from `modules/ledger/python/requirements.txt`, and its row from `modules/ledger/tests/fixtures/copied-blobs.psd1`, in one pull request with a receipt | claude | F75: it is declared, never imported, never installed. It cannot be dropped alone — the file is one of eleven pinned blobs, and editing it without moving the pin trades a real provenance claim for a cosmetic one. Both edits or neither |
| B11 | Rebuild the `PushGuard` and `Trailers` negative tests against synthetic repositories built in `TestDrive` — a trailerless root, a one-parent commit, a two-parent merge — with no pinned live shas and no grandfather file | claude | F78: the versions that were removed at birth pinned the source repository's commit shas as fixtures, so a clean copy could not run them, and in a tree missing those objects they went green off `git`'s `fatal: bad object` instead of off the guard. Until this lands, the guards' negative path is enforced in CI and proven nowhere |
| B12 | Re-run the three calls in `docs/PROTECTION.md` -> "What was attempted" and close F80 | claude | F80: branch protection and rulesets are paid features for a private repository and the account is on the free plan. Five calls on 2026-09-22 returned HTTP 403 and changed nothing. 403 is the tier declining the feature, not a 404 for an unset branch, so there is no toggle anybody can reach. It becomes actionable the moment the account is Pro or the repository is public, and not before. Until then every tag of this repository is pinned against a `main` that nothing server-side refuses to rewrite, which is what F80 exists to say out loud |
| B13 | Revisit the banner URL host once this repository is public — `raw.githubusercontent.com` is fine then, and cheaper | claude | F81: the `github.com/.../blob/...?raw=true` URL is a private-repo workaround. It costs a redirect and resolves against the viewer's session; the raw host is a CDN and needs neither. Nothing is broken if it is left alone, so this is a cleanup and not a fix, and it is not actionable until the repository goes public |
| B14 | `claude.agent.meta` — one repository for what spans repositories: cross-cutting docs, plan files, the off-tree forensic anchors. Nothing enforcing; the view from above | claude | F82: recorded so it is a decision rather than a drift. The trigger as stated — four or more `claude.agent.*` repositories, or the first artifact that genuinely cannot live in any single one — is **already met on both halves**: six exist, and the images anchor `915be889` is held inside the repository it attests. It stays unstarted because a single file outside every repository anchors that hash as well as a seventh repository would, and costs nothing to keep. What is open is the judgement, not the count |

## the legacy image builder

Recorded here because it was measured during the cutover and cannot be fixed from this repository:
the file belongs to the image builder, and it was found while its images were being verified
read-only.

| # | Item | Owner | Why it is not done yet |
|---|---|---|---|
| B6 | Add `__pycache__` to `.dockerignore` | claude | F62: `.gitignore` carries it and `.dockerignore` does not, so `git status` is clean while the build context is not. Two honest agents on the same commit record different developer image ids, and the leash ships CPython bytecode compiled by a Windows host against a runtime it never uses |

## Closed by the copy

| # | Item | Closed because |
|---|---|---|
| B4 | Reword the policy repo's fourth `retire_when` condition so it does not parenthesise a grep | F68's subject was `docs/migration/migration.json`, which is not carried (F74). There is no migration manifest here to reword, and core is the result of that migration rather than a participant in it |
| B7 | Guard `tests/Trailers.Tests.ps1`'s pull-request range against being empty | F63's subject file is not carried (F78). Superseded by **B11**, which rebuilds the whole suite on synthetic repositories instead of patching one range |
