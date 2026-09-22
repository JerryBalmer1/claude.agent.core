# Theory of operation

The contract between the two halves of Ledger, and why each rule exists. Everything here is
taken from the source; where the implementation is stricter or looser than you might assume,
that is called out.

## 1. Compute vs leash

Two processes, one job each.

| | Python (the snake) | PowerShell (the leash) |
|---|---|---|
| Runs | `Snake.force()` — send, validate, feed failure back, retry | Spawns the snake, maps its events onto PowerShell streams |
| Decides | Whether an output passes the validator | Whether the run succeeded, and what gets recorded |
| Writes the ledger | **Never** | **Always** — sole writer |
| Knows about hashing | Computes `sha256` of the accepted output only | Computes the chain: canonical payload, `prev`, `self` |

The split matters because the ledger is a single-writer append-only file. One writer means no
interleaving, no partial lines, and no second implementation of the canonical form to keep in
sync. `snake.py` hashes the accepted output
([snake.py:183](../src/ledger/python/snake.py#L183), `hashlib.sha256(text.encode("utf-8")).hexdigest()`)
and hands that hex string up; PowerShell does everything else.

`Invoke-LedgerForce` passes scalar knobs on argv and the prompt as one JSON object on **stdin**,
so prompt text never lands in a command line or a process list.

## 2. Dry-run vs live

`-Mode dry-run` (the default) injects a scripted mock transport. `Snake.__init__` takes an
optional `transport` callable; when one is supplied it skips the key check and the SDK entirely
([snake.py:66-77](../src/ledger/python/snake.py#L66-L77)). The default script is two responses
([cli.py](../src/ledger/python/cli.py), `DEFAULT_MOCK_RESPONSES`): prose that fails
`has_function_def`, then the function that passes it. That is why a dry-run demonstrates a real
reject then feedback then retry cycle rather than a straight-through success. Override the script
with `-MockResponse`; the last entry repeats once the script runs out.

The `anthropic` import is **lazy**: it happens inside `Snake._live_transport()`
([snake.py:84](../src/ledger/python/snake.py#L84)), which is only called when no transport was
injected. So a dry-run never imports the SDK, and the package does not need to be installed at
all to run one. This is asserted by a test, not assumed — see [verification.md](verification.md).

`-Mode live` requires `ANTHROPIC_API_KEY`. PowerShell checks for it **before spawning Python** and
throws `LedgerMissingApiKey` if it is missing or whitespace. Python enforces the same rule
independently and exits `4` if reached another way. No receipt is written on either path.

## 3. The NDJSON event stream

Python's stdout is one self-describing JSON event per line. `cli.py` routes every event through a
`logging` handler with a `JsonLineFormatter`, so stdout carries only protocol; stderr carries only
unstructured crashes. Each event is stamped `"v": 1`.

`Invoke-LedgerForce` reads the stream and maps event types onto PowerShell streams:

| Event `type` | PowerShell destination |
|---|---|
| `log`, `level: "debug"` | `Write-Debug` |
| `log`, `level: "verbose"` (default) | `Write-Verbose` |
| `log`, `level: "warn"` | `Write-Warning` |
| `log`, `level: "error"` | `Write-Error` (non-terminating; also recorded) |
| `attempt` | `Write-Verbose` — `--- attempt N/M ---` |
| `validation` | `Write-Verbose` — `attempt N: VALID/INVALID - <reason>` |
| `result` | Captured as the run's result; `Write-Debug` acknowledgement |
| `error` | `Write-Error` (non-terminating; recorded, then the exit code terminates) |
| unparseable line | Recorded as raw and echoed to `Write-Verbose` as `[py-raw]` |

Nothing is swallowed. Lines that fail to parse are kept and folded into the eventual error
message rather than discarded. A run that exits `0` but never emitted a `result` event is itself
an error: `LedgerNoResult`.

The protocol version is pinned. PowerShell sends `--protocol 1`; `cli.py` rejects any other value
with exit `3`.

## 4. Exit codes

From [cli.py](../src/ledger/python/cli.py):

| Code | Constant | Meaning |
|---|---|---|
| 0 | `EXIT_OK` | Output accepted |
| 1 | `EXIT_UNEXPECTED` | Unhandled failure |
| 2 | `EXIT_VALIDATION` | Retry cap exhausted — validator never satisfied |
| 3 | `EXIT_USAGE` | Bad argv, bad stdin payload, protocol mismatch, unusable validator |
| 4 | `EXIT_NO_KEY` | Live mode with no `ANTHROPIC_API_KEY` |
| 5 | `EXIT_TRANSPORT` | The model call itself failed (network, auth, SDK missing) |

The module sets `$PSNativeCommandUseErrorActionPreference = $true`, so **any** non-zero exit
becomes a terminating PowerShell error rather than a quietly-set `$LASTEXITCODE`. It surfaces as
`LedgerSnakeFailed`, carrying the exit code and every error message collected from the stream.

## 5. Canonical JSON, and why both JSON cmdlets are banned from the chain

The hash chain is only meaningful if the exact bytes that were hashed can be reproduced later. Two
PowerShell conveniences break that, so neither is used anywhere near the chain.

**`ConvertTo-Json` is not used to build a record.** Its whitespace, escaping policy and key
ordering are implementation details, not a specification. The canonical payload is emitted by hand
by `ConvertTo-LedgerCanonicalJson`, with string escaping done explicitly in
`ConvertTo-LedgerJsonString` (quote, backslash, the five short forms, and `\uXXXX` below `0x20`).

**`ConvertFrom-Json` is not used to read one.** It infers types, and it converts an ISO-8601
string into a `[datetime]`. A parsed-then-re-stringified timestamp does not reproduce the original
characters, so every record fails its own hash check. This is not hypothetical — it was the first
failure observed during implementation. Records are parsed with `System.Text.Json`
(`JsonDocument.Parse`), which returns exact strings and additionally exposes duplicate keys that a
`PSCustomObject` would silently collapse.

The canonical payload is the record **without** `self`, keys in this exact order, no whitespace:

```json
{"ts":"...","attempt":N,"validator":"...","mode":"...","model":"...","sha256":"...","prev":"..."}
```

`self` is the lowercase-hex SHA-256 of those UTF-8 bytes. The written line is the canonical
payload with `,"self":"<64 hex>"` spliced in before the closing brace, so `self` is always the
final key and the payload is recoverable from the line by deleting it.

The form is deliberately language-neutral. Python's
`json.dumps(payload, separators=(",", ":"), ensure_ascii=False)` over the same seven keys produces
byte-identical output, which is how the chain was independently re-verified.

## 6. The critical section

`Add-LedgerRecord` must read the previous record's `self` and append the new record without
another writer slipping in between. It opens the file **once**:

```
FileMode.OpenOrCreate   FileAccess.ReadWrite   FileShare.None
```

and holds that handle across both the tail read and the write. `FileShare.None` makes the
read-then-append pair atomic with respect to other processes. If the file is locked, the open is
retried up to 10 times with a 25 ms x attempt backoff before the `IOException` propagates.

Two more properties of the write:

- **Encoding is UTF-8 with no BOM**, and the terminator is a single LF — never CRLF.
- If the file does not already end in `0x0A`, a newline is written **first**, with a warning. A
  hand-truncated tail therefore cannot get the next record glued onto it.

`Flush($true)` forces the write through to disk before the handle is released.

## 7. Record schema v1

One JSON object per line. Exactly eight fields — no more, no fewer, no duplicates. A record that
fails that check is `LedgerBadRecord`.

| Field | Type | Meaning |
|---|---|---|
| `ts` | string | UTC timestamp, format `yyyy-MM-ddTHH:mm:ss.fffZ` (millisecond precision) |
| `attempt` | number | Which attempt was accepted — the accepted attempt number, not a retry count |
| `validator` | string | Validator name that accepted the output |
| `mode` | string | `dry-run` or `live` |
| `model` | string | Model id the snake was told to use |
| `sha256` | 64 lowercase hex | SHA-256 of the **accepted output's** UTF-8 bytes |
| `prev` | 64 lowercase hex | The previous line's `self` |
| `self` | 64 lowercase hex | SHA-256 of this record's canonical payload, excluding `self` |

`sha256`, `prev` and `self` are each validated against `^[0-9a-f]{64}$` — case-sensitively, so
uppercase hex is rejected.

Note that `sha256` identifies the *output*, not the *record*. Two runs that accept identical text
produce identical `sha256` but different `self`, because `ts` and `prev` differ. That is the
intended behaviour and is exercised by the tests.

## 8. The chain rule

```
line 1.prev  ==  0000000000000000000000000000000000000000000000000000000000000000
line N.prev  ==  line N-1.self                                          (for N > 1)
```

**The genesis value is 64 ASCII `0` characters**, from `$script:LedgerGenesis = '0' * 64`
([Ledger.psm1:18](../src/ledger/Ledger.psm1#L18)). It is *not* empty, *not* null, and *not* an
absent field — `prev` is always present and always 64 hex characters, on every line including the
first. A first line with an empty or missing `prev` is rejected as `LedgerBadRecord`.

`Get-LedgerVerify` walks the file in order and, for every line, checks: valid JSON, then exactly
the eight v1 keys, then field shapes, then `self` equals the recomputed hash of that record's own
payload, then `prev` equals the running expected value. Any break is terminating, so a returned
object always means the chain held. Blank lines are skipped and do not count as records.

Because `self` covers the payload and the payload contains `prev`, editing any field of any record
invalidates that record's `self` **and** every `prev` link after it. Re-forging the chain requires
recomputing every record from the edit forward.

## 9. ErrorIds

Every one of these is raised as a **terminating** error. All thirteen exist in
[Ledger.psm1](../src/ledger/Ledger.psm1); nothing below is aspirational.

### Raised by `Invoke-LedgerForce`

| ErrorId | Category | Raised when |
|---|---|---|
| `LedgerPythonMissing` | ObjectNotFound | `-PythonPath` (default `python`) is not on `PATH` |
| `LedgerCliMissing` | ObjectNotFound | `src/ledger/python/cli.py` is absent |
| `LedgerMissingApiKey` | AuthenticationError | `-Mode live` with no `ANTHROPIC_API_KEY`. Checked **before** spawning Python |
| `LedgerSnakeFailed` | OperationStopped | Python exited non-zero. Message carries the exit code and collected errors |
| `LedgerNoResult` | ProtocolError | Python exited 0 but emitted no `result` event |
| `LedgerResultMismatch` | InvalidResult | The `result` event echoes back a `mode`, `validator` or (when `-Model` was named) `model` that differs from what the force asked for. Case-sensitive. A field the event omits is not a mismatch, and `attempts` is not checked at all |
| `LedgerOutputHashMismatch` | InvalidData | The snake's reported `sha256` does not match a local rehash of the accepted output, compared case-sensitively so uppercase hex fails here rather than at the writer. Checked **before** `-SkipLedger` returns, so it fires whether or not a receipt was going to be written |
| `LedgerAppendFailed` | WriteError | The output was accepted but its receipt could not be appended |
| `LedgerBadSettings` | InvalidArgument | `-Halt` or `-PolicyPath` without `-Policy`. Raised before Python, before the key check, before anything is spawned |

Under `-Policy`, Inspector's own errors travel up **unwrapped**: `InspectorPolicyHalt` (a
halt-weight finding under `-Halt`), `InspectorPathNotFound`, `InspectorBadSettings`. They keep
Inspector's ErrorId, so `catch { $_.FullyQualifiedErrorId }` says which module made the decision.
Ledger owns `LedgerBadSettings` for its own parameter law and nothing else.

`LedgerAppendFailed` is the one to understand: the force **succeeded** and the model output is
valid, but the receipt did not land. It is terminating by design — a silently missing receipt
defeats the purpose of an append-only ledger. The accepted `Ledger.ForceResult` is attached to the
ErrorRecord's `TargetObject` so the output is recoverable from the error. See
[do-not.md](do-not.md).

### Raised by `Get-LedgerVerify` and `Get-LedgerEntry`

| ErrorId | Category | Raised when |
|---|---|---|
| `LedgerFileMissing` | ObjectNotFound | The ledger file does not exist |
| `LedgerCorruptLine` | InvalidData | A line is not valid JSON, or is not a JSON object |
| `LedgerBadRecord` | InvalidData | Wrong field set, duplicate keys, wrong JSON type, or a malformed hash/timestamp |
| `LedgerBadSelf` | InvalidData | A record's `self` does not match its recomputed payload hash — the record was edited |
| `LedgerBrokenChain` | InvalidData | A record's `prev` does not match the previous record's `self` — a record was inserted, removed or reordered |

`LedgerBadRecord` is also raised by the writer if it is handed an output hash that is not 64
lowercase hex characters, so a malformed hash can never enter the file.

**`LedgerBadSelf` vs `LedgerBrokenChain`.** Editing a field in place trips `LedgerBadSelf` first,
because a record is checked against itself before it is checked against its predecessor.
`LedgerBrokenChain` is what you see when records are structurally rearranged — deleted, inserted
or reordered — while each individual record remains internally consistent.
