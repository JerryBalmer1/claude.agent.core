<!--
  GENERATED FILE - DO NOT EDIT BY HAND.
  Rendered from config/repo.json by scripts/Generate-Policy.ps1.
  CI check "generated-match-config" fails the build if this file and the config disagree.
-->

## What

<!-- What is true after this merges, in prose. Not a list of what you did -- what is different, and how would someone tell? -->

<details open>
<summary><strong>How</strong></summary>

<!-- One block per commit, and repeat this block per commit: the sha first, then every file touched as a sha-pinned permalink, then what changed and why. The pr-body-links check rejects a bare path, a URL on a branch name instead of a 40-hex sha, and a line suffix that does not match the #L fragment. -->

</details>

## Why

<!-- The control this serves, or the constraint it removes. Short. -->

<details>
<summary><strong>Verify</strong></summary>

<!-- The check table, pester counts, and the forensic tip. Paste what you measured, not what you expected. -->

</details>

## Base branch

Tick exactly one. Any other pair fails the `branch-flow` check.

- [ ] `feature/*` -> `develop`
- [ ] `develop` -> `main`

## Trailer

- [ ] Every commit ends with a `who:` trailer as its last line
- [ ] The value is one of: `claude`

## Merge

- [ ] This will land as a **merge commit** - not a squash, not a rebase

## Checks that must be green

- [ ] `requires-header`
- [ ] `trailer-guard`
- [ ] `branch-flow`
- [ ] `generated-match-config`
- [ ] `pester`
- [ ] `forensic-verify`

`review.mode` is `human`: the automerge workflow stands down. A human merges this.

## Wall

- [ ] No module code under `src/` or `modules/` unless a run order says so
- [ ] No sibling repository was touched
- [ ] No container surface was added - substrate is never a container
- [ ] No `.py` outside `modules/ledger/python/`
