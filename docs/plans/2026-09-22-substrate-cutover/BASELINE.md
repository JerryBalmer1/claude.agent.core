# BASELINE — the cutover pass counts

The README says substrate is done when image.builder's submodule points here and its
in-container suite is green **at the same pass count it had at cutover**. That count had
never been recorded. This file is the record. Phase 6 is measured against it.

Measured on 2026-09-21. Host pwsh 7.6.6, docker 29.5.3.

Generated from `baseline.json`. Do not edit by hand and do not regenerate: this file is
committed exactly once, in Phase 1, and nothing in Phases 2-6 touches it. A baseline that
moves is not a baseline.

## The exact command

```powershell
pwsh -NoProfile -File scripts/Measure-Baseline.ps1 `
    -Json docs/plans/2026-09-22-substrate-cutover/baseline.json `
    -Markdown docs/plans/2026-09-22-substrate-cutover/BASELINE.md
```

## Source pins

| Repository | Branch | HEAD | Dirty |
|---|---|---|---|
| `claude.agent.substrate` | `feature/cutover-baseline` | `7cd58cadaf84e6f2afc38c2505e32a7b53ca806f` | 14 |
| `claude.build.ledger` | `feature/grok-confession-record` | `d57938d1eed2b5df13435d7820826e50de30483d` | 0 |
| `claude.build.policy` | `main` | `3be10c446b8b4d7c38e392ff4e3657dec8a51e1b` | 0 |
| `claude.pwsh.image.builder` | `feature/oneshot-2026-09-21` | `e96bba8b1dd17cb7e1fc5439bfbf2fe2c057f68d` | 0 |

The suites measured below are **not** `claude.build.ledger` at HEAD. They are the tree
`claude.pwsh.image.builder` pins as its submodule:

| | |
|---|---|
| Submodule path | `vendor/claude.build.ledger` |
| Pinned commit | `ed9c9d79856b4590b64eb2f0229dee8775a903d5` |
| Pinned tree | `709145a43fbfd1d029e96c60a18d868e3c51c866` |
| `claude.build.ledger` HEAD | `d57938d1eed2b5df13435d7820826e50de30483d` |
| Pin equals that HEAD | **false** |

The pin is behind the sibling's HEAD, so **the pin is the baseline**, not HEAD. The suite
tree is cloned from the sibling and detached at the pin, and the measuring script asserts
the resulting tree object equals the vendored one before it runs anything.

## Images

| Tag | Image id | pwsh | Pester | `python` | `python3` |
|---|---|---|---|---|---|
| `claude.pwsh.image.leash:run-01` | `sha256:1716f8ab42c50b9349eb11c0a703cfdb8cef509c5d0fae1bd1918bbfaeb87cab` | 7.6.6 | 6.1.0 | `-` | - |
| `claude.pwsh.image.developer:run-01` | `sha256:6708943e90b067ba9b18e5c985ea337bd5eeed05aec758515756ad36f02be819` | 7.6.6 | 6.1.0 | `-` | Python 3.12.3 |

Both images are measured because they are not interchangeable. The snake is Python.

## `claude.pwsh.image.leash:run-01`

| Suite | Exit | Passed | Failed | Total | Status | Seconds | Count from |
|---|---|---|---|---|---|---|---|
| `continuity.ps1` | 0 | 77 | 0 | 77 | GREEN | 3.9 | `summary-checks` |
| `forensic_chain.ps1` | 0 | 28 | 0 | 28 | GREEN | 8.05 | `summary-checks` |
| `no_sabotage.ps1` | 0 | 22 | 0 | 22 | GREEN | 1.32 | `summary-covenant` |
| `hook_pre_tool.ps1` | 1 | 11 | 0 | 11 | ABORTED | 1.79 | `markers` |
| `fail_path.ps1` | 1 | 0 | 0 | 0 | SKIPPED | 1.37 | `none` |
| `fuzzer_import.ps1` | 1 | 0 | 0 | 0 | SKIPPED | 1.4 | `none` |
| `ledger_chain.ps1` | 1 | 0 | 0 | 0 | SKIPPED | 2.35 | `none` |

**3 suite(s) produced a count: 127 passed, 0 failed, 127 checks total.**

### Not counted in that total

Recorded, never omitted: "the suite did not run", "the suite died partway" and "the
suite has no checks" must not look the same in a table. `ABORTED` means the suite
passed everything it reached and then hit a terminating error before its own summary
line, so its count is a partial and is excluded from the total above.

| Suite | Exit | Status | Reached | Why |
|---|---|---|---|---|
| `fail_path.ps1` | 1 | SKIPPED | - | fail_path.ps1: You cannot call a method on a null-valued expression. |
| `fuzzer_import.ps1` | 1 | SKIPPED | - | fuzzer_import.ps1: Cannot bind argument to parameter 'Path' because it is an empty string. |
| `hook_pre_tool.ps1` | 1 | ABORTED | 11 check(s) | New-Fixture: /work/tests/sandbox/hook_pre_tool.ps1:230 -- 230 \|  $d2  = New-Fixture 'nonshell' |
| `ledger_chain.ps1` | 1 | SKIPPED | - | Invoke-LedgerForce: /work/examples/force_example.ps1:52 -- 52 \|  $result = Invoke-LedgerForce @forward ` |

## `claude.pwsh.image.developer:run-01`

| Suite | Exit | Passed | Failed | Total | Status | Seconds | Count from |
|---|---|---|---|---|---|---|---|
| `continuity.ps1` | 0 | 77 | 0 | 77 | GREEN | 3.24 | `summary-checks` |
| `forensic_chain.ps1` | 0 | 28 | 0 | 28 | GREEN | 7.96 | `summary-checks` |
| `no_sabotage.ps1` | 0 | 22 | 0 | 22 | GREEN | 1.34 | `summary-covenant` |
| `hook_pre_tool.ps1` | 1 | 11 | 0 | 11 | ABORTED | 1.87 | `markers` |
| `fail_path.ps1` | 1 | 0 | 0 | 0 | SKIPPED | 2.32 | `none` |
| `fuzzer_import.ps1` | 1 | 0 | 0 | 0 | SKIPPED | 1.42 | `none` |
| `ledger_chain.ps1` | 1 | 0 | 0 | 0 | SKIPPED | 2.21 | `none` |

**3 suite(s) produced a count: 127 passed, 0 failed, 127 checks total.**

### Not counted in that total

Recorded, never omitted: "the suite did not run", "the suite died partway" and "the
suite has no checks" must not look the same in a table. `ABORTED` means the suite
passed everything it reached and then hit a terminating error before its own summary
line, so its count is a partial and is excluded from the total above.

| Suite | Exit | Status | Reached | Why |
|---|---|---|---|---|
| `fail_path.ps1` | 1 | SKIPPED | - | fail_path.ps1: You cannot call a method on a null-valued expression. |
| `fuzzer_import.ps1` | 1 | SKIPPED | - | fuzzer_import.ps1: Cannot bind argument to parameter 'Path' because it is an empty string. |
| `hook_pre_tool.ps1` | 1 | ABORTED | 11 check(s) | New-Fixture: /work/tests/sandbox/hook_pre_tool.ps1:230 -- 230 \|  $d2  = New-Fixture 'nonshell' |
| `ledger_chain.ps1` | 1 | SKIPPED | - | Invoke-LedgerForce: /work/examples/force_example.ps1:52 -- 52 \|  $result = Invoke-LedgerForce @forward ` |

## Substrate's own starting Pester total

Pester 5.7.1, run by `scripts/ci/Invoke-Tests.ps1` in a clean worktree at `origin/develop`
(`7cd58cadaf84e6f2afc38c2505e32a7b53ca806f`) — deliberately not in the Phase 1 working tree, which already holds Phase 1's
own edits:

| Total | Passed | Failed | Skipped |
|---|---|---|---|
| **47** | 47 | 0 | 0 |

This is the **starting** total: the repository as it stood before Phase 1 changed
anything. Phase 1 itself ends higher, because it lands tests of its own, so Phase 2's
"the total went up by exactly 10" is measured against the END of Phase 1 and not
against 47. `FINDINGS.md` F15 carries both numbers and why they differ.

## What this file is not

It is not a claim that every suite above *should* be green. Several are red or unrunnable
in a container, and the reasons are in the tables and in `FINDINGS.md`. The baseline's job
is to say what was true on the measured date, so that Phase 6 can prove the cutover changed
nothing — including not changing the failures.
