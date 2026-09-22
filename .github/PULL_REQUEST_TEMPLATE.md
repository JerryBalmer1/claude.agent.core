<!--
  GENERATED FILE - DO NOT EDIT BY HAND.
  Rendered from config/repo.json by scripts/Generate-Policy.ps1.
  CI check "generated-match-config" fails the build if this file and the config disagree.
-->

## What

<!-- One paragraph. What is different after this merges, and how would someone tell? -->

## How

<!-- The mechanism, not the intent. Which files changed, in what order, and what each one does. -->

## Verify

<!-- The exact commands a reader can run and the output they should see. Paste what you measured, not what you expected. -->

## Said vs did

<!-- Anything this pull request claims that it did not do, or did differently from the run order it came from. If there is nothing, say so in those words. -->

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
