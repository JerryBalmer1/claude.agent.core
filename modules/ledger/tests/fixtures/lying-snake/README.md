# The lying snake

A stub that answers `Invoke-LedgerForce` with a `result` event describing a run nobody asked
for. It exists to exercise `LedgerResultMismatch`, which `FINDINGS.md` F44 and F51 recorded as
the one error id in the module's pinned vocabulary with nothing behind it.

It runs on **both** platforms. Nothing here is skipped.

| File | What it is |
|---|---|
| `result-mismatch.ndjson` | one `result` event, `"mode": "live"`, whose `sha256` is the real hash of its own `output` |
| `lie.cmd` | the Windows stub: prints that file and exits 0, ignoring argv and stdin |
| `lie` | the non-Windows stub: same job, `#!/usr/bin/env pwsh`, mode `100755`, writing through `[Console]::Out.Write` |

`lie.cmd` is stored CRLF (`.gitattributes`), because a batch file is read by `cmd.exe` and not
by anything that tolerates bare LF. `lie`'s execute bit is carried in the tree by
`git update-index --chmod=+x`, and `ledger.Tests.ps1` asserts it rather than assuming it.

## Why two stubs, and why the non-Windows one has no extension

`ledger.psm1` resolves `-PythonPath` with
`Get-Command -Name $PythonPath -CommandType Application`. Everything below follows from that one
line, and all of it is asserted by `It`s next door rather than trusted to this file.

**A `.ps1` can never be the stub, on any platform.** It is an `ExternalScript`, not an
`Application`, execute bit or not — so `Get-Command -CommandType Application` does not return it,
and the force would die as `LedgerPythonMissing` without ever reaching the identity check. This is
why the non-Windows stub is `lie` and not the `lie.ps1` that step 6.6 Option A asked for.

**`pwsh -File` rejects a path without a `.ps1` extension — on Windows only.** A shebang hands the
interpreter the script path as an argument, so `#!/usr/bin/env pwsh` on `lie` resolves to
`pwsh /path/to/lie`. On Linux and macOS that runs. On Windows it exits 64 with *"does not have a
'.ps1' extension"*, and Windows has no shebang anyway — hence `lie.cmd`.

Those two facts do not overlap, so one mechanism cannot serve both platforms, and the
`$IsWindows` branch the run order asked for is real rather than decorative.

## The correction this fixture is built on

The first version of this directory shipped **only** `lie.cmd`, with the mismatch `It` skipped on
`ubuntu-latest` and a written claim that no PowerShell-interpreted stub could exist anywhere. That
claim was wrong. It generalised the Windows `-File` refusal to every platform, measured on a
Windows workstation and never on the gate — which is `FINDINGS.md` F26's lesson arriving from the
opposite direction, and F26 is cited in this suite's own header.

What caught it was the falsifier written alongside the wrong claim: an `It` asserting
`pwsh -File <extensionless>` exits non-zero, with *"if this ever exits 0, the Linux twin is
buildable and should be built"* as its `-Because`. It went red on the runner, exit 0, and the twin
was built. F67 records the error and the correction together.

## Why `lie` embeds its payload instead of reading the file next to it

**A shebang-invoked script has no `$PSScriptRoot`.** Measured on `ubuntu-latest`: when the kernel
resolves this file's `#!/usr/bin/env pwsh`, pwsh runs the script with `$PSScriptRoot` *and*
`$PSCommandPath` both **empty**, so there is no way for it to locate a file sitting beside itself.
`lie.cmd` has no such problem — `%~dp0` is the batch file's own directory and cmd.exe always knows
it.

That cost two CI runs, and the first one is the instructive half:

| Run | Symptom | What it actually was |
|---|---|---|
| 1 | `LedgerNoResult` — *"Snake exited 0 but emitted no result event"* | `Join-Path ''` failed, the default `$ErrorActionPreference` swallowed it to stderr, the script exited 0 with empty stdout |
| 2 | `Split-Path: Cannot bind argument to parameter 'Path' it is an empty string` | the same empty `$PSScriptRoot`, now **loud** |

The difference between those two rows is the whole lesson. Run 1 reported a fact about the module
(*the snake said nothing*) that was true and useless — it cannot distinguish a broken stub from a
broken module. Run 2 named the file, the line and the variable, because of two changes made
between them:

- **`$ErrorActionPreference = 'Stop'`** in the stub, so a failure exits non-zero and arrives as
  `LedgerSnakeFailed` carrying the reason.
- **An `It` that runs the stub directly**, with the argv shape and the stdin the module uses,
  asserting exit 0 and exactly one line. It prints the stub's actual output in its `-Because`.

`[Console]::Out.Write` stays, for the reason it was added: no output formatter in the path, no
wrapping at the host's idea of a console width, no extra newline.

**`result-mismatch.ndjson` is still the single source of truth.** `lie.cmd` prints it; `lie`
carries a copy; and the `It` that runs `lie` asserts its output is byte-equal to that file's one
line, so the copy cannot drift without going red.
