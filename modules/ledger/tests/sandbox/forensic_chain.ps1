#Requires -Version 7.4
<#
.SYNOPSIS
    Prove the forensic chain detects tampering, and prove it never touches the receipt chain.

.DESCRIPTION
    A hash chain nobody has tried to break is a decoration. Every check below either
    verifies the real chain read-only, or breaks a COPY in $env:TEMP and asserts the
    verifier throws. If a tamper check passes on a broken copy, the chain is theatre.

    The real `.continuity/forensic.jsonl` and `.ledger/ledger.jsonl` are never written
    by this suite. Check 8 proves it by hashing both before and after.

.EXAMPLE
    pwsh -NoProfile -File tests/sandbox/forensic_chain.ps1
#>
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$script:Checks = 0
$script:Failures = 0

function Write-Section { param([string]$T) Write-Host ''; Write-Host "=== $T ===" -ForegroundColor Cyan }

function Assert-That {
    param([bool]$Condition, [string]$Name, [string]$Why = '')
    $script:Checks++
    if ($Condition) { Write-Host "  PASS  $Name" -ForegroundColor Green }
    else {
        $script:Failures++
        Write-Host "  FAIL  $Name" -ForegroundColor Red
        if ($Why) { Write-Host "        $Why" -ForegroundColor DarkYellow }
    }
}

function Test-VerifyThrows {
    <#
        Run the verifier against a path and report whether it failed. A tamper check
        that cannot distinguish "threw" from "exited 0" proves nothing, so this reads
        the exit code, not the text.
    #>
    param([Parameter(Mandatory)][string]$File)
    return Invoke-Forensic @('-Verify', '-Path', $File)
}

function Invoke-Forensic {
    <#
        Run forensic.ps1 and report its exit code as data. The repo sets
        $PSNativeCommandUseErrorActionPreference = $true, which makes a non-zero exit a
        terminating error -- correct everywhere else, useless in a suite whose whole job
        is to make the verifier fail on purpose. Setting the preference inside the
        function creates a local copy; the caller's value is untouched.
    #>
    param([Parameter(Mandatory)][string[]]$Arguments)
    $PSNativeCommandUseErrorActionPreference = $false
    $out = & pwsh -NoProfile -File $script:Script @Arguments 2>&1
    return [pscustomobject]@{ Failed = ($LASTEXITCODE -ne 0); Code = $LASTEXITCODE; Output = ($out -join "`n") }
}

function Get-FileSha {
    param([Parameter(Mandatory)][string]$File)
    if (-not (Test-Path -LiteralPath $File)) { return '(absent)' }
    return (Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash
}

$root         = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$script:Script = Join-Path $root 'scripts/forensic.ps1'
$chainPath    = Join-Path $root '.continuity/forensic.jsonl'
$ledgerPath   = Join-Path $root '.ledger/ledger.jsonl'

$beforeForensic = Get-FileSha $chainPath
$beforeLedger   = Get-FileSha $ledgerPath

$work = Join-Path ([System.IO.Path]::GetTempPath()) "forensic-suite-$PID"
$null = New-Item -ItemType Directory -Path $work -Force

try {
    # ------------------------------------------------------------------ 1
    Write-Section '1  the real chain verifies, read-only'

    Assert-That (Test-Path -LiteralPath $script:Script) 'scripts/forensic.ps1 exists'
    Assert-That (Test-Path -LiteralPath $chainPath) '.continuity/forensic.jsonl exists'

    $real = Test-VerifyThrows -File $chainPath
    Assert-That (-not $real.Failed) 'the live forensic chain verifies' $real.Output
    Assert-That ($real.Output -match 'FORENSIC CHAIN OK') 'the verifier says so out loud'

    $lines = @([System.IO.File]::ReadAllLines($chainPath) | Where-Object { $_.Trim() })
    Assert-That ($lines.Count -ge 1) "the chain has records ($($lines.Count))"

    # ------------------------------------------------------------------ 2
    Write-Section '2  the schema is eight keys, in order, frozen'

    $first = [System.Text.Json.JsonDocument]::Parse($lines[0])
    try {
        $keys = @($first.RootElement.EnumerateObject() | ForEach-Object { $_.Name })
    }
    finally { $first.Dispose() }

    $expected = @('ts', 'seq', 'actor', 'kind', 'subject', 'evidence', 'prev', 'self')
    Assert-That ($keys.Count -eq 8) "record 1 has 8 keys (found $($keys.Count))"
    Assert-That (-not (Compare-Object $keys $expected -SyncWindow 0)) `
        'the eight keys are in schema order' "found: $($keys -join ',')"

    Assert-That ($lines[0] -match '"prev":""') 'the genesis record has an empty prev'

    # ------------------------------------------------------------------ 3
    Write-Section '3  a changed byte is detected'

    $t = Join-Path $work 'tampered-evidence.jsonl'
    $copy = [System.IO.File]::ReadAllLines($chainPath)
    # flip one character inside 'evidence' on the first record, leaving every hash alone
    $copy[0] = $copy[0] -replace '"evidence":"', '"evidence":"X'
    [System.IO.File]::WriteAllLines($t, $copy, [System.Text.UTF8Encoding]::new($false))
    $r = Test-VerifyThrows -File $t
    Assert-That $r.Failed 'editing one evidence byte fails verification' `
        'a chain that accepts an edited payload is not a chain'
    Assert-That ($r.Output -match 'self mismatch') 'and it says which record and why'

    # ------------------------------------------------------------------ 4
    Write-Section '4  a removed record breaks linkage'

    if ($lines.Count -ge 3) {
        $t = Join-Path $work 'removed-record.jsonl'
        $copy = @([System.IO.File]::ReadAllLines($chainPath))
        $copy = $copy[0..0] + $copy[2..($copy.Count - 1)]   # drop record 2
        [System.IO.File]::WriteAllLines($t, $copy, [System.Text.UTF8Encoding]::new($false))
        $r = Test-VerifyThrows -File $t
        Assert-That $r.Failed 'deleting a record in the middle fails verification'
        Assert-That ($r.Output -match 'prev is|seq is') 'and it names the linkage or the sequence'
    }
    else {
        Write-Host '  SKIP  fewer than three records; linkage test needs a middle' -ForegroundColor Yellow
    }

    # ------------------------------------------------------------------ 5
    Write-Section '5  a reordered chain is detected'

    if ($lines.Count -ge 3) {
        $t = Join-Path $work 'reordered.jsonl'
        $copy = @([System.IO.File]::ReadAllLines($chainPath))
        $swap = $copy[1]; $copy[1] = $copy[2]; $copy[2] = $swap
        [System.IO.File]::WriteAllLines($t, $copy, [System.Text.UTF8Encoding]::new($false))
        $r = Test-VerifyThrows -File $t
        Assert-That $r.Failed 'swapping two records fails verification' `
            'append-only is only meaningful if order is load-bearing'
    }
    else {
        Write-Host '  SKIP  fewer than three records' -ForegroundColor Yellow
    }

    # ------------------------------------------------------------------ 6
    Write-Section '6  a ninth key and an uppercase hash are refused'

    $t = Join-Path $work 'ninth-key.jsonl'
    $copy = @([System.IO.File]::ReadAllLines($chainPath))
    $copy[0] = $copy[0] -replace '}$', ',"note":"harmless"}'
    [System.IO.File]::WriteAllLines($t, $copy, [System.Text.UTF8Encoding]::new($false))
    $r = Test-VerifyThrows -File $t
    Assert-That $r.Failed 'a ninth key is refused' 'the schema is frozen or it is not a schema'
    Assert-That ($r.Output -match 'expected 8 keys') 'and it says the key count'

    $t = Join-Path $work 'upper-hex.jsonl'
    $copy = @([System.IO.File]::ReadAllLines($chainPath))
    $m = [regex]::Match($copy[0], '"self":"([0-9a-f]{64})"')
    $copy[0] = $copy[0] -replace '"self":"[0-9a-f]{64}"', ('"self":"' + $m.Groups[1].Value.ToUpperInvariant() + '"')
    [System.IO.File]::WriteAllLines($t, $copy, [System.Text.UTF8Encoding]::new($false))
    $r = Test-VerifyThrows -File $t
    Assert-That $r.Failed 'uppercase hex is refused' `
        'a digest right about the bytes and wrong about the encoding is a different string'

    # ------------------------------------------------------------------ 7
    Write-Section '7  the writer refuses a broken tail, and the twin proves the check can pass'

    $t = Join-Path $work 'append-onto-broken.jsonl'
    $copy = @([System.IO.File]::ReadAllLines($chainPath))
    $copy[0] = $copy[0] -replace '"evidence":"', '"evidence":"Z'
    [System.IO.File]::WriteAllLines($t, $copy, [System.Text.UTF8Encoding]::new($false))

    $probe = Invoke-Forensic @('-Append', '-Actor', 'claude', '-Kind', 'finding',
        '-Subject', 'suite-probe', '-Evidence', 'suite probe, must be refused', '-Path', $t)
    Assert-That $probe.Failed 'appending onto an unverifiable tail is refused' `
        'Add-LedgerRecord documents that appending does not verify the tip; this writer refuses instead'
    Assert-That ($probe.Output -match 'refusing to append') 'and it says refusing to append'

    $before = (@([System.IO.File]::ReadAllLines($t))).Count
    $forced = Invoke-Forensic @('-Append', '-Actor', 'claude', '-Kind', 'finding',
        '-Subject', 'suite-probe', '-Evidence', 'suite probe, forced', '-Path', $t, '-Force')
    $after = (@([System.IO.File]::ReadAllLines($t))).Count
    Assert-That ($after -eq $before + 1) '-Force appends anyway, which is why it exists' `
        "before=$before after=$after"
    Assert-That ($forced.Output -match 'unverifiable tail') '-Force warns on the way past'

    # a good tail accepts, so check 7 is not vacuously true
    $t2 = Join-Path $work 'append-onto-good.jsonl'
    Copy-Item -LiteralPath $chainPath -Destination $t2 -Force
    $before = (@([System.IO.File]::ReadAllLines($t2))).Count
    $good = Invoke-Forensic @('-Append', '-Actor', 'claude', '-Kind', 'finding',
        '-Subject', 'suite-probe', '-Evidence', 'suite probe, good tail', '-Path', $t2)
    $after = (@([System.IO.File]::ReadAllLines($t2))).Count
    Assert-That ((-not $good.Failed) -and $after -eq $before + 1) `
        'appending onto a verified tail succeeds' "before=$before after=$after"
    $r = Test-VerifyThrows -File $t2
    Assert-That (-not $r.Failed) 'and the extended chain still verifies' $r.Output

    # ------------------------------------------------------------------ 8
    Write-Section '8  the receipt chain was never touched'

    Assert-That ((Get-FileSha $ledgerPath) -eq $beforeLedger) `
        '.ledger/ledger.jsonl is byte-identical' `
        'a continuity entry is not a receipt; schema v1 stays eight keys'
    Assert-That ((Get-FileSha $chainPath) -eq $beforeForensic) `
        '.continuity/forensic.jsonl is byte-identical' `
        'this suite is read-only against the live chain'

    # Code, not comments. The first draft of these two checks greped the whole file
    # and went red on the writer's own docstring, which names .ledger/ledger.jsonl and
    # ConvertFrom-Json in order to explain why neither is used. That is precisely the
    # defect this session caught in no_sabotage.ps1 check 6 -- a whole-file grep reading
    # the evidence as the crime -- reproduced by the person who caught it, one file over.
    $writerCode = [System.Collections.Generic.List[string]]::new()
    $inBlock = $false
    foreach ($line in (Get-Content $script:Script)) {
        if ($line -match '<#') { $inBlock = $true }
        if ($inBlock) { if ($line -match '#>') { $inBlock = $false }; continue }
        if ($line -match '^\s*#') { continue }
        $writerCode.Add($line)
    }
    $code = $writerCode -join "`n"

    Assert-That ($code -notmatch 'ledger\.jsonl') `
        'no executable line of the forensic writer names a path inside .ledger/' `
        'a continuity entry is not a receipt; schema v1 stays eight keys'
    Assert-That ($code -notmatch 'ConvertTo-Json|ConvertFrom-Json') `
        'no executable line of the forensic writer calls ConvertTo-Json or ConvertFrom-Json' `
        'ConvertFrom-Json turns ts into a datetime and every hash fails'
    Assert-That ($code -match 'FileShare\]::None') `
        'the writer opens the chain exclusively, one handle' `
        'same discipline as Add-LedgerRecord: one writer or the tail is a race'
    Assert-That ($code -match 'System\.Text\.Json') `
        'the reader parses with System.Text.Json'
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host "checks run: $($script:Checks)"
if ($script:Failures -eq 0) {
    Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
    exit 0
}
Write-Host "$($script:Failures) of $($script:Checks) CHECK(S) FAILED" -ForegroundColor Red
exit 1
