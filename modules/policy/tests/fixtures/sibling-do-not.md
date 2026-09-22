# Fixture docs/do-not.md — stands in for `../claude.build.fuzzer/docs/do-not.md`

Fixture for sandbox check 7, which parsed the sibling Fuzzer repository's `docs/do-not.md` and
asserted that at least one rule came back. There is no `../claude.build.fuzzer` in substrate and
Phase 2 is forbidden to reach for one, so a prohibition list in the same shape stands in for it.

This file is a parser input, not law. Nothing in substrate obeys it.

## Do not

- Do not import Ledger from the fuzzer.
- Never edit a recorded corpus case to make a red suite green.
- Do not edit `tests/sandbox/` fixtures that another suite is the oracle for.
- Do not commit anything under `.ledger/` except `.gitkeep`.
- Claude MUST NOT rewrite a pushed commit to repair a trailer.

## Why these lines and not a summary

The original asserted only that a real sibling `do-not.md` yielded at least one rule, which is a
low bar that a one-line file would clear. These five keep the bar where the sibling file put it:
the bullets carry four different law tokens (`Do not`, `Never`, `MUST NOT`), so pattern 1 fires
repeatedly; two of them pair a `do not edit` / `do not commit` prohibition with a `tests/` or
`.ledger/` path token, so pattern 4 fires and yields `path` rules at `halt` weight; and the first
mentions an import, so pattern 3 fires as well. A fixture that produced one rule from one pattern
would pass check 7 while testing a fraction of what check 7 walked over.
