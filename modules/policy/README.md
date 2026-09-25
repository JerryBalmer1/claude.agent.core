# policy

**What it is.** A markdown-to-`PolicyRule` parser, and a judge of one tool call against those
rules. `Get-PolicyRules` reads `AGENTS.md`, `docs/do-not.md` and `CLAUDE.md` at a path and emits
one content-hashed rule per extracted line. `Test-PolicyAction` (`evaluate.psm1`, D013) takes the
rules and a tool call (`tool_name`, `tool_input`) and returns `allow` or `deny`, the matched rule
ids and how many of them are halt-weight.

**What it is not.** It judges and does not stop anything. No OPA, no network, no receipts, and
nothing written. A caller that ignores `deny` isn't refused here. Only `write` and `import` rules
can match. Law sentences (verb `none`) can't, and a shell command that writes a file isn't parsed
(D013).

**The manifest's two files.** `evaluate.psm1` is the `RootModule` and `policy.psm1` its
`NestedModules` entry. The reason is below: `policy.psm1` exports `Get-PolicyRules` alone, and a
root that does that would hide the evaluator.

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
edited. F47 shows the rename line, and D013 the `RootModule`, `NestedModules`, `FunctionsToExport`
and `Description` lines.