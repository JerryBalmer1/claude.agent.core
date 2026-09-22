# policy

**What it is.** A markdown-to-`PolicyRule` parser: one exported function, `Get-PolicyRules`, reads
`AGENTS.md`, `docs/do-not.md` and `CLAUDE.md` at a path and emits one content-hashed rule per
extracted line.

**What it is not.** It parses, never enforces — no OPA, no enforcement, no network, no receipts,
nothing written.

**Copied from.** `claude.build.policy@3be10c446b8b4d7c38e392ff4e3657dec8a51e1b`, byte-identical, in
`f676d72`; `src/claude.build.policy/**` became `modules/policy/**`.

**Renamed in.** The v0.1.0 release phase. `claude.build.policy.psd1` / `.psm1` became `policy.psd1`
/ `policy.psm1`, so the import path is `modules/policy/policy.psd1` and the module name is `policy`
— bare, like `ledger` and `plans`. `docs/plans/2026-09-22-substrate-cutover/FINDINGS.md` F22
records why Phase 2 declined the rename; F47 records the decision that took it and what it cost.

**One copied byte was not changed by the rename.** `policy.psm1` is the byte-identical copy and
still hashes to blob `72dc1ec6010897d56cb2ca3aa10351393b72d5ef`, so the objects it emits still
carry `PSTypeName = 'claude.build.policy.PolicyRule'` and its `$script:SiblingNames` list still
names the four `claude.build.*` repositories. Those are the parser's subject matter and its
provenance, not this module's identity. The manifest is the only copied file this repository has
edited, and F47 shows the one line.