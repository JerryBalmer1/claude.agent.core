# Do not

The short version, in plain language. Each line below is a law this repo's own parser extracts when you run
`Get-PolicyRules -Path .` — the file is both documentation and a test fixture.

- Do not import Ledger.
- Do not call `Invoke-LedgerForce`.
- Do not write `.ledger/`.
- Do not implement `opa eval`.
- Do not talk to the network.
- Do not commit secrets.
- Do not edit `src/`, `tests/`, or `examples/` without explicit instruction.

The long version, with the reason and the correct alternative, follows.

## Do not import Ledger

This module imports nobody. Ledger and Fuzzer do not import it; Inspector v0.2 does, but only under `-Policy`,
and only in one direction — lazily, fail-open, never in `RequiredModules`. `claude.build.ledger` imports
`claude.build.fuzzer` and `claude.build.inspector`; neither of those imports Ledger; and `claude.build.policy`
imports none of them. A parser that needs the thing it describes cannot be used to check it.

**Instead:** take a path and return objects. Whoever wants the rules enforced can import this module later and
decide what to do with them. That decision is not made here.

## Do not call `Invoke-LedgerForce`

That is Ledger's cmdlet surface. This module runs no model, forces no output through a validator, and retries
nothing. It reads markdown and returns rows.

## Do not write `.ledger/`

There is no receipt chain here and there must not be one. `Hash` on a `PolicyRule` is the SHA-256 of the rule's
own content — `Id|Kind|Basis|Weight|Verb`. It is not a `self`, not a `prev`, and it links to nothing. Calling it
a receipt invents a guarantee this module does not make.

## Do not implement `opa eval`

No OPA, no Rego, no policy engine, no shelling out to a binary. v0 compiles markdown into objects and stops.
Evaluation is a later decision and a different surface.

**Instead:** emit the rule with `Basis` set to something checkable, or to `prose` when it is not yet checkable,
and let the caller decide.

## Do not talk to the network

No HTTP, no API key, no Anthropic SDK, no MCP, no telemetry, no update check. An air-gapped machine runs this
module identically. Nothing here needs a key, so nothing here reads one.

## Do not commit secrets

No API keys, tokens, `.env` files, or machine-specific paths in the tree. Nothing in v0 needs one.

## Do not edit `src/`, `tests/`, or `examples/` without explicit instruction

`AGENTS.md`, `prompts/`, and `docs/` are free to edit. Code and tests are not: they change only when the user
says so in the current session. Commit only when told. Never amend. Never force-push.

## Do not widen the heuristic quietly

The four v0 patterns are frozen. Adding a fifth, loosening a token list, or switching to a markdown AST changes
every `Id` and every `Hash` downstream. That is a version bump and an explicit instruction, not a tweak.

## Do not run `.ps1` under Git Bash

PowerShell scripts are run by PowerShell:

```powershell
pwsh -NoProfile -File <short-repo-relative-path>
```

Use short repo-relative paths. Long scratchpad paths hit `ENAMETOOLONG`.

## Do not delete `.gitkeep`

`tests/sandbox/.gitkeep` keeps the sandbox directory in a fresh clone. The suite writes its temp files to
`$env:TEMP` and deletes them; it never writes under the repo.
