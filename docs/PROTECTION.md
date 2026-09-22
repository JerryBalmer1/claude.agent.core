# PROTECTION

What was attempted, what GitHub answered, what enforces the policy instead, and how to change
the review mode later.

Measured against `claude.agent.core` on **2026-09-22T23:15:42Z**. This file was carried over from
`claude.agent.substrate` and every call in it was re-run against this repository rather than
copied across — a transcript inherited from another repo is a claim, not a measurement. BACKLOG
B12, FINDINGS F80.

## Tier

```
gh api user --jq .plan.name
free
```

`claude.agent.core` is **private** and the account is on the **free** plan. Branch protection and
rulesets are paid features for private repositories.

## What was attempted — once each, no retry loop

Three calls, each made exactly once. Record the 403 and move on rather than loop against the API.

### 1. Classic branch protection on `main`

```
gh api -X PUT repos/JerryBalmer1/claude.agent.core/branches/main/protection --input <payload>
```

Payload:

```json
{
  "required_status_checks": {
    "strict": true,
    "contexts": [
      "requires-header",
      "trailer-guard",
      "branch-flow",
      "generated-match-config",
      "pester",
      "forensic-verify"
    ]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null
}
```

Response, verbatim:

```
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#update-branch-protection","status":"403"}
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
```

### 2. Classic branch protection on `develop`

Same payload, same endpoint with `develop`. Response, verbatim:

```
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#update-branch-protection","status":"403"}
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
```

Substrate's copy of this file carried a caveat here: `develop` did not exist on origin when that
call was made, so the 403 could in principle have been standing in for a 404. **That confound is
gone.** `develop` existed on this repository's origin before this call was made — it was pushed
with `main` at birth and has had two merges since. The 403 is the tier refusing the feature
outright, on a branch that demonstrably exists.

### 3. Repository ruleset

```
gh api -X POST repos/JerryBalmer1/claude.agent.core/rulesets --input <payload>
```

A ruleset named `core-flow` targeting `refs/heads/main` and `refs/heads/develop` with `deletion`,
`non_fast_forward`, `pull_request` and `required_status_checks` rules naming the same six checks.
Response, verbatim:

```
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/repos/rules#create-a-repository-ruleset","status":"403"}
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
```

Reading them back is refused the same way, which is how any auditor can confirm the state is
genuinely absent rather than merely unrecorded:

```
gh api repos/JerryBalmer1/claude.agent.core/branches/main/protection
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#get-branch-protection","status":"403"}

gh api repos/JerryBalmer1/claude.agent.core/rulesets
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/repos/rules#get-all-repository-rulesets","status":"403"}
```

Five calls, five 403s, and the repository's settings were unchanged by all of them — measured
after, not assumed:

```json
{"deleteBranchOnMerge":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":false,"squashMergeAllowed":false}
```

## What enforces the policy instead

**CI is the enforcement.** Say plainly what that is and is not worth:

| | Branch protection would | This repository actually does |
|---|---|---|
| Red check blocks merge | Yes, GitHub refuses | No — automerge declines, but a human can still click Merge |
| Direct push to `main` | Blocked | **Not blocked.** `push-guard` notices afterwards and leaves a public red |
| Force-push to `main` | Blocked | **Not blocked** |
| Branch deletion | Blocked | **Not blocked** |
| Squash / rebase merge | Blockable | **Blocked**, by repository setting — see below |

So the honest summary: the flow is **enforced against automation and convention, not against a
determined human with push access**. Everyone with push access here is Jerry or an agent acting as
Jerry. The guards catch mistakes and drift; they do not resist an adversary, and nothing in this
repository should be read as claiming otherwise.

`push-guard` is the one control that operates after the fact rather than before it. It asserts two
parents and a `who:` trailer on every commit arriving on a long-lived branch, and it cannot refuse
anything — it can only make the arrival loud, dated and public. It is deliberately not in
`required_checks`, because a check that only fires on push events would deadlock a pull request
that is waiting on it.

### What is closed for free

Merge-method settings are **not** gated behind the paid tier, so one real gap is closed. Measured
state, read back rather than assumed:

```json
{"deleteBranchOnMerge":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":false,"squashMergeAllowed":false}
```

"Merge commits only, hashes are evidence" is enforced by GitHub itself here rather than by
goodwill. It reverses with one `gh repo edit`, so it is a lock and not a law — the law is in
`AGENTS.md`. If it is ever needed again:

```
gh repo edit --enable-squash-merge=false --enable-rebase-merge=false --enable-merge-commit=true
gh repo edit --delete-branch-on-merge --enable-auto-merge=false
```

GitHub's own auto-merge stays **off** — merging is done by `.github/workflows/automerge.yml`, so
the decision lives in a script that can be read and a config that can be changed.

## How to flip review mode later

`config/repo.json` here carries `"review": { "mode": "human" }`, so `automerge.yml` stands down and
a human merges. To flip it to `auto`, four steps, and the middle two are the point — nothing is
hand-edited twice.

1. Branch from `develop`:
   ```powershell
   git switch develop; git pull --ff-only; git switch -c feature/review-auto
   ```
2. Edit **only** `config/repo.json`:
   ```json
   "review": { "mode": "auto", "note": "<why, and what would flip it back>" }
   ```
3. Regenerate, or `generated-match-config` will go red:
   ```powershell
   pwsh -NoProfile -File scripts/Generate-Policy.ps1
   ```
   `docs/POLICY.md` and `.github/PULL_REQUEST_TEMPLATE.md` rewrite themselves to say the automerge
   workflow merges. That is the whole design: the prose cannot disagree with the behaviour.
4. Commit with a `who:` trailer, push, open a PR into `develop`.

**That pull request is still governed by the old mode** — automerge reads `review.mode` from the
**base** branch, not the head, so it stands down for this one and a human merges it. From the
moment it lands on `develop`, every subsequent PR is automerged. To flip back, do the same with
`"human"`.

## If the tier becomes Pro, or the repository becomes public

Re-run the three calls in "What was attempted" unchanged. They should then succeed, and:

- The six required checks become genuinely blocking rather than advisory.
- Direct and force pushes to `main` and `develop` become impossible rather than merely
  discouraged, and `push-guard` goes from being the control to being the backstop.
- The table above stops needing its second column.
- **FINDINGS F80 closes**, and with it the caveat that anything pinning a tag of this repository
  inherits an unprotected `main`.

Nothing in `config/repo.json`, the workflows or the check scripts has to change — the required
check names are already read from the config, which is where the `contexts` array in the
protection payload came from. This is BACKLOG **B12**.
