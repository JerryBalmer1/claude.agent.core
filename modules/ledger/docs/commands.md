# Command reference

Four exported functions and one alias, from
[../src/ledger/Ledger.psd1](../src/ledger/Ledger.psd1):

```powershell
FunctionsToExport = @('Invoke-LedgerForce', 'Get-LedgerStatus', 'Get-LedgerVerify', 'Get-LedgerEntry')
AliasesToExport   = @('ledger-force')
```

Import the module by its manifest:

```powershell
Import-Module ./src/ledger/Ledger.psd1 -Force
```

## Conventions that apply to all four

**Pipeline behaviour: none of them accept pipeline input.** No parameter on any exported command
declares `ValueFromPipeline` or `ValueFromPipelineByPropertyName`. Pass arguments by name or
position. All four *emit* objects to the pipeline normally, so they compose downstream
(`Get-LedgerEntry | Where-Object ...`).

**`-Verbose` and `-Debug`** are supported everywhere (`[CmdletBinding()]` on all four). Two
practical notes:

- Module functions do not inherit the caller's preference variables. When calling from a script,
  forward them explicitly — this is what
  [../examples/force_example.ps1](../examples/force_example.ps1) does:

  ```powershell
  $forward = @{ Verbose = ($VerbosePreference -eq 'Continue'); Debug = ($DebugPreference -eq 'Continue') }
  Invoke-LedgerForce @forward -Prompt '...'
  ```

- `-Debug` prompts for confirmation by default in PowerShell. For non-interactive runs, set
  `$DebugPreference = 'Continue'` instead of passing the switch.

**`-LedgerPath` resolution** (shared by `Invoke-LedgerForce`, `Get-LedgerVerify`,
`Get-LedgerEntry`): omitted or blank means the default, `.ledger/ledger.jsonl` under the **repo
root**, computed from the module's own location (`src/ledger/../..`) — so it is the same file
regardless of your current directory. An absolute path is used as given. A relative path resolves
against the **caller's** filesystem location, not the module's.

**Errors are terminating.** Every ErrorId below is thrown via `ThrowTerminatingError`, so `try/catch`
works without `-ErrorAction Stop`. Full list in
[theory-of-operation.md](theory-of-operation.md#9-errorids).

---

## Invoke-LedgerForce

Force a model response through a validator, retrying with feedback until it passes or the cap is
hit; on success, append one receipt.

### Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `-Prompt` | string | — | **Mandatory**, position 0. Non-empty. Sent on stdin, not argv |
| `-Validator` | string | `has_function_def` | One of `contains`, `has_function_def`, `is_json`, `matches`, `non_empty` |
| `-ValidatorArg` | string | — | Required by `contains` and `matches`; rejected by the other three |
| `-MaxRetries` | int | `5` | Range 1–20. The cap, not the extra tries |
| `-Model` | string | `claude-sonnet-4-5` | Recorded in the receipt verbatim |
| `-System` | string | — | System prompt. Omitted from the payload if not supplied |
| `-Mode` | string | `dry-run` | `dry-run` or `live` |
| `-MockResponse` | string[] | — | Scripted dry-run responses; the last repeats when exhausted |
| `-MaxTokens` | int | `4096` | Range 1–200000 |
| `-BaseDelay` | double | `1.0` | Range 0–60. Exponential backoff base. Forced to `0` in dry-run |
| `-PythonPath` | string | `python` | Must resolve to an application on `PATH` |
| `-LedgerPath` | string | repo `.ledger/ledger.jsonl` | Where the receipt is appended |
| `-SkipLedger` | switch | off | Accept the output, write no receipt |
| `-Policy` | switch | off | Run one `claude.build.inspector` policy evaluation **before** the snake. See [Policy pass-through](#policy-pass-through) |
| `-Halt` | switch | off | Requires `-Policy`. Let a halt-weight finding terminate the force with Inspector's own `InspectorPolicyHalt` |
| `-PolicyPath` | string | repo root | Directory Inspector evaluates. Requires `-Policy` |

### Returns

A single `Ledger.ForceResult`:

| Property | Type | |
|---|---|---|
| `Output` | string | The accepted text |
| `Attempts` | int | Which attempt was accepted |
| `Sha256` | string | SHA-256 of the accepted output's UTF-8 bytes |
| `Validator` | string | Validator that accepted it |
| `Reason` | string | The validator's pass reason |
| `Model` | string | |
| `Mode` | string | `dry-run` or `live` |
| `LedgerPath` | string | Absolute path written to; `$null` under `-SkipLedger` |
| `LedgerSelf` | string | This receipt's `self` hash; `$null` under `-SkipLedger` |
| `PolicyEvaluated` | bool | `$true` only when `-Policy` ran **and** Inspector found a policy module. `$false` otherwise |
| `PolicyRuleCount` | int | Rules the parser returned for `PolicyPath`. `0` without `-Policy` |
| `PolicyHaltCount` | int | Inspector findings that start with `policy halt:`. `0` without `-Policy` |
| `PolicyPath` | string | Directory that was evaluated; `''` without `-Policy` |

The last four are additive, always present, and `false / 0 / 0 / ''` when `-Policy` was not passed.
**They do not reach the receipt.** The on-disk record is schema v1 — exactly eight keys — and every
hash already written depends on that set staying frozen. The policy verdict lives on the returned
object; the receipt it points at (`LedgerSelf`) is byte-identical in shape to every receipt before it.

### Throws

`LedgerPythonMissing`, `LedgerCliMissing`, `LedgerMissingApiKey`, `LedgerSnakeFailed`,
`LedgerNoResult`, `LedgerResultMismatch`, `LedgerOutputHashMismatch`, `LedgerAppendFailed`,
`LedgerBadSettings`.

`LedgerResultMismatch` is the newest of them. The snake's `result` event echoes back the mode,
validator and model it was told to use, and an echo that differs from the invocation terminates the
force before any receipt is written — case-sensitively, because a receipt is a literal record. A
field the event leaves out is not a mismatch. `-Model` is the one exemption: name a model and the
echo must match it; omit it and nothing is compared, with the receipt recording the parameter default
rather than whatever the snake echoed. **`attempts` is not verified** — PowerShell never watched the
retry loop, so it records the reported number and claims nothing more about it.

Under `-Policy`, Inspector's own errors — `InspectorPolicyHalt`, `InspectorPathNotFound`,
`InspectorBadSettings` — pass through **unwrapped** and keep their own ErrorId. Ledger does not
swallow them into a generic error and does not re-raise them under a Ledger id.

### Example

```powershell
Import-Module ./src/ledger/Ledger.psd1 -Force

$r = Invoke-LedgerForce -Verbose `
    -Prompt 'Write a Python function add(a, b) that returns a + b. Code only.' `
    -System 'You are a code generator. Output only code, no explanation.' `
    -Validator 'has_function_def' `
    -MaxRetries 5 `
    -Mode 'dry-run'

$r.Output
$r | Format-List Attempts, Sha256, LedgerPath, LedgerSelf
```

With a validator that takes an argument:

```powershell
Invoke-LedgerForce -Prompt 'Return a JSON object with a name field.' `
    -Validator 'matches' -ValidatorArg '"name"\s*:' -Mode dry-run `
    -MockResponse '{"name":"ok"}'
```

### Policy pass-through

Both switches are **off by default**, and with neither of them the force behaves exactly as it did
in v0.1: no inspect, no policy module, no throw on a halt-weight rule.

`-Policy` runs **exactly one** `Invoke-ClaudeInspector -Path <PolicyPath> -Policy`, before Python is
spawned and before any receipt is written, and copies three counts onto the result. Ledger imports
`claude.build.inspector` lazily for this and nothing else. It never imports `claude.build.policy`:
Ledger talks to Inspector, Inspector talks to the parser.

```powershell
# Observe: what does this project's written law say, and does the allow list contradict it?
$r = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Mode dry-run -Policy -Verbose
$r | Format-List PolicyEvaluated, PolicyRuleCount, PolicyHaltCount, PolicyPath

# Gate: a halt-weight finding stops the force before a model is called.
Invoke-LedgerForce -Prompt 'Write add(a, b).' -Mode dry-run -Policy -Halt
# InspectorPolicyHalt,Invoke-ClaudeInspector
```

Three things this does **not** do:

- **It does not block a Claude Code agent.** `-Halt` fails the PowerShell pipeline that called it.
  An agent already running is unaffected. If a finding matters, a human changes the settings.
- **It does not write settings and does not install hooks.** Inspector is read-only and so is this.
- **It does not add a second fail-open path.** A missing policy module is Inspector's fail-open,
  already implemented there. A missing *Inspector* is Ledger's only concession: `-Policy` warns and
  the force continues exactly as if the switch had not been passed.

---

## Get-LedgerVerify

Walk the receipt file and prove the hash chain is intact.

### Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `-LedgerPath` | string | repo `.ledger/ledger.jsonl` | Position 0 |

### Returns

A single `Ledger.VerifyResult`. **A returned object always means the chain held** — failure is a
throw, not an `Ok = $false`.

| Property | Type | |
|---|---|---|
| `Path` | string | Absolute path verified |
| `Count` | int | Records verified. Blank lines are skipped and not counted |
| `Ok` | bool | Always `$true` when the call returns |
| `FirstTs` | string | `ts` of the first record; `$null` if the file is empty |
| `LastTs` | string | `ts` of the last record; `$null` if the file is empty |
| `LastSelf` | string | `self` of the last record; `$null` if the file is empty |

An existing-but-empty file is not an error: it returns `Count = 0`, `Ok = $true`, and `$null`
timestamps. A **missing** file is an error.

### Throws

`LedgerFileMissing`, `LedgerCorruptLine`, `LedgerBadRecord`, `LedgerBadSelf`, `LedgerBrokenChain`.

### Example

```powershell
Import-Module ./src/ledger/Ledger.psd1 -Force
Get-LedgerVerify -Verbose | Format-List

# Verify a copy without touching the real one
Get-LedgerVerify -LedgerPath ./tests/sandbox/copy.jsonl
```

---

## Get-LedgerEntry

Read receipt lines as objects, oldest first.

### Parameters

| Parameter | Type | Default | Notes |
|---|---|---|---|
| `-LedgerPath` | string | repo `.ledger/ledger.jsonl` | Position 0 |
| `-Last` | int | `10` | Range 0–100000. **`0` returns every record** |

### Returns

Zero or more `Ledger.Entry` objects **in file order** (oldest first), being the last `-Last`
records. Every line is validated on the way out, so a corrupt record throws rather than being
handed back as data.

| Property | Type | |
|---|---|---|
| `Line` | int | 1-based line number in the file |
| `Ts` | string | |
| `Attempt` | int | |
| `Validator` | string | |
| `Mode` | string | |
| `Model` | string | |
| `Sha256` | string | Hash of the accepted output |
| `Prev` | string | |
| `Self` | string | |

Note it emits nothing at all for an empty file, so guard `$_[0]` style indexing.

### Throws

Same set as `Get-LedgerVerify`, minus `LedgerBrokenChain` — it validates each record but does not
check links between them. Use `Get-LedgerVerify` for chain integrity.

### Example

```powershell
Get-LedgerEntry -Last 5 | Format-Table Line, Ts, Attempt, Mode, Sha256

# Confirm the last two records link
$p = @(Get-LedgerEntry -Last 2)
$p[1].Prev -eq $p[0].Self      # True

# Everything
Get-LedgerEntry -Last 0 | Measure-Object | Select-Object Count
```

---

## Get-LedgerStatus

Report where the snake lives and whether it can run. Takes **no parameters** beyond the common
ones. Touches nothing and writes nothing.

### Returns

A single `Ledger.Status`:

| Property | Type | |
|---|---|---|
| `Protocol` | int | NDJSON protocol version the module speaks (`1`) |
| `SnakeCli` | string | Absolute path to `cli.py` |
| `SnakePresent` | bool | Whether that file exists |
| `Python` | string | Resolved `python` path, or `$null` if not on `PATH` |
| `ApiKeyPresent` | bool | Whether `ANTHROPIC_API_KEY` is set and non-whitespace. **The key itself is never returned** |
| `PSVersion` | string | Running PowerShell version |

### Throws

Nothing. A missing Python or absent key is reported as data, not raised.

### Example

```powershell
Import-Module ./src/ledger/Ledger.psd1 -Force
Get-LedgerStatus | Format-List
```

```
Protocol      : 1
SnakeCli      : C:\__Code\____Claude.Build\claude.build.ledger\src\ledger\python\cli.py
SnakePresent  : True
Python        : C:\Python310\python.exe
ApiKeyPresent : False
PSVersion     : 7.6.6
```

---

## ledger-force (alias)

`ledger-force` resolves to `Invoke-LedgerForce`. Same parameters, same behaviour, same return
type — it is a plain alias, not a wrapper.

```powershell
ledger-force -Prompt 'Write add(a, b).' -Mode dry-run -Verbose
```

Prefer the full name in scripts; aliases are for the prompt.
