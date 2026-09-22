#Requires -Version 7.4
<#
.SYNOPSIS
    Per-module Pester counts, measured from `(Invoke-Pester -PassThru).Tests` and nothing else.

.DESCRIPTION
    `scripts/ci/Invoke-Tests.ps1` answers one question -- did the suite pass -- and prints one
    total. The release needs a finer number: how many tests each module actually contributes, so
    that README.md and REPORT.md can state a per-module figure that a reader can reproduce
    instead of a figure someone added up by hand.

    The bucket for a test is the FILE IT CAME FROM, read off the test object itself
    (`$test.ScriptBlock.File`), not the Pester root it was collected under. A test declared in
    `modules/ledger/tests/ledger.Tests.ps1` counts to `ledger` no matter how the run was
    invoked, and a test that somehow lands outside `tests/` or `modules/<n>/tests/` shows up in
    its own row rather than being quietly folded into a module's number.

    The same Pester version is pinned the same way, from config/repo.json -> tooling.pester. Two
    scripts that measure the same suite under different runners are two different measurements.

    Exits 1 if any test failed, if the suite ran zero tests, or if the per-file rows do not add
    up to Pester's own TotalCount. That last one is the check on this script rather than on the
    repository: a bucketing bug that dropped a file would otherwise print a smaller, tidier and
    entirely wrong table.

.PARAMETER Json
    Optional path. Writes the same measurement as JSON, for a document that wants to be
    generated rather than typed.

.EXAMPLE
    pwsh -NoProfile -File scripts/Measure-Modules.ps1

.EXAMPLE
    pwsh -NoProfile -File scripts/Measure-Modules.ps1 -Json docs/plans/2026-09-22-substrate-cutover/modules.json
#>
[CmdletBinding()]
param(
    [string]$Json
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path $PSScriptRoot -Parent
$config   = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)
$pinned   = $config.tooling.pester

# Same roots as the CI check, discovered the same way, for the same reason: a listed root is a
# second place to forget a module.
$testPath = [System.Collections.Generic.List[string]]::new()
$testPath.Add((Join-Path $RepoRoot 'tests'))

$modulesRoot = Join-Path $RepoRoot 'modules'
if (Test-Path -LiteralPath $modulesRoot -PathType Container) {
    foreach ($dir in (Get-ChildItem -LiteralPath $modulesRoot -Directory | Sort-Object Name)) {
        $candidate = Join-Path $dir.FullName 'tests'
        if (Test-Path -LiteralPath $candidate -PathType Container) { $testPath.Add($candidate) }
    }
}

Write-Host "measure-modules: pinned Pester $pinned (config/repo.json -> tooling.pester)"

$have = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version.ToString() -eq $pinned } |
        Select-Object -First 1

if (-not $have) {
    Write-Host "measure-modules: $pinned not installed, installing from PSGallery"
    Install-Module -Name Pester -RequiredVersion $pinned -Force -SkipPublisherCheck `
                   -Scope CurrentUser -AllowClobber -ErrorAction Stop
}

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -RequiredVersion $pinned -Force -ErrorAction Stop

$pc = New-PesterConfiguration
$pc.Run.Path           = $testPath.ToArray()
$pc.Run.PassThru       = $true
$pc.Output.Verbosity   = 'None'
$pc.TestResult.Enabled = $false

$result = Invoke-Pester -Configuration $pc

# ---------------------------------------------------------------- bucket every test by its file

$rows = [System.Collections.Generic.List[object]]::new()
foreach ($test in $result.Tests) {
    $file = $test.ScriptBlock.File
    if ([string]::IsNullOrWhiteSpace($file)) {
        throw 'a test reported no source file; the bucketing below would be a guess'
    }
    $relative = [System.IO.Path]::GetRelativePath($RepoRoot, $file).Replace('\', '/')
    $parts    = $relative -split '/'
    $bucket   = if ($parts[0] -eq 'modules' -and $parts.Count -gt 1) { $parts[1] } else { 'repo' }

    $rows.Add([pscustomobject]@{
        Bucket = $bucket
        File   = $relative
        Result = $test.Result
    })
}

function Format-Group {
    param([Parameter(Mandatory)][object[]]$Rows, [Parameter(Mandatory)][string]$Name)
    [pscustomobject]@{
        Name    = $Name
        Total   = $Rows.Count
        Passed  = @($Rows | Where-Object { $_.Result -eq 'Passed'  }).Count
        Failed  = @($Rows | Where-Object { $_.Result -eq 'Failed'  }).Count
        Skipped = @($Rows | Where-Object { $_.Result -eq 'Skipped' }).Count
    }
}

$byFile = foreach ($g in ($rows | Group-Object File | Sort-Object Name)) {
    $r = Format-Group -Rows @($g.Group) -Name $g.Name
    [pscustomobject]@{
        Bucket = @($g.Group)[0].Bucket
        File   = $g.Name
        Total  = $r.Total; Passed = $r.Passed; Failed = $r.Failed; Skipped = $r.Skipped
    }
}

$byBucket = foreach ($g in ($rows | Group-Object Bucket | Sort-Object Name)) {
    Format-Group -Rows @($g.Group) -Name $g.Name
}

Write-Host ''
Write-Host 'per file'
$byFile | Format-Table -AutoSize -Property Bucket, File, Total, Passed, Failed, Skipped | Out-String -Width 160 | Write-Host

Write-Host 'per module  (bucket "repo" is tests/ at the repository root)'
$byBucket | Format-Table -AutoSize -Property Name, Total, Passed, Failed, Skipped | Out-String -Width 160 | Write-Host

$sum = ($byBucket | Measure-Object -Property Total -Sum).Sum
Write-Host ("measure-modules: total={0} passed={1} failed={2} skipped={3} duration={4}" -f
    $result.TotalCount, $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.Duration)

if ($Json) {
    $payload = [ordered]@{
        measured   = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        pester     = $pinned
        head       = (& git -C $RepoRoot rev-parse HEAD).Trim()
        total      = $result.TotalCount
        passed     = $result.PassedCount
        failed     = $result.FailedCount
        skipped    = $result.SkippedCount
        byModule   = @($byBucket)
        byFile     = @($byFile)
    }
    # An absolute path must survive: the release verifier calls this script with a scratch path
    # OUTSIDE the repository, because a measurement that dirties the tree it is measuring is not
    # a measurement anyone can run before a commit. Join-Path of a repo root and an absolute path
    # produces neither.
    $full = if ([System.IO.Path]::IsPathRooted($Json)) { [System.IO.Path]::GetFullPath($Json) }
            else { [System.IO.Path]::GetFullPath((Join-Path $RepoRoot $Json)) }
    [System.IO.File]::WriteAllText($full, (ConvertTo-Json $payload -Depth 8), [System.Text.UTF8Encoding]::new($false))
    Write-Host "measure-modules: wrote $full"
}

if ($result.TotalCount -eq 0) {
    Write-Host 'measure-modules: FAIL -- the suite ran zero tests'
    exit 1
}
if ($sum -ne $result.TotalCount) {
    Write-Host "measure-modules: FAIL -- rows sum to $sum but Pester counted $($result.TotalCount); the bucketing dropped something"
    exit 1
}
if ($result.FailedCount -gt 0) {
    Write-Host "measure-modules: FAIL -- $($result.FailedCount) test(s) failed"
    exit 1
}
Write-Host 'measure-modules: PASS'
exit 0
