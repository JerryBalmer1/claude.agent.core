# ledger

An append-only, hash-chained receipt file, and a Python retry loop that produces the things it
records. Copied from `claude.build.ledger@d57938d` and **unchanged in behaviour** — not as a
claim, as arithmetic: `ledger.psm1` is byte-identical to the source, and
`tests/ledger.Tests.ps1` recomputes its git blob sha from the bytes on disk on every run.

## What it is

Four exported functions and one alias, exactly as the source module exported them:

| | |
|---|---|
| `Invoke-LedgerForce` | Spawn the Python snake, validate its output, retry on failure, append one receipt for the output that passed. Aliased `ledger-force`. |
| `Get-LedgerVerify` | Walk the chain and prove it. Any break is a terminating error, so a returned object always means `Ok`. |
| `Get-LedgerEntry` | Read records back as objects, oldest first, each one validated on the way out. |
| `Get-LedgerStatus` | Where the snake is and whether it can run. |

A record is eight keys — `ts, attempt, validator, mode, model, sha256, prev, self` — in that
order, and the order is the schema. `self` is the sha256 of the record's own canonical payload;
`prev` is the previous record's `self`, and it lives *inside* the hashed payload, which is why
a forgery that re-hashes its own record still breaks at the next link.

The compute engine is Python (`python/`), under the one permission
`config/repo.json` → `runtimes.python.allowed_under` grants. The dry-run path constructs no
client and needs no SDK; `requirements.txt` is here for the live path and is never installed by
CI.

## What it is not

**It does not enforce anything.** It records what happened. Nothing here writes settings,
installs hooks, or stops an agent.

**It is not a second chain.** `.continuity/forensic.jsonl` — eight *different* keys, written by
`scripts/forensic.ps1` — is the forensic record of who did what to the law. This is the receipt
chain. A record from one cannot be verified by the other, and neither is a place to put the
other's rows.

**It is not `LedgerReceipt.ps1`.** image.builder ships a file by a similar name that is a
weaker second implementation of the same idea: `ConvertTo-Json` on both the write and the
verify path, `prev` hashed twice, no lock across the tail read, and a silent carry-on over an
unparseable tail. It is a boot-time hook rail, its destination is `claude.agent.images`, and a
test in this module fails if it ever appears under `modules/`. FINDINGS F29.

## The chain's two rules, and how they are held

**One writer, or the tail is a race.** `Add-LedgerRecord` opens the file once with
`FileShare.None` and holds that one handle across *both* the tail read that learns `prev` *and*
the append. Four concurrent `pwsh` processes appending twenty records land twenty distinct
records and a chain that still verifies — asserted, with the set of hashes compared, not just
the count.

**No `ConvertTo-Json`, `ConvertFrom-Json` or `Test-Json` on the chain.** The canonical bytes
feed a hash, so they must be reproducible from any language and immune to serializer quirks;
`ConvertFrom-Json` alone would turn an ISO-8601 `ts` into a `[datetime]` and every hash after it
would fail. The bytes are assembled by hand and read back with `System.Text.Json`.

The ban is on the **chain**, not on the module, and those are different claims. `ledger.psm1`
does call `ConvertTo-Json` and `ConvertFrom-Json` — three times, all inside `Invoke-LedgerForce`,
on the subprocess protocol it speaks to Python. Nothing hashes those bytes. The suite asserts
both halves: no chain function calls any of the three, and the three calls that exist are all in
`Invoke-LedgerForce`. It asserts them by **parsing**, not by grepping, because a grep goes red on
the comment that explains the rule (FINDINGS F32).

## Renamed from

`claude.build.ledger/src/ledger/Ledger.psd1` and `Ledger.psm1`. The module name in this repo is
`ledger`, bare, matching `policy` and `plans`. The source repository's own CLAUDE.md says the
module name there stays `Ledger`; that instruction governs that repository, and it is why the
rename happened here and not there. The rename is case-only and the copy landed at its final
name in one step — a case-only `git mv` on a case-insensitive filesystem is a way to lose a byte
for no gain. `ledger.psd1`'s `RootModule` is the only line that differs from the source manifest,
and a test proves that by reversing the change and watching the source blob sha come back.

## Provenance, and what does not run here

`tests/sandbox/` holds three suites copied byte-identical from the source repository:
`ledger_chain.ps1` (ten tests), `forensic_chain.ps1` (eight sections), `fail_path.ps1`. **They
are provenance, not a suite.** Each resolves the module through `../../src/ledger/`, which is
the source repository's layout; `ledger_chain.ps1` additionally runs
`examples/force_example.ps1`, which was not copied. They are kept because they are what the
Pester port was written from, and a reader who wants to check the port against its oracle needs
the oracle in the tree.

`docs/` holds two documents from the source repository, byte-identical: `theory-of-operation.md`
and `commands.md`. Any path they name is that repository's layout.

## Running it

```powershell
Import-Module ./modules/ledger/ledger.psd1 -Force
Invoke-LedgerForce -Prompt 'Write a Python function add(a, b).' -Mode dry-run `
    -LedgerPath ./scratch.jsonl -Verbose
Get-LedgerVerify -LedgerPath ./scratch.jsonl
```

With no `-LedgerPath`, the default resolves to `<repo>/.ledger/ledger.jsonl`. That path is
gitignored: a receipt chain is evidence about a run on somebody's workstation, not a repository
artifact.

```powershell
pwsh -NoProfile -File scripts/ci/Invoke-Tests.ps1     # the whole repo, this module included
```
