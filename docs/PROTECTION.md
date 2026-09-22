# PROTECTION

What was attempted, what GitHub answered, what enforces the policy instead, and how to change
the review mode later.

## Tier

```
gh api user --jq .plan.name
free
```

`claude.agent.substrate` is **private** and the account is on the **free** plan. Branch
protection and rulesets are paid features for private repositories.

## What was attempted — once each, no retry loop

Three calls, each made exactly once. The run order says to record a 403 and move on rather than
loop against the API, and that is what happened.

### 1. Classic branch protection on `main`

```
gh api -X PUT repos/JerryBalmer1/claude.agent.substrate/branches/main/protection --input <payload>
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
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#update-branch-protection","status":"403"}
```

### 2. Classic branch protection on `develop`

Same payload, same endpoint with `develop`. Response, verbatim:

```
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/branches/branch-protection#update-branch-protection","status":"403"}
```

Note: `develop` did not exist on origin at the time of this call — it is created in step 7. The
403 is the tier refusing the feature outright, not a 404 for a missing branch, so the answer
would have been the same either way. This is recorded rather than glossed over.

### 3. Repository ruleset

```
gh api -X POST repos/JerryBalmer1/claude.agent.substrate/rulesets --input <payload>
```

A ruleset targeting `refs/heads/main` and `refs/heads/develop` with `deletion`,
`non_fast_forward`, `pull_request` and `required_status_checks` rules naming the same six
checks. Response, verbatim:

```
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
{"message":"Upgrade to GitHub Pro or make this repository public to enable this feature.","documentation_url":"https://docs.github.com/rest/repos/rules#create-a-repository-ruleset","status":"403"}
```

Reading them back is refused the same way, which is how `verify.ps1` and any auditor can confirm
the state is genuinely absent rather than merely unrecorded:

```
gh api repos/JerryBalmer1/claude.agent.substrate/branches/main/protection
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
gh api repos/JerryBalmer1/claude.agent.substrate/rulesets
gh: Upgrade to GitHub Pro or make this repository public to enable this feature. (HTTP 403)
```

## What enforces the policy instead

**CI is the enforcement.** Say plainly what that is and is not worth:

| | Branch protection would | CI actually does |
|---|---|---|
| Red check blocks merge | Yes, GitHub refuses | No — automerge declines, but a human can still click Merge |
| Direct push to `main` | Blocked | **Not blocked** |
| Force-push to `main` | Blocked | **Not blocked** |
| Branch deletion | Blocked | **Not blocked** |
| Squash / rebase merge | Blockable | Blocked, by repository setting (see below) |

So the honest summary: the flow is **enforced against automation and convention, not against a
determined human with push access**. Everyone with push access here is Jerry or an agent acting
as Jerry. The guards catch mistakes and drift; they do not resist an adversary, and nothing in
this repo should be read as claiming otherwise.

### What was closed for free

Merge-method settings are **not** gated behind the paid tier, so one real gap was closed:

```
gh repo edit --enable-squash-merge=false --enable-rebase-merge=false --enable-merge-commit=true
```

Resulting state:

```json
{"deleteBranchOnMerge":true,"mergeCommitAllowed":true,"rebaseMergeAllowed":false,"squashMergeAllowed":false}
```

"Merge commits only, hashes are evidence" is now enforced by GitHub itself rather than by
goodwill. This went beyond what the run order asked for and is recorded as such in FINDINGS.md.
It reverses with one `gh repo edit`.

Also applied, as the run order specified:

```
gh repo edit --delete-branch-on-merge --enable-auto-merge=false
```

GitHub's own auto-merge stays **off** — merging is done by `.github/workflows/automerge.yml`, so
that the decision lives in a script that can be read and a config that can be changed.

## How to flip review mode to "human" later

Four steps, and the middle two are the point — nothing is hand-edited twice.

1. Branch from `develop`:
   ```powershell
   git switch develop; git pull --ff-only; git switch -c feature/review-human
   ```
2. Edit **only** `config/repo.json`:
   ```json
   "review": { "mode": "human", "note": "<why, and what would flip it back>" }
   ```
3. Regenerate, or `generated-match-config` will go red:
   ```powershell
   pwsh -NoProfile -File scripts/Generate-Policy.ps1
   ```
   `docs/POLICY.md` and `.github/PULL_REQUEST_TEMPLATE.md` rewrite themselves to say a human
   merges. That is the whole design: the prose cannot disagree with the behaviour.
4. Commit with a `who:` trailer, push, open a PR into `develop`.

**This pull request is still merged by automation** — automerge reads `review.mode` from the PR
head, sees `human`, and... stands down, leaving this one for a human to merge. Either outcome is
fine; what matters is that from the moment it lands on `develop`, every subsequent PR is
human-merged.

To flip back, do the same with `"auto"`.

## If the tier becomes Pro

Re-run the three calls in the "What was attempted" section unchanged. They should then succeed,
and:

- The six required checks become genuinely blocking rather than advisory.
- Direct and force pushes to `main` and `develop` become impossible rather than merely
  discouraged.
- The table above stops needing its second column.

Nothing in `config/repo.json`, the workflows or the check scripts has to change — the required
check names are already read from the config, which is where the `contexts` array in the
protection payload came from.
