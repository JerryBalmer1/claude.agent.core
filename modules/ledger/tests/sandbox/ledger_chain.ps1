#Requires -Version 7.4
<#
.SYNOPSIS
    Prove the append-only receipt chain: it grows, it links, and it refuses to lie.

.DESCRIPTION
    Ten tests:
      1. The example appends exactly one receipt; Get-LedgerVerify says Ok.
      2. A second run increments Count and line N's prev equals line N-1's self.
      3. A tampered copy in the sandbox makes Get-LedgerVerify throw.
      4. The dry-run path never imports anthropic.
      5. Live mode with no key throws before spawn and writes no receipt.
      6. The optional -Policy / -Halt pass-through to claude.build.inspector: off by
         default, one inspect when asked, InspectorPolicyHalt unwrapped under -Halt,
         and src/ still imports no policy module of its own.
      7. Schema and chain rejection, forged line by line.
      8. The writer rehashes the accepted output and refuses a hash it cannot reproduce
         - including one that is right about the bytes and wrong about the case.
      9. A halt writes no receipt, with no -SkipLedger to hide behind.
     10. The result event must describe the run that was asked for: a mode, validator or
         named model that comes back different raises LedgerResultMismatch. An omitted
         -Model is the one exemption, and attempts is not verified at all.

    Test 6 writes its fixtures to $env:TEMP only and deletes them in a finally block.

    Everything this script generates lands in tests/sandbox/, which is gitignored
    except for .ps1 files. Nothing here is committed.

.EXAMPLE
    pwsh -NoProfile -File tests/sandbox/ledger_chain.ps1 -Verbose
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'Continue' }

$repo     = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..'))
$manifest = Join-Path -Path $repo -ChildPath 'src' -AdditionalChildPath 'ledger', 'Ledger.psd1'
$default  = Join-Path -Path $repo -ChildPath '.ledger' -AdditionalChildPath 'ledger.jsonl'
$sandbox  = $PSScriptRoot

if (-not (Test-Path -LiteralPath $manifest)) { throw "Ledger.psd1 not found at $manifest" }
Import-Module -Name $manifest -Force -ErrorAction Stop

$script:Failures = 0
$script:Checks   = 0

function Write-Section { param([string]$Text)
    Write-Host ''
    Write-Host "=== $Text ===" -ForegroundColor Cyan
}

function Assert-That { param([bool]$Condition, [string]$Label, [string]$Detail = '')
    $script:Checks++
    if ($Condition) {
        Write-Host "  PASS  $Label" -ForegroundColor Green
    } else {
        Write-Host "  FAIL  $Label" -ForegroundColor Red
        if ($Detail) { Write-Host "        $Detail" -ForegroundColor Red }
        $script:Failures++
    }
}

function Get-LedgerCount {
    if (-not (Test-Path -LiteralPath $default -PathType Leaf)) { return 0 }
    return (Get-LedgerVerify -LedgerPath $default).Count
}

# Run the example the way CLAUDE.md says to: pwsh -NoProfile -File, repo-relative.
# No stream redirection: merging native stderr into the pipeline under
# $ErrorActionPreference = 'Stop' turns ordinary verbose chatter into a throw.
# A non-zero exit still terminates, via $PSNativeCommandUseErrorActionPreference.
function Invoke-Example {
    Push-Location -LiteralPath $repo
    try {
        pwsh -NoProfile -File 'examples/force_example.ps1' -Verbose
        Write-Host "  example exit code: $LASTEXITCODE"
    }
    finally { Pop-Location }
}

# ---------------------------------------------------------------- 1
Write-Section 'TEST 1  example appends one receipt, verify says Ok'

$before = Get-LedgerCount
Write-Host "  ledger count before: $before"
Invoke-Example
$v1 = Get-LedgerVerify -LedgerPath $default -Verbose
$v1 | Format-List | Out-String | Write-Host

Assert-That $v1.Ok                      'Ok is true'
Assert-That ($v1.Count -ge 1)           'Count >= 1'         "Count=$($v1.Count)"
Assert-That ($v1.Count -eq $before + 1) 'exactly one line appended' "before=$before after=$($v1.Count)"

# ---------------------------------------------------------------- 2
Write-Section 'TEST 2  second run increments Count and links prev -> self'

Invoke-Example
$v2 = Get-LedgerVerify -LedgerPath $default

Assert-That ($v2.Count -eq $v1.Count + 1) 'Count incremented by 1' "was=$($v1.Count) now=$($v2.Count)"

$pair = @(Get-LedgerEntry -LedgerPath $default -Last 2)
$pair | Format-Table Line, Ts, Attempt, Mode, @{n='Sha256'; e={$_.Sha256.Substring(0,16)}},
    @{n='Prev'; e={$_.Prev.Substring(0,16)}}, @{n='Self'; e={$_.Self.Substring(0,16)}} |
    Out-String | Write-Host

Assert-That ($pair.Count -eq 2)             'Get-LedgerEntry -Last 2 returned 2 records'
Assert-That ($pair[1].Prev -eq $pair[0].Self) 'line N prev == line N-1 self' `
    "prev=$($pair[1].Prev) self=$($pair[0].Self)"
Assert-That ($v2.LastSelf -eq $pair[1].Self) 'LastSelf matches the final record'

# ---------------------------------------------------------------- 3
Write-Section 'TEST 3  tampered copy must throw'

$broken = Join-Path -Path $sandbox -ChildPath 'broken.jsonl'
$lines  = @([System.IO.File]::ReadAllLines($default, [System.Text.UTF8Encoding]::new($false)) |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

# Flip one hex digit of the last record's sha256. Nothing else changes.
$victim = $lines[-1]
if (-not ($victim -match '"sha256":"([0-9a-f]{64})"')) {
    throw 'could not locate sha256 in the last record'
}
$origHash = $Matches[1]
$firstDigit = if ($origHash[0] -eq '0') { 'f' } else { '0' }
$flipped    = $firstDigit + $origHash.Substring(1)
$lines[-1]  = $victim -replace "`"sha256`":`"$origHash`"", "`"sha256`":`"$flipped`""

[System.IO.File]::WriteAllText(
    $broken, ($lines -join "`n") + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host "  wrote $broken with sha256 $($origHash.Substring(0,16))... -> $($flipped.Substring(0,16))..."

$threw = $false
$errId = ''
try {
    Get-LedgerVerify -LedgerPath $broken | Out-Null
}
catch {
    $threw = $true
    $errId = $_.FullyQualifiedErrorId
    Write-Host ''
    Write-Host '  --- TERMINATING ERROR CAUGHT (expected) ---' -ForegroundColor Yellow
    Write-Host "  FullyQualifiedErrorId : $errId"
    Write-Host "  Category              : $($_.CategoryInfo.Category)"
    Write-Host "  Message               : $($_.Exception.Message)"
    Write-Host ''
}

Assert-That $threw                        'Get-LedgerVerify threw on the broken chain'
Assert-That ($errId -like 'LedgerBadSelf*') 'failed for the right reason (LedgerBadSelf)' "got: $errId"

# The real ledger must be untouched by any of that.
Assert-That ((Get-LedgerVerify -LedgerPath $default).Count -eq $v2.Count) 'real ledger still intact'

# ---------------------------------------------------------------- 4
Write-Section 'TEST 4  dry-run never imports anthropic'

# Generated at runtime into the gitignored sandbox, so it is never committed.
$checker = Join-Path -Path $sandbox -ChildPath 'no_anthropic_check.py'
$checkerSource = @'
"""Assert the dry-run path never drags the anthropic SDK into sys.modules."""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "src", "ledger", "python"))

import cli  # noqa: E402

if "anthropic" in sys.modules:
    print("LEAK: importing cli already pulled in anthropic", file=sys.stderr)
    sys.exit(1)

sys.stdin = io.StringIO(json.dumps({"prompt": "Write a Python function add(a, b)."}))
rc = cli.main([
    "--protocol", "1",
    "--mode", "dry-run",
    "--model", "claude-sonnet-4-5",
    "--max-retries", "5",
    "--validator", "has_function_def",
    "--max-tokens", "256",
    "--base-delay", "0",
])

leaked = sorted(m for m in sys.modules if m == "anthropic" or m.startswith("anthropic."))
print("CHECK exit_code={0} anthropic_modules={1}".format(rc, leaked or "none"), file=sys.stderr)

if rc != 0:
    print("FAIL: dry-run exited {0}".format(rc), file=sys.stderr)
    sys.exit(1)
if leaked:
    print("FAIL: dry-run imported {0}".format(leaked), file=sys.stderr)
    sys.exit(1)

print("OK: dry-run completed with anthropic absent from sys.modules", file=sys.stderr)
sys.exit(0)
'@
[System.IO.File]::WriteAllText($checker, $checkerSource, [System.Text.UTF8Encoding]::new($false))

# stderr goes to a file rather than into the pipeline, for the same reason as above.
$pyErr = Join-Path -Path $sandbox -ChildPath 'no_anthropic_check.err'
$pyOk  = $true
try {
    python $checker 2> $pyErr
}
catch {
    $pyOk = $false
    Write-Host "  python check failed: $($_.Exception.Message)" -ForegroundColor Red
}
$pyErrText = ''
if (Test-Path -LiteralPath $pyErr) {
    $pyErrText = (Get-Content -LiteralPath $pyErr -Raw)
    Get-Content -LiteralPath $pyErr | ForEach-Object { Write-Host "  py| $_" }
}

# $pyOk alone is a weak check: it starts $true and only flips in a catch, so it depends
# entirely on $PSNativeCommandUseErrorActionPreference being on. If that line were ever
# dropped from the header, a failing leak check would still print PASS. Assert on what the
# checker actually printed as well, so the check stands on its own evidence.
Assert-That $pyOk 'dry-run ran to completion with anthropic absent from sys.modules'
Assert-That ($pyErrText -match 'anthropic_modules=none') `
    'the checker reported anthropic_modules=none' $pyErrText
Assert-That ($pyErrText -match 'OK: dry-run completed with anthropic absent') `
    'the checker printed its success sentinel, not just a zero exit' $pyErrText
Assert-That ($pyErrText -notmatch 'LEAK:|FAIL:') `
    'the checker printed no LEAK or FAIL line' $pyErrText

# ---------------------------------------------------------------- 5
Write-Section 'TEST 5  live mode with no key throws before spawn, writes nothing'

$countBeforeLive = (Get-LedgerVerify -LedgerPath $default).Count
$savedKey = $env:ANTHROPIC_API_KEY
$liveThrew = $false
$liveId = ''
try {
    $env:ANTHROPIC_API_KEY = ''
    Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' -Mode 'live' -Verbose |
        Out-Null
}
catch {
    $liveThrew = $true
    $liveId = $_.FullyQualifiedErrorId
    Write-Host ''
    Write-Host '  --- TERMINATING ERROR CAUGHT (expected) ---' -ForegroundColor Yellow
    Write-Host "  FullyQualifiedErrorId : $liveId"
    Write-Host "  Category              : $($_.CategoryInfo.Category)"
    Write-Host "  InnerException        : $($_.Exception.GetType().Name)"
    Write-Host "  Message               : $($_.Exception.Message)"
    Write-Host ''
}
finally { $env:ANTHROPIC_API_KEY = $savedKey }

$countAfterLive = (Get-LedgerVerify -LedgerPath $default).Count

Assert-That $liveThrew                          'live mode without a key threw'
Assert-That ($liveId -like 'LedgerMissingApiKey*') 'error id is LedgerMissingApiKey' "got: $liveId"
Assert-That ($countAfterLive -eq $countBeforeLive) 'no receipt was written' `
    "before=$countBeforeLive after=$countAfterLive"

# ---------------------------------------------------------------- bonus
Write-Section 'SkipLedger writes nothing'

$countBeforeSkip = (Get-LedgerVerify -LedgerPath $default).Count
$skipped = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
    -Mode 'dry-run' -SkipLedger
$countAfterSkip = (Get-LedgerVerify -LedgerPath $default).Count

Assert-That ($null -eq $skipped.LedgerPath)        'LedgerPath is null under -SkipLedger'
Assert-That ($null -eq $skipped.LedgerSelf)        'LedgerSelf is null under -SkipLedger'
Assert-That ($countAfterSkip -eq $countBeforeSkip) 'Count unchanged under -SkipLedger'

# ---------------------------------------------------------------- 6
Write-Section 'TEST 6  optional -Policy / -Halt pass-through to claude.build.inspector'

# Everything this test creates lives in $env:TEMP and is removed in the finally block.
$script:TempRoots = [System.Collections.Generic.List[string]]::new()

function New-PolicyFixture {
    <#
        A throwaway project the policy parser reads as halt-weight law, with an allow
        list that trips Inspector's allow-contains-bash check. Same shape as the fixture
        in claude.build.inspector's own suite.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $root = Join-Path -Path $env:TEMP -ChildPath ('ledger-chain-{0}-{1}' -f $PID, $Name)
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    [void](New-Item -ItemType Directory -Path $root -Force)
    $script:TempRoots.Add($root)

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText(
        (Join-Path -Path $root -ChildPath 'AGENTS.md'),
        "# temp project`n`n## Laws`n`n- Do not import Ledger.`n",
        $utf8)

    $claudeDir = Join-Path -Path $root -ChildPath '.claude'
    [void](New-Item -ItemType Directory -Path $claudeDir -Force)
    $settings = [ordered]@{
        permissions = [ordered]@{
            allow = @('Bash(*)')
            deny  = @('Read(./.env)')
            ask   = @()
        }
    }
    [System.IO.File]::WriteAllText(
        (Join-Path -Path $claudeDir -ChildPath 'settings.json'),
        (($settings | ConvertTo-Json -Depth 5) + "`n"),
        $utf8)

    return $root
}

function New-LawlessFixture {
    <#
        The dangerous shape: the same shell-handing settings.json as New-PolicyFixture,
        with the law removed. Before PolicySourceCount this was indistinguishable from a
        clean project - evaluated, no rules, no halts - so deleting AGENTS.md was enough
        to switch -Halt off silently. -EmptyAgents leaves a blank AGENTS.md instead of
        no file, because blanking it and deleting it are the same move.
    #>
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$EmptyAgents
    )

    $root = Join-Path -Path $env:TEMP -ChildPath ('ledger-chain-{0}-{1}' -f $PID, $Name)
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    [void](New-Item -ItemType Directory -Path $root -Force)
    $script:TempRoots.Add($root)

    $utf8 = [System.Text.UTF8Encoding]::new($false)
    if ($EmptyAgents) {
        [System.IO.File]::WriteAllText((Join-Path -Path $root -ChildPath 'AGENTS.md'), '', $utf8)
    }

    $claudeDir = Join-Path -Path $root -ChildPath '.claude'
    [void](New-Item -ItemType Directory -Path $claudeDir -Force)
    $settings = [ordered]@{
        permissions = [ordered]@{
            allow = @('Bash(*)')
            deny  = @('Read(./.env)')
            ask   = @()
        }
    }
    [System.IO.File]::WriteAllText(
        (Join-Path -Path $claudeDir -ChildPath 'settings.json'),
        (($settings | ConvertTo-Json -Depth 5) + "`n"),
        $utf8)

    return $root
}

function New-PermissiveFixture {
    <#
        A project that really did write its law down and simply forbids nothing. It must
        stay quiet: this is the false positive that a rule-count check would raise and a
        source-count check must not.
    #>
    param([Parameter(Mandatory)][string]$Name)

    $root = Join-Path -Path $env:TEMP -ChildPath ('ledger-chain-{0}-{1}' -f $PID, $Name)
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    [void](New-Item -ItemType Directory -Path $root -Force)
    $script:TempRoots.Add($root)

    [System.IO.File]::WriteAllText(
        (Join-Path -Path $root -ChildPath 'AGENTS.md'),
        "# permissive project`n`nThis project trusts its agents and forbids nothing.`n",
        [System.Text.UTF8Encoding]::new($false))

    return $root
}

# git's own view of the tree, so test 6 can prove it left no trace under the repo.
function Get-RepoStatus {
    Push-Location -LiteralPath $repo
    try { return (@(git status --porcelain) -join "`n") }
    finally { Pop-Location }
}

$statusBefore = Get-RepoStatus
$countBefore6 = (Get-LedgerVerify -LedgerPath $default).Count

try {
    # -- 6a: the default force is unchanged. No inspect, no policy, no import.
    $plain = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
        -Mode 'dry-run' -SkipLedger
    $plainProp = $plain.PSObject.Properties['PolicyEvaluated']
    Assert-That ($null -eq $plainProp -or -not $plainProp.Value) `
        'default force is observe-only: PolicyEvaluated absent or false' `
        ("got: " + $(if ($plainProp) { $plainProp.Value } else { '(absent)' }))
    Assert-That ($null -eq (Get-Module -Name 'claude.build.policy')) `
        'a plain force pulled no policy module into the session'

    # -- 6b: -Policy against this repo. Inspector runs, the written law is counted.
    $self = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
        -Mode 'dry-run' -SkipLedger -Policy -Verbose
    Write-Host ("  self-inspect: evaluated={0} rules={1} halts={2}" -f
        $self.PolicyEvaluated, $self.PolicyRuleCount, $self.PolicyHaltCount)

    Assert-That ([bool]$self.PolicyEvaluated) '-Policy on this repo: PolicyEvaluated is true'
    Assert-That ($self.PolicyRuleCount -ge 1) '-Policy on this repo: PolicyRuleCount >= 1' `
        "PolicyRuleCount=$($self.PolicyRuleCount)"
    Assert-That ($self.PolicyPath -eq $repo)  '-Policy inspected this repo by default' `
        "PolicyPath=$($self.PolicyPath)"

    # -- 6c: a lawful temp project that also allows Bash(*). Halt findings, but no throw.
    $fixture = New-PolicyFixture -Name 'bash-allow'
    Write-Host "  fixture: $fixture"

    $observed = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
        -Mode 'dry-run' -SkipLedger -Policy -PolicyPath $fixture
    Write-Host ("  fixture observe: evaluated={0} rules={1} halts={2}" -f
        $observed.PolicyEvaluated, $observed.PolicyRuleCount, $observed.PolicyHaltCount)

    Assert-That ($observed.PolicyHaltCount -ge 1) '-Policy on a lawful fixture: PolicyHaltCount >= 1' `
        "PolicyHaltCount=$($observed.PolicyHaltCount)"
    Assert-That (-not [string]::IsNullOrWhiteSpace($observed.Output)) `
        '-Policy without -Halt still produced accepted output'

    # -- 6d: the same fixture with -Halt. Inspector's own ErrorId, unwrapped.
    $haltThrew = $false
    $haltId    = ''
    try {
        Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
            -Mode 'dry-run' -SkipLedger -Policy -Halt -PolicyPath $fixture | Out-Null
    }
    catch {
        $haltThrew = $true
        $haltId    = $_.FullyQualifiedErrorId
        Write-Host ''
        Write-Host '  --- TERMINATING ERROR CAUGHT (expected) ---' -ForegroundColor Yellow
        Write-Host "  FullyQualifiedErrorId : $haltId"
        Write-Host "  Category              : $($_.CategoryInfo.Category)"
        Write-Host "  Message               : $($_.Exception.Message)"
        Write-Host ''
    }

    Assert-That $haltThrew '-Policy -Halt on a lawful fixture threw'
    Assert-That ($haltId -like 'InspectorPolicyHalt*') `
        "-Halt surfaced Inspector's own ErrorId unwrapped" "got: $haltId"

    # -- 6e: -Halt on its own is a parameter error, raised before anything is spawned.
    $badThrew = $false
    $badId    = ''
    try {
        Invoke-LedgerForce -Prompt 'Write add(a, b).' -Mode 'dry-run' -SkipLedger -Halt | Out-Null
    }
    catch {
        $badThrew = $true
        $badId    = $_.FullyQualifiedErrorId
        Write-Host "  -Halt alone: $badId"
    }

    Assert-That $badThrew                           '-Halt without -Policy threw'
    Assert-That ($badId -like 'LedgerBadSettings*') 'error id is LedgerBadSettings' "got: $badId"

    # -- 6f: the import law, read off the source rather than taken on faith.
    $srcFiles = @(Get-ChildItem -LiteralPath (Join-Path -Path $repo -ChildPath 'src') -Recurse -File |
        Where-Object { $_.FullName -notmatch '__pycache__' })
    $srcText  = @($srcFiles | ForEach-Object {
        [System.IO.File]::ReadAllLines($_.FullName, [System.Text.UTF8Encoding]::new($false))
    })

    $rulesHits = @($srcText | Where-Object { $_ -match 'Get-PolicyRules' })
    Assert-That ($rulesHits.Count -eq 0) 'src/ never calls Get-PolicyRules' `
        "hits: $($rulesHits -join ' | ')"

    # Comments may name the law. Code may not import it.
    $policyLines = @($srcText | Where-Object { $_ -match 'claude\.build\.policy' })
    $policyCode  = @($policyLines | Where-Object { $_.TrimStart() -notmatch '^#' })
    Assert-That ($policyCode.Count -eq 0) 'src/ names claude.build.policy in comments only' `
        "code lines: $($policyCode -join ' | ')"

    $importHits = @($srcText | Where-Object {
        $_ -match 'Import-Module' -and $_ -match 'claude\.build\.policy' })
    Assert-That ($importHits.Count -eq 0) 'src/ has no claude.build.policy import' `
        "hits: $($importHits -join ' | ')"

    $manifestText = [System.IO.File]::ReadAllText($manifest, [System.Text.UTF8Encoding]::new($false))
    Assert-That ($manifestText -notmatch 'RequiredModules') `
        'Ledger.psd1 declares no RequiredModules (Inspector stays optional)'

    # -- 6g: absent law must not read as clean law.
    #        A project whose AGENTS.md was deleted reports evaluated / zero rules / zero
    #        halts - the same thing a lawful permissive project reports - so before
    #        PolicySourceCount, deleting one file switched -Halt off and nothing said so.
    #        The answer is loud, never fatal: -Halt fires on law that was broken, not on
    #        law that was never written.
    Write-Host ''
    Write-Host '  -- 6g: absent law is loud --' -ForegroundColor Cyan

    $lawless     = New-LawlessFixture -Name 'lawless'
    $lawlessWarn = $null
    $lawlessRes  = $null
    $lawlessThrew = $false
    try {
        $lawlessRes = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
            -Mode 'dry-run' -SkipLedger -Policy -Halt -PolicyPath $lawless `
            -WarningVariable lawlessWarn -WarningAction SilentlyContinue
    }
    catch {
        $lawlessThrew = $true
        Write-Host "  lawless threw: $($_.FullyQualifiedErrorId)" -ForegroundColor Red
    }

    Assert-That (-not $lawlessThrew) `
        'absent law does not throw under -Halt (no law is not broken law)'

    if (-not $lawlessThrew) {
        Write-Host ("  lawless: evaluated={0} sources={1} rules={2} halts={3}" -f
            $lawlessRes.PolicyEvaluated, $lawlessRes.PolicySourceCount,
            $lawlessRes.PolicyRuleCount, $lawlessRes.PolicyHaltCount)

        Assert-That ($null -ne $lawlessRes.PSObject.Properties['PolicySourceCount']) `
            'ForceResult carries PolicySourceCount'
        Assert-That ($lawlessRes.PolicySourceCount -eq 0) `
            'absent law: PolicySourceCount is 0' "got: $($lawlessRes.PolicySourceCount)"
        Assert-That ([bool]$lawlessRes.PolicyEvaluated) `
            'absent law: PolicyEvaluated stays true (the evaluation did run)'
        Assert-That ($lawlessRes.PolicyHaltCount -eq 0) `
            'absent law: PolicyHaltCount is 0, so only the source count tells them apart'

        $warnText = (@($lawlessWarn) | ForEach-Object { [string]$_ }) -join ' // '
        Write-Host "  warning: $warnText"
        Assert-That ($warnText -match 'no law sources') `
            'absent law warned out loud' "warnings: $warnText"
    }

    # The same move by a different name: the file is there, and says nothing.
    $blank    = New-LawlessFixture -Name 'lawless-blank' -EmptyAgents
    $blankRes = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
        -Mode 'dry-run' -SkipLedger -Policy -Halt -PolicyPath $blank `
        -WarningAction SilentlyContinue
    Assert-That ($blankRes.PolicySourceCount -eq 0) `
        'an empty AGENTS.md counts as no law source, same as a deleted one' `
        "got: $($blankRes.PolicySourceCount)"

    # The false positive a rule-count check would raise. This project wrote its law down;
    # it just forbids nothing. It must stay quiet.
    $permissive     = New-PermissiveFixture -Name 'permissive'
    $permissiveWarn = $null
    $permissiveRes  = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
        -Mode 'dry-run' -SkipLedger -Policy -Halt -PolicyPath $permissive `
        -WarningVariable permissiveWarn -WarningAction SilentlyContinue
    Write-Host ("  permissive: evaluated={0} sources={1} rules={2} halts={3}" -f
        $permissiveRes.PolicyEvaluated, $permissiveRes.PolicySourceCount,
        $permissiveRes.PolicyRuleCount, $permissiveRes.PolicyHaltCount)

    Assert-That ($permissiveRes.PolicySourceCount -ge 1) `
        'lawful-but-permissive: PolicySourceCount >= 1' "got: $($permissiveRes.PolicySourceCount)"
    Assert-That ($permissiveRes.PolicyRuleCount -eq 0) `
        'lawful-but-permissive: PolicyRuleCount is 0, which is why rules cannot be the test'
    $permissiveText = (@($permissiveWarn) | ForEach-Object { [string]$_ }) -join ' // '
    Assert-That ($permissiveText -notmatch 'no law sources') `
        'lawful-but-permissive did NOT warn about missing law' "warnings: $permissiveText"

    # And the halting fixture read real law, so the counter is not stuck at zero.
    Assert-That ($observed.PolicySourceCount -ge 1) `
        'a fixture with real law reports PolicySourceCount >= 1' `
        "got: $($observed.PolicySourceCount)"
}
finally {
    foreach ($root in $script:TempRoots) {
        if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
    }
    Write-Host ("  cleaned {0} fixture(s) under `$env:TEMP" -f $script:TempRoots.Count)
}

# -- 6h: test 6 left no trace under the repo, and the chain file stays ignored.
$statusAfter = Get-RepoStatus
Assert-That ($statusAfter -eq $statusBefore) 'test 6 changed nothing git can see' `
    "before=[$statusBefore] after=[$statusAfter]"

$countAfter6 = (Get-LedgerVerify -LedgerPath $default).Count
Assert-That ($countAfter6 -eq $countBefore6) 'test 6 appended no receipts (-SkipLedger throughout)' `
    "before=$countBefore6 after=$countAfter6"

# git check-ignore exits 1 when a path is NOT ignored, which is a throw here by design.
# Asserting only "we did not land in the catch" is weak for the same reason as TEST 4: it
# passes if native errors ever stop being terminating. Take -v and assert on the rule it
# prints, so a pass means git named the pattern doing the ignoring.
$ignoreOut  = ''
$ignoreExit = -1
Push-Location -LiteralPath $repo
try {
    try {
        $ignoreOut  = (& git check-ignore -v -- '.ledger/ledger.jsonl' 2>&1 | Out-String).Trim()
        $ignoreExit = $LASTEXITCODE
    }
    catch {
        $ignoreExit = if ($LASTEXITCODE) { $LASTEXITCODE } else { 1 }
        $ignoreOut  = $_.Exception.Message
    }
}
finally { Pop-Location }

Assert-That ($ignoreExit -eq 0) '.ledger/ledger.jsonl is still gitignored' `
    "exit=$ignoreExit out=$ignoreOut"
Assert-That ($ignoreOut -match '\.gitignore:\d+:') `
    'git named the .gitignore rule doing it, not merely exited 0' $ignoreOut

# ---------------------------------------------------------------- 7
Write-Section 'TEST 7  schema and chain rejection, forged line by line'

# Every forgery below is built with the module's own canonicalizer, so it is byte-correct
# except for the single thing under test. Nothing is hand-typed: a forgery that was merely
# malformed would be caught by the JSON parser and would prove nothing about the schema.
# Files land in tests/sandbox/, which is gitignored, and are deleted at the end of the test.
$mod = Get-Module -Name 'Ledger'
if ($null -eq $mod) { throw 'Ledger module not loaded; TEST 7 cannot reach the canonicalizer' }

$script:ForgedFiles = [System.Collections.Generic.List[string]]::new()

function New-ForgedRecord {
    param(
        [Parameter(Mandatory)][string]$Ts,
        [Parameter(Mandatory)][int]$Attempt,
        [Parameter(Mandatory)][string]$Prev,
        [string]$Sha256 = ('a' * 64)
    )

    $canonical = & $mod {
        param($t, $a, $s, $p)
        ConvertTo-LedgerCanonicalJson -Ts $t -Attempt $a -Validator 'non_empty' `
            -Mode 'dry-run' -Model 'coverage' -Sha256 $s -Prev $p
    } $Ts $Attempt $Sha256 $Prev

    $self = & $mod { param($c) Get-LedgerSha256Hex -Text $c } $canonical

    return [pscustomobject]@{
        Canonical = $canonical
        Self      = $self
        Record    = ($canonical.Substring(0, $canonical.Length - 1) + ',"self":"' + $self + '"}')
    }
}

function Write-ForgedLedger {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string[]]$Lines)

    $path = Join-Path -Path $sandbox -ChildPath $Name
    [System.IO.File]::WriteAllText($path, (($Lines -join "`n") + "`n"),
        [System.Text.UTF8Encoding]::new($false))
    $script:ForgedFiles.Add($path)
    return $path
}

function Get-VerifyErrorId {
    param([Parameter(Mandatory)][string]$Path)
    try { $null = Get-LedgerVerify -LedgerPath $Path; return '' }
    catch { return $_.FullyQualifiedErrorId }
}

function Assert-Rejected {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$Lines,
        [Parameter(Mandatory)][string]$ExpectedId
    )

    $id = Get-VerifyErrorId -Path (Write-ForgedLedger -Name $Name -Lines $Lines)
    Write-Host ("  {0,-46} -> {1}" -f $Label, $(if ($id) { $id } else { 'ACCEPTED' }))
    Assert-That ($id -like "$ExpectedId*") $Label "expected $ExpectedId, got '$id'"
}

$g   = '0' * 64
$r1  = New-ForgedRecord -Ts '2026-01-01T00:00:00.000Z' -Attempt 1 -Prev $g
$r2  = New-ForgedRecord -Ts '2026-01-01T00:00:01.000Z' -Attempt 2 -Prev $r1.Self
$r3  = New-ForgedRecord -Ts '2026-01-01T00:00:02.000Z' -Attempt 3 -Prev $r2.Self

# Baseline. If this does not verify, every rejection below is meaningless.
$honest = Write-ForgedLedger -Name 'coverage_honest.jsonl' -Lines @($r1.Record, $r2.Record, $r3.Record)
$honestResult = Get-LedgerVerify -LedgerPath $honest
Assert-That ($honestResult.Ok -and $honestResult.Count -eq 3) `
    'baseline: an honestly forged 3-line chain verifies' "Count=$($honestResult.Count)"

# --- field set ---
Assert-Rejected -Label 'ninth key is rejected' -Name 'coverage_ninth.jsonl' `
    -ExpectedId 'LedgerBadRecord' `
    -Lines @($r1.Record.Substring(0, $r1.Record.Length - 1) + ',"note":"extra"}')

Assert-Rejected -Label 'missing key is rejected' -Name 'coverage_missing.jsonl' `
    -ExpectedId 'LedgerBadRecord' `
    -Lines @($r1.Record -replace ',"model":"coverage"', '')

Assert-Rejected -Label 'duplicate key is rejected' -Name 'coverage_dup.jsonl' `
    -ExpectedId 'LedgerBadRecord' `
    -Lines @($r1.Record.Substring(0, $r1.Record.Length - 1) + ',"ts":"2026-01-01T00:00:00.000Z"}')

# --- field types ---
Assert-Rejected -Label 'attempt as a JSON string is rejected' -Name 'coverage_type.jsonl' `
    -ExpectedId 'LedgerBadRecord' -Lines @($r1.Record -replace '"attempt":1', '"attempt":"1"')

Assert-Rejected -Label 'attempt as a JSON null is rejected' -Name 'coverage_null.jsonl' `
    -ExpectedId 'LedgerBadRecord' -Lines @($r1.Record -replace '"attempt":1', '"attempt":null')

Assert-Rejected -Label 'uppercase hex is rejected' -Name 'coverage_upper.jsonl' `
    -ExpectedId 'LedgerBadRecord' `
    -Lines @($r1.Record -replace ('"sha256":"' + ('a' * 64) + '"'), ('"sha256":"' + ('A' * 64) + '"'))

Assert-Rejected -Label 'a JSON array is not a record' -Name 'coverage_array.jsonl' `
    -ExpectedId 'LedgerCorruptLine' -Lines @('[1,2,3]')

# --- the chain itself ---
# Tamper a middle record's payload and leave its self alone: the self no longer describes
# the payload, so line 2 fails on its own terms before linkage is ever considered.
Assert-Rejected -Label 'mid-chain payload tamper is rejected' -Name 'coverage_midtamper.jsonl' `
    -ExpectedId 'LedgerBadSelf' `
    -Lines @($r1.Record, ($r2.Record -replace '"model":"coverage"', '"model":"tampered"'), $r3.Record)

# The sharper one: re-sign the middle record so its self is genuinely correct. Nothing is
# malformed and no self is wrong, so only prev == previous self can catch it. This is the
# branch a tip-only tamper test never reaches.
$r2Forged = New-ForgedRecord -Ts '2099-12-31T23:59:59.000Z' -Attempt 2 -Prev $r1.Self
Assert-Rejected -Label 'mid-chain re-forge breaks linkage' -Name 'coverage_broken.jsonl' `
    -ExpectedId 'LedgerBrokenChain' -Lines @($r1.Record, $r2Forged.Record, $r3.Record)

# Genesis is not decoration: line 1 must point at 64 zeros.
$badGenesis = New-ForgedRecord -Ts '2026-01-01T00:00:00.000Z' -Attempt 1 -Prev ('f' * 64)
Assert-Rejected -Label 'a non-genesis first prev is rejected' -Name 'coverage_genesis.jsonl' `
    -ExpectedId 'LedgerBrokenChain' -Lines @($badGenesis.Record)

# --- the hex anchor itself ---
# '^[0-9a-f]{64}$' accepts a trailing newline in .NET, because '$' matches before one.
# That is a hash with a byte welded to it, which would hash differently. \z does not.
$hexClean   = & $mod { param($v) Test-LedgerHex64 $v } ('a' * 64)
$hexNewline = & $mod { param($v) Test-LedgerHex64 $v } (('a' * 64) + "`n")
$hexShort   = & $mod { param($v) Test-LedgerHex64 $v } ('a' * 63)
$hexUpper   = & $mod { param($v) Test-LedgerHex64 $v } ('A' * 64)

Assert-That $hexClean          'Test-LedgerHex64 accepts 64 lowercase hex'
Assert-That (-not $hexNewline) 'Test-LedgerHex64 rejects 64 hex plus a trailing newline (\z, not $)'
Assert-That (-not $hexShort)   'Test-LedgerHex64 rejects 63 hex'
Assert-That (-not $hexUpper)   'Test-LedgerHex64 rejects uppercase hex'

# --- the real chain is untouched by any of it ---
Assert-That ((Get-LedgerVerify -LedgerPath $default).Ok) 'the real ledger still verifies after TEST 7'

# ---------------------------------------------------------------- 8
Write-Section 'TEST 8  the writer rehashes the output and will not sign what it cannot reproduce'

# A stub stands in for the interpreter. -PythonPath names the program Invoke-LedgerForce
# runs, so a .cmd that ignores its arguments and prints one canned NDJSON result event is
# enough to drive the PowerShell side with a hash of our choosing. The event line is written
# to a file and the stub just types it, which keeps cmd's quoting rules out of the test.
$stubOutput = "def add(a, b):`n    return a + b`n"
$stubGood   = & $mod { param($t) Get-LedgerSha256Hex -Text $t } $stubOutput
# Flip the first nibble to something it is not. Hard-coding a letter is how this test
# silently passed nothing once: the real digest already began with 'b'.
$stubBad    = $(if ($stubGood[0] -eq 'a') { 'b' } else { 'a' }) + $stubGood.Substring(1)

function New-SnakeStub {
    # The echoed mode/validator/model are parameters because TEST 10 needs a stub that
    # answers with a different run than the one it was asked for. Their defaults are the
    # values every call in TEST 8 passes on the command line, so an unqualified stub agrees
    # with its invocation and only the hash is ever in question.
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Sha256,
        [string]$EchoMode      = 'dry-run',
        [string]$EchoValidator = 'non_empty',
        [string]$EchoModel     = 'stub-model',
        [switch]$OmitModel
    )

    $utf8    = [System.Text.UTF8Encoding]::new($false)
    $payload = Join-Path -Path $sandbox -ChildPath "stub_$Name.ndjson"
    $cmd     = Join-Path -Path $sandbox -ChildPath "stub_$Name.cmd"

    $modelField = if ($OmitModel) { '' } else { ' "model": "' + $EchoModel + '",' }
    $event = '{"v": 1, "type": "result", "ok": true, "output": "def add(a, b):\n    return a + b\n",' +
             ' "attempts": 1, "sha256": "' + $Sha256 + '", "reason": "stub",' +
             ' "validator": "' + $EchoValidator + '",' + $modelField +
             ' "mode": "' + $EchoMode + '"}'

    [System.IO.File]::WriteAllText($payload, $event + "`n", $utf8)
    [System.IO.File]::WriteAllText($cmd, "@echo off`r`ntype `"$payload`"`r`n", $utf8)

    $script:ForgedFiles.Add($payload)
    $script:ForgedFiles.Add($cmd)
    return $cmd
}

$agreeStub    = New-SnakeStub -Name 'agree'    -Sha256 $stubGood
$mismatchStub = New-SnakeStub -Name 'mismatch' -Sha256 $stubBad
$stubLedger   = Join-Path -Path $sandbox -ChildPath 'stub_ledger.jsonl'
if (Test-Path -LiteralPath $stubLedger) { Remove-Item -LiteralPath $stubLedger -Force }
$script:ForgedFiles.Add($stubLedger)

Write-Host "  stub output hashes to $($stubGood.Substring(0, 12))..."
Write-Host "  mismatch stub will claim $($stubBad.Substring(0, 12))..."
Assert-That ($stubBad -ne $stubGood) 'the mismatch stub really does claim a different hash'

# 8a: the honest stub. Hashes agree, so the force completes and the receipt lands.
#
# -Model 'stub-model' is not decoration. The stub echoes "model": "stub-model", and without
# naming it here the caller asked for no model at all - so the receipt used to record a model
# nobody requested, and this check went green on it. The writer now records the model
# PowerShell asked for, so the only way this stub's echo reaches the chain is if the test
# asks for it by name. A receipt describing a run nobody ordered is not a passing test.
$agreed = Invoke-LedgerForce -Prompt 'stub' -Validator 'non_empty' -Mode 'dry-run' `
    -Model 'stub-model' -PythonPath $agreeStub -LedgerPath $stubLedger
Assert-That ($agreed.Sha256 -eq $stubGood) 'agree stub: reported hash survives the check' `
    "got $($agreed.Sha256)"
Assert-That ($agreed.Model -ceq 'stub-model') 'agree stub: the receipt records the model that was asked for' `
    "got $($agreed.Model)"
Assert-That ((Get-LedgerVerify -LedgerPath $stubLedger).Count -eq 1) `
    'agree stub: exactly one receipt was appended'

# 8b: the lying stub. The output is identical; only the claimed hash differs.
$mmThrew = $false
$mmId    = ''
try {
    Invoke-LedgerForce -Prompt 'stub' -Validator 'non_empty' -Mode 'dry-run' `
        -PythonPath $mismatchStub -LedgerPath $stubLedger | Out-Null
}
catch {
    $mmThrew = $true
    $mmId    = $_.FullyQualifiedErrorId
    Write-Host ''
    Write-Host '  --- TERMINATING ERROR CAUGHT (expected) ---' -ForegroundColor Yellow
    Write-Host "  FullyQualifiedErrorId : $mmId"
    Write-Host "  Message               : $($_.Exception.Message)"
    Write-Host ''
}

Assert-That $mmThrew 'mismatch stub: a hash that does not match its output throws'
Assert-That ($mmId -like 'LedgerOutputHashMismatch*') 'error id is LedgerOutputHashMismatch' `
    "got: $mmId"
Assert-That ((Get-LedgerVerify -LedgerPath $stubLedger).Count -eq 1) `
    'mismatch stub: no receipt was appended for output the writer cannot reproduce'

# 8c: the gate sits before -SkipLedger returns, not merely before the append. Output whose
#     hash is wrong is wrong whether or not anyone was going to write it down.
$mmSkipThrew = $false
$mmSkipId    = ''
try {
    Invoke-LedgerForce -Prompt 'stub' -Validator 'non_empty' -Mode 'dry-run' `
        -PythonPath $mismatchStub -SkipLedger | Out-Null
}
catch { $mmSkipThrew = $true; $mmSkipId = $_.FullyQualifiedErrorId }

Assert-That $mmSkipThrew 'mismatch stub: -SkipLedger does not excuse a bad hash'
Assert-That ($mmSkipId -like 'LedgerOutputHashMismatch*') `
    '-SkipLedger path raises the same ErrorId' "got: $mmSkipId"

# 8d: an otherwise honest digest in uppercase. The bytes are right and the encoding is not,
#     and the compare is -cne, so the gate refuses it here rather than letting it travel on
#     to Add-LedgerRecord for a different ErrorId. Get-LedgerVerify already rejects uppercase
#     hex on the way back in (TEST 7); this is the same law applied on the way out.
$stubUpper = $stubGood.ToUpperInvariant()
Assert-That ($stubUpper -cne $stubGood) 'the uppercase digest really is a different string' `
    'a digest of digits only would make this test vacuous'
Assert-That ($stubUpper.ToLowerInvariant() -ceq $stubGood) `
    'and it is otherwise the honest digest, differing in case alone'

$upperStub  = New-SnakeStub -Name 'upper' -Sha256 $stubUpper
$upperBefore = (Get-LedgerVerify -LedgerPath $stubLedger).Count
$upThrew = $false
$upId    = ''
try {
    Invoke-LedgerForce -Prompt 'stub' -Validator 'non_empty' -Mode 'dry-run' `
        -Model 'stub-model' -PythonPath $upperStub -LedgerPath $stubLedger | Out-Null
}
catch { $upThrew = $true; $upId = $_.FullyQualifiedErrorId }

Write-Host "  uppercase stub: $upId"
Assert-That $upThrew 'uppercase hex of an honest digest still throws'
Assert-That ($upId -like 'LedgerOutputHashMismatch*') `
    'uppercase hex fails as LedgerOutputHashMismatch, not further down' "got: $upId"
Assert-That ((Get-LedgerVerify -LedgerPath $stubLedger).Count -eq $upperBefore) `
    'uppercase hex appended no receipt'

# And -SkipLedger is not a way round it: uppercase must not be a silent pass just because
# nothing was going to be written.
$upSkipThrew = $false
$upSkipId    = ''
try {
    Invoke-LedgerForce -Prompt 'stub' -Validator 'non_empty' -Mode 'dry-run' `
        -Model 'stub-model' -PythonPath $upperStub -SkipLedger | Out-Null
}
catch { $upSkipThrew = $true; $upSkipId = $_.FullyQualifiedErrorId }

Assert-That $upSkipThrew 'uppercase hex under -SkipLedger throws too'
Assert-That ($upSkipId -like 'LedgerOutputHashMismatch*') `
    '-SkipLedger raises the same ErrorId for uppercase hex' "got: $upSkipId"

# ---------------------------------------------------------------- 9
Write-Section 'TEST 9  a halt writes no receipt, with no -SkipLedger to hide behind'

# Every -Halt exercise in TEST 6 passes -SkipLedger, so none of them can tell "the halt
# stopped the append" from "-SkipLedger stopped the append". This one points at a real
# ledger path that does not exist yet: if anything were written, the file would appear.
$haltLedger = Join-Path -Path $sandbox -ChildPath 'halt_no_skip.jsonl'
if (Test-Path -LiteralPath $haltLedger) { Remove-Item -LiteralPath $haltLedger -Force }
$script:ForgedFiles.Add($haltLedger)

$haltFixture  = New-PolicyFixture -Name 'halt-no-skip'
$haltNsThrew  = $false
$haltNsId     = ''
try {
    Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' -Mode 'dry-run' `
        -Policy -Halt -PolicyPath $haltFixture -LedgerPath $haltLedger | Out-Null
}
catch { $haltNsThrew = $true; $haltNsId = $_.FullyQualifiedErrorId }

Write-Host "  halt without -SkipLedger: $haltNsId"
Assert-That $haltNsThrew '-Policy -Halt throws without -SkipLedger'
Assert-That ($haltNsId -like 'InspectorPolicyHalt*') `
    'still Inspector''s own ErrorId, unwrapped' "got: $haltNsId"
Assert-That (-not (Test-Path -LiteralPath $haltLedger)) `
    'a halt created no ledger file at all: the append never ran' $haltLedger

# ---------------------------------------------------------------- 10
Write-Section 'TEST 10  the result must describe the run that was asked for'

# TEST 8 asks whether the hash matches the output. This asks the prior question: whether the
# result came from the invocation at all. A stub that echoes a mode, validator or model other
# than the one on the command line is a stale process, the wrong process, or a liar, and a
# receipt about it would be a claim this module cannot stand behind.
$mismLedger = Join-Path -Path $sandbox -ChildPath 'mismatch_ledger.jsonl'
if (Test-Path -LiteralPath $mismLedger) { Remove-Item -LiteralPath $mismLedger -Force }
$script:ForgedFiles.Add($mismLedger)

function Get-ForceErrorId {
    param([Parameter(Mandatory)][hashtable]$Splat)
    try { Invoke-LedgerForce @Splat | Out-Null; return '' }
    catch { return [string]$_.FullyQualifiedErrorId }
}

# 10a: the mode came back wrong. The hash is honest, so nothing but the echo can fail this.
$modeStub = New-SnakeStub -Name 'mode-mismatch' -Sha256 $stubGood -EchoMode 'live'
$modeId = Get-ForceErrorId @{
    Prompt = 'stub'; Validator = 'non_empty'; Mode = 'dry-run'; Model = 'stub-model'
    PythonPath = $modeStub; LedgerPath = $mismLedger
}
Write-Host "  mode echo 'live' against -Mode dry-run: $modeId"
Assert-That ($modeId -like 'LedgerResultMismatch*') `
    'a mode the caller never asked for throws LedgerResultMismatch' "got: $modeId"

# 10b: the validator came back wrong.
$valStub = New-SnakeStub -Name 'validator-mismatch' -Sha256 $stubGood -EchoValidator 'is_json'
$valId = Get-ForceErrorId @{
    Prompt = 'stub'; Validator = 'non_empty'; Mode = 'dry-run'; Model = 'stub-model'
    PythonPath = $valStub; LedgerPath = $mismLedger
}
Write-Host "  validator echo 'is_json' against -Validator non_empty: $valId"
Assert-That ($valId -like 'LedgerResultMismatch*') `
    'a validator the caller never asked for throws LedgerResultMismatch' "got: $valId"

# 10c: the comparison is case-sensitive. 'Dry-Run' is not 'dry-run', and a receipt is a
#      literal record - the same reason the chain's hex is compared with -cne.
$caseStub = New-SnakeStub -Name 'case-mismatch' -Sha256 $stubGood -EchoMode 'Dry-Run'
$caseId = Get-ForceErrorId @{
    Prompt = 'stub'; Validator = 'non_empty'; Mode = 'dry-run'; Model = 'stub-model'
    PythonPath = $caseStub; LedgerPath = $mismLedger
}
Write-Host "  mode echo 'Dry-Run' against -Mode dry-run: $caseId"
Assert-That ($caseId -like 'LedgerResultMismatch*') `
    'the echo compare is case-sensitive' "got: $caseId"

# 10d: -Model was named, and the echo disagrees with it.
$modelStub = New-SnakeStub -Name 'model-mismatch' -Sha256 $stubGood -EchoModel 'some-other-model'
$modelId = Get-ForceErrorId @{
    Prompt = 'stub'; Validator = 'non_empty'; Mode = 'dry-run'; Model = 'stub-model'
    PythonPath = $modelStub; LedgerPath = $mismLedger
}
Write-Host "  model echo 'some-other-model' against -Model stub-model: $modelId"
Assert-That ($modelId -like 'LedgerResultMismatch*') `
    'a named -Model that comes back different throws LedgerResultMismatch' "got: $modelId"

Assert-That (-not (Test-Path -LiteralPath $mismLedger)) `
    'not one of the four mismatches created a ledger file' $mismLedger

# 10e: -Model omitted. There is nothing to hold the snake to, so nothing throws - and the
#      receipt records the model PowerShell put on the command line, which is the parameter
#      default, not the snake's echo. This is the documented exemption, pinned.
$omitted = Invoke-LedgerForce -Prompt 'stub' -Validator 'non_empty' -Mode 'dry-run' `
    -PythonPath $modelStub -LedgerPath $mismLedger
Write-Host "  -Model omitted, stub echoed 'some-other-model', recorded: $($omitted.Model)"
Assert-That ($omitted.Model -cne 'some-other-model') `
    'with -Model omitted the receipt does not record the snake''s echo' "got: $($omitted.Model)"
# Read the declared default off the AST rather than hard-coding it here, so renaming the
# default model stays a one-line change in the module and does not silently rot this check.
$declaredModel = @(
    (Get-Command Invoke-LedgerForce).ScriptBlock.Ast.Body.ParamBlock.Parameters |
        Where-Object { $_.Name.VariablePath.UserPath -eq 'Model' } |
        ForEach-Object { [string]$_.DefaultValue.Value }
)[0]
Write-Host "  declared -Model default: $declaredModel"
Assert-That (-not [string]::IsNullOrWhiteSpace($declaredModel)) `
    'the module declares a default -Model, so there is something to record'
Assert-That ($omitted.Model -ceq $declaredModel) `
    'it records the parameter default - what PowerShell asked for' `
    "expected=$declaredModel got=$($omitted.Model)"
$omittedEntry = Get-LedgerEntry -LedgerPath $mismLedger -Last 1
Assert-That ($omittedEntry.Model -ceq $omitted.Model) `
    'and the line on disk says the same thing the result object does' `
    "result=$($omitted.Model) record=$($omittedEntry.Model)"

# 10f: a result event that omits a field is not claiming anything, so it is not a mismatch.
$silentStub = New-SnakeStub -Name 'model-omitted' -Sha256 $stubGood -OmitModel
$silent = Invoke-LedgerForce -Prompt 'stub' -Validator 'non_empty' -Mode 'dry-run' `
    -Model 'named-by-the-caller' -PythonPath $silentStub -LedgerPath $mismLedger
Assert-That ($silent.Model -ceq 'named-by-the-caller') `
    'an event that omits model is silent, not wrong: the invocation stands' "got: $($silent.Model)"

# 10g: attempts is not verified and is not claimed to be. The stub reports 1 attempt for a
#      loop PowerShell never watched, and the module records that number as given.
Assert-That ($silent.Attempts -eq 1) `
    'attempts is recorded as reported - PowerShell cannot attest to a loop it did not see' `
    "got: $($silent.Attempts)"

foreach ($path in $script:ForgedFiles) {
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
}
Remove-Item -LiteralPath $haltFixture -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("  cleaned {0} forged file(s) from tests/sandbox" -f $script:ForgedFiles.Count)

# ---------------------------------------------------------------- tail
Write-Section 'FINAL LEDGER TAIL'
Get-LedgerEntry -LedgerPath $default -Last 3 |
    Format-List Line, Ts, Attempt, Validator, Mode, Model, Sha256, Prev, Self |
    Out-String | Write-Host

$final = Get-LedgerVerify -LedgerPath $default
Write-Host "Path     : $($final.Path)"
Write-Host "Count    : $($final.Count)"
Write-Host "Ok       : $($final.Ok)"
Write-Host "FirstTs  : $($final.FirstTs)"
Write-Host "LastTs   : $($final.LastTs)"
Write-Host "LastSelf : $($final.LastSelf)"

Write-Host ''
Write-Host "checks run: $($script:Checks)"
if ($script:Failures -eq 0) {
    Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
    exit 0
}
Write-Host "$($script:Failures) CHECK(S) FAILED" -ForegroundColor Red
exit 1
