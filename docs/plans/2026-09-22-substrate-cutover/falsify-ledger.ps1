#Requires -Version 7.4
<#
.SYNOPSIS
    Plant one defect at a time in modules/ledger, run its Pester suites, and report which
    checks went red. Produces the falsification table in FINDINGS.md.

.DESCRIPTION
    A suite that has never been shown to fail is a suite nobody has tested. This script is
    how the numbers in FINDINGS F41 were measured, and it is committed so they can be
    measured again rather than believed.

    EACH DEFECT IS PLANTED IN THE REAL TREE AND THEN REVERTED WITH GIT. A throwaway copy
    under the temp root was the first design and it does not work here: the suites resolve
    config/repo.json, .gitignore and the modules/ directory from the repository root, so a
    copy would fail for reasons that have nothing to do with the defect. Reverting with
    `git checkout --` restores bytes rather than approximating them, and the script asserts
    a clean tree after every single round -- if it cannot, it stops immediately rather than
    planting the next defect on top of the last one.

    RUN IT ON A CLEAN TREE. It refuses otherwise, because it cannot tell your edits from
    its own and `git checkout --` would discard them.

    A defect that does NOT go red is reported and kept in the table. A falsification table
    listing only the plants that worked is a table edited to flatter the suite.

.EXAMPLE
    pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/falsify-ledger.ps1

.EXAMPLE
    pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/falsify-ledger.ps1 -Only 'lock'
#>
[CmdletBinding()]
param(
    # Substring filter over defect names; omit to run all of them.
    [string]$Only,

    # Internal. The script re-invokes ITSELF with this to run the two suites in a child
    # process and write the result as JSON. Not a style preference: running Invoke-Pester
    # in-process leaks variables from inside the tests back into this script's scope --
    # measured, when `foreach ($d in $script:TempDirs)` in a cleanup It overwrote the
    # harness's own `$d` loop variable and the next round tried to read .Name off a
    # temp-directory path. A child process cannot do that, and it also guarantees each
    # round loads the patched module from disk rather than a cached one.
    [string]$RunSuitesTo
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot   = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$ModuleRoot = Join-Path $RepoRoot 'modules' 'ledger'
$Psm1       = Join-Path $ModuleRoot 'ledger.psm1'
$Psd1       = Join-Path $ModuleRoot 'ledger.psd1'
$Snake      = Join-Path $ModuleRoot 'python' 'snake.py'
$SuitePaths = @(
    (Join-Path $ModuleRoot 'tests' 'ledger.Tests.ps1'),
    (Join-Path $ModuleRoot 'tests' 'python.Tests.ps1')
)
$PinnedPester = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw |
    ConvertFrom-Json -Depth 20).tooling.pester

# ---------------------------------------------------------------- child mode
if ($RunSuitesTo) {
    Import-Module Pester -RequiredVersion $PinnedPester -Force -ErrorAction Stop
    $pc = New-PesterConfiguration
    $pc.Run.Path         = $SuitePaths
    $pc.Run.PassThru     = $true
    $pc.Output.Verbosity = 'None'
    $r = Invoke-Pester -Configuration $pc
    [pscustomobject]@{
        Total  = $r.TotalCount
        Passed = $r.PassedCount
        Red    = @($r.Failed | ForEach-Object { $_.ExpandedPath })
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $RunSuitesTo -Encoding utf8
    exit 0
}

function Test-TreeClean {
    Push-Location $RepoRoot
    try { return -not @(git status --porcelain -- 'modules/ledger') }
    finally { Pop-Location }
}

function Restore-Tree {
    Push-Location $RepoRoot
    try {
        git checkout -- 'modules/ledger'
        git clean -fdq -- 'modules/ledger'
    }
    finally { Pop-Location }
}

function Edit-File {
    param([string]$Path, [string]$From, [string]$To)
    $text = [System.IO.File]::ReadAllText($Path)
    if (-not $text.Contains($From)) { throw "falsify: anchor not found in $Path -- '$From'" }
    [System.IO.File]::WriteAllText($Path, $text.Replace($From, $To),
        [System.Text.UTF8Encoding]::new($false))
}

function Add-Bytes {
    param([string]$Path, [string]$Text)
    [System.IO.File]::AppendAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

$defects = @(
    @{ Name = 'none (control)'; Apply = { } }

    @{ Name = 'a byte appended to ledger.psm1'
       Apply = { Add-Bytes -Path $Psm1 -Text ' ' } }

    @{ Name = 'a byte appended to python/snake.py'
       Apply = { Add-Bytes -Path $Snake -Text "`n" } }

    @{ Name = 'a fifth name in ledger.psd1 FunctionsToExport ONLY'
       Apply = { Edit-File -Path $Psd1 -From "'Get-LedgerEntry')" -To "'Get-LedgerEntry', 'Get-LedgerNothing')" } }

    @{ Name = 'a second REAL export (defined and exported)'
       Apply = {
            Edit-File -Path $Psm1 -From "New-Alias -Name 'ledger-force'" `
                -To "function Get-LedgerNothing { 'nothing' }`nNew-Alias -Name 'ledger-force'"
            Edit-File -Path $Psm1 -From "'Get-LedgerVerify', 'Get-LedgerEntry' -Alias" `
                -To "'Get-LedgerVerify', 'Get-LedgerEntry', 'Get-LedgerNothing' -Alias"
            Edit-File -Path $Psd1 -From "'Get-LedgerEntry')" -To "'Get-LedgerEntry', 'Get-LedgerNothing')"
       } }

    @{ Name = 'a ConvertTo-Json call inside Add-LedgerRecord'
       Apply = { Edit-File -Path $Psm1 -From "    `$dir = [System.IO.Path]::GetDirectoryName(`$Path)" `
            -To "    `$echo = ConvertTo-Json @{ p = `$Path } -Compress`n    `$dir = [System.IO.Path]::GetDirectoryName(`$Path)" } }

    @{ Name = 'the writer drops the exclusive lock (FileShare.None -> Read)'
       Apply = { Edit-File -Path $Psm1 -From '[System.IO.FileShare]::None)' -To '[System.IO.FileShare]::ReadWrite)' } }

    @{ Name = 'the canonicalizer emits mode and model in the wrong order'
       Apply = {
            Edit-File -Path $Psm1 `
                -From "',`"mode`":'    + (ConvertTo-LedgerJsonString `$Mode)      +`n           ',`"model`":'   + (ConvertTo-LedgerJsonString `$Model)     +" `
                -To   "',`"model`":'   + (ConvertTo-LedgerJsonString `$Model)     +`n           ',`"mode`":'    + (ConvertTo-LedgerJsonString `$Mode)      +"
       } }

    @{ Name = 'an error id renamed (LedgerBadSelf -> LedgerSelfMismatch)'
       Apply = { Edit-File -Path $Psm1 -From "-Id 'LedgerBadSelf'" -To "-Id 'LedgerSelfMismatch'" } }

    @{ Name = 'LedgerReceipt.ps1 dropped into the module'
       Apply = {
            [System.IO.File]::WriteAllText((Join-Path $ModuleRoot 'LedgerReceipt.ps1'),
                "#Requires -Version 7.4`n# the second chain, which F29 says belongs elsewhere`n",
                [System.Text.UTF8Encoding]::new($false))
       } }

    @{ Name = 'the verifier stops checking prev linkage'
       Apply = { Edit-File -Path $Psm1 -From 'if ($entry.Prev -ne $expectedPrev) {' -To 'if ($false) {' } }
)

if (-not (Test-TreeClean)) {
    Write-Host 'falsify: modules/ledger is dirty. Commit or stash first -- this script reverts with git checkout.'
    exit 1
}

$rows  = [System.Collections.Generic.List[object]]::new()
$scrap = Join-Path ([System.IO.Path]::GetTempPath()) ('falsify-' + [guid]::NewGuid().ToString('N'))
$null  = New-Item -ItemType Directory -Path $scrap -Force
$round = 0

foreach ($defect in $defects) {
    if ($Only -and $defect.Name -notlike "*$Only*") { continue }
    $round++
    $name = [string]$defect.Name

    Write-Host ''
    Write-Host "=== planting: $name" -ForegroundColor Cyan
    try {
        & $defect.Apply

        $outFile = Join-Path $scrap "round-$round.json"
        & (Get-Process -Id $PID).Path -NoProfile -File $PSCommandPath -RunSuitesTo $outFile |
            Out-Null
        $result = Get-Content -LiteralPath $outFile -Raw | ConvertFrom-Json -Depth 5

        $failed = @($result.Red)
        $rows.Add([pscustomobject]@{
            Defect = $name
            Score  = "$($result.Passed)/$($result.Total)"
            Red    = $failed.Count
            Checks = $failed
        })
        Write-Host ("    {0}  ({1} red)" -f "$($result.Passed)/$($result.Total)", $failed.Count)
        foreach ($f in $failed) { Write-Host "      RED  $f" -ForegroundColor Yellow }
    }
    finally {
        Restore-Tree
        if (-not (Test-TreeClean)) {
            Write-Host 'falsify: FAILED TO RESTORE modules/ledger. Stopping before planting anything else.'
            exit 1
        }
    }
}

Write-Host ''
Write-Host '=== falsification table ===' -ForegroundColor Cyan
Write-Host '| Planted defect | Score | Red |'
Write-Host '|---|---|---|'
foreach ($r in $rows) {
    $red = if ($r.Red -eq 0) { '**none**' } else { $r.Red.ToString() }
    Write-Host ("| {0} | {1} | {2} |" -f $r.Defect, $r.Score, $red)
}

Write-Host ''
foreach ($r in $rows | Where-Object { $_.Red -gt 0 }) {
    Write-Host "$($r.Defect):"
    foreach ($c in $r.Checks) { Write-Host "    $c" }
}

$control = $rows | Where-Object { $_.Defect -eq 'none (control)' }
if ($control -and $control.Red -gt 0) {
    Write-Host ''
    Write-Host 'falsify: the CONTROL went red. Every row below it is meaningless.'
    exit 1
}
exit 0
