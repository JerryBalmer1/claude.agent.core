#Requires -Version 7.4
<#
.SYNOPSIS
    Part of the CI check "requires-header": Python is allowed only where config/repo.json says.

.DESCRIPTION
    Substrate vendors the Ledger snake, and the snake is Python. That permission was granted
    by the substrate-cutover run order, which also draws the boundary: Python 3.10+ under
    modules/ledger/python/, nowhere else. A permission with no boundary is not a permission,
    it is an absence of one.

    This runs as a SECOND STEP of the existing `requires-header` job rather than as a new job.
    The job key is the check name GitHub reports and the automerge workflow waits on, and
    config/repo.json -> required_checks is asserted to equal the set of job keys. Adding a job
    would mean adding a required check name, which the run order forbids in this phase - a
    newly required check that branch protection does not know about is a check that can go red
    while the merge proceeds anyway.

    Two assertions:

    1. Every TRACKED .py file sits under one of runtimes.python.allowed_under. Tracked, via
       `git ls-files`, for the reason recorded in closeout FINDINGS F-C6: a check that scanned
       untracked files would fail on scratch work, and anything not tracked is not in the repo.
       The consequence is the same trap - run this AFTER `git add`, not before.

    2. runtimes.powershell equals scripts.requires_version. The run order specifies both, so
       the repository now states its PowerShell floor twice. This is the assertion that stops
       them drifting apart; without it the second statement is decoration.

    Note the asymmetry: absence of .py files is a PASS here, unlike requires-header, which
    fails when it finds no .ps1 at all. It is not the same situation. "No PowerShell in a
    PowerShell repo" means the check is pointed at the wrong tree; "no Python" is the normal
    state of substrate until Phase 4 lands the snake.

.EXAMPLE
    pwsh -NoProfile -File scripts/ci/Test-Runtimes.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config   = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)

$allowed = @($config.runtimes.python.allowed_under)
$failures = 0

Write-Host "runtimes: python $($config.runtimes.python.version)+ allowed under: $($allowed -join ', ')"

# ------------------------------------------------------------------ 1/2 python placement

Push-Location $RepoRoot
try {
    $py = @(git ls-files -- '*.py' | Where-Object { $_ -notmatch '^vendor/' })
}
finally { Pop-Location }

if ($py.Count -eq 0) {
    Write-Host '  none   no tracked .py files; substrate carries no Python until the ledger module lands'
}
else {
    foreach ($rel in $py) {
        $normal = $rel.Replace('\', '/')
        $ok = [bool](@($allowed | Where-Object { $normal.StartsWith($_, [System.StringComparison]::Ordinal) }).Count)
        if ($ok) {
            Write-Host "  OK     $normal"
        }
        else {
            Write-Host "  DENIED $normal -- outside every allowed_under prefix"
            $failures++
        }
    }
    Write-Host "runtimes: $($py.Count) tracked .py file(s) checked"
}

# ------------------------------------------------------------------ 2/2 the floor agrees with itself

$declared = $config.runtimes.powershell
$floor    = $config.scripts.requires_version
if ($declared -ceq $floor) {
    Write-Host "  OK     runtimes.powershell '$declared' equals scripts.requires_version '$floor'"
}
else {
    Write-Host "  DENIED runtimes.powershell '$declared' does not equal scripts.requires_version '$floor'"
    Write-Host '         the repository would state two different PowerShell floors and enforce the other one'
    $failures++
}

Write-Host ''
if ($failures -gt 0) {
    Write-Host "runtimes: FAIL -- $failures violation(s)"
    exit 1
}
Write-Host 'runtimes: PASS'
exit 0
