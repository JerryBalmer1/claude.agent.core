# Fixture AGENTS.md — stands in for `../claude.build.ledger/AGENTS.md`

Fixture for sandbox check 6, which parsed the sibling Ledger repository's `AGENTS.md` and asserted
that at least one `module` or `law` rule came back mentioning an import or Ledger. There is no
`../claude.build.ledger` in substrate and Phase 2 is forbidden to reach for one, so the sibling's
**import law is restated here in its own shape** instead of being read across a repo boundary.

This file is a parser input, not law. Nothing in substrate obeys it.

## Import law

`claude.build.ledger` imports `claude.build.fuzzer` and `claude.build.inspector`. Neither imports Ledger.

`claude.build.policy` imports nothing at all.

- Do not import Ledger from a sibling module.
- Never import `claude.build.policy` from Ledger; Ledger talks to Inspector and Inspector talks to the parser.

## Why these lines and not a summary

Check 6 exercised three parser paths at once, and a fixture that only said "import" would exercise
one. The bullets above are bullets carrying a law token, so pattern 1 fires and yields `law` rules
at `halt` weight; every line mentions `import` alongside a repo name, so pattern 3 fires and yields
`module` rules; and `Ledger` appears bare, not only as the tail of `claude.build.ledger`, so the
bare-name branch fires too. That is what the original measured against a real sibling file.
