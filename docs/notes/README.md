# docs/notes

## What this is

Raw conversation notes, one file each, append-only.

`raw/` is the source of truth. `derived/` is regenerated from it and may be deleted and
rebuilt at any time. Nothing in `derived/` is written by hand.

## What it is not yet

Deferred on purpose, not forgotten. Each line names what would trigger adding it.

- **No receipt chain.** Added when a second reader has to trust a note it did not watch
  being written.
- **No required checks.** Added when volume makes a malformed note likely to slip in unseen.
- **No classification.** Added when volume shows which fields recur across notes.
- **No schema beyond the filename.** Added when a query comes up that nobody can answer
  from `raw/`.

## Branches

Notes accumulate on `feature/notes` and ride to `develop` by pull request whenever. Nothing
merges backward.

## Filename rule

`docs/notes/raw/YYYY-MM-DD-HHmm-<slug>.md`. The slug is lowercase, hyphens, no dots.

Write one with `scripts/New-Note.ps1 -Slug <slug>` and exactly one body source: `-Body <text>`,
`-BodyFile <path>`, or the body piped in.
