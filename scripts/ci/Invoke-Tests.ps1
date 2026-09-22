#Requires -Version 7.4
<#
.SYNOPSIS
    CI check "pester": runs tests/ and every modules/<name>/tests/ under the exact Pester version
    pinned in config/repo.json.

.DESCRIPTION
    The version is PINNED, from config/repo.json -> tooling.pester, and imported with
    -RequiredVersion. A suite whose runner floats is not a control: a green that came from a
    different Pester than the one the result was recorded under proves less than it looks like.

    Windows images ship a signed Pester 3.4.0 in the system module path, whose command surface
    is incompatible with 5.x. -SkipPublisherCheck and an explicit -RequiredVersion import are
    what stop that one being picked up.

    Exits 1 if any test fails AND if the suite ran zero tests. An empty suite reports zero
    failures, which is the most flattering possible lie a test runner can tell.

.EXAMPLE
    pwsh -NoProfile -File scripts/ci/Invoke-Tests.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config   = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)
$pinned   = $config.tooling.pester

# tests/ plus every modules/<name>/tests/ that exists. A module's suite lives beside the module it
# tests, so a module is one directory and not two, and the roots are DISCOVERED rather than listed:
# a list is a second place to forget, and a module whose tests are silently not collected is a
# module whose tests do not run while the check stays green. Pester's own *.Tests.ps1 filter is what
# keeps modules/<name>/tests/sandbox/ and modules/<name>/tests/fixtures/ out of the run.
$testPath = [System.Collections.Generic.List[string]]::new()
$testPath.Add((Join-Path $RepoRoot 'tests'))

$modulesRoot = Join-Path $RepoRoot 'modules'
if (Test-Path -LiteralPath $modulesRoot -PathType Container) {
    foreach ($dir in (Get-ChildItem -LiteralPath $modulesRoot -Directory | Sort-Object Name)) {
        $candidate = Join-Path $dir.FullName 'tests'
        if (Test-Path -LiteralPath $candidate -PathType Container) { $testPath.Add($candidate) }
    }
}

Write-Host "pester: pinned version $pinned (config/repo.json -> tooling.pester)"
foreach ($p in $testPath) {
    Write-Host ("pester: root {0}" -f [System.IO.Path]::GetRelativePath($RepoRoot, $p).Replace('\', '/'))
}

$have = Get-Module -ListAvailable -Name Pester |
        Where-Object { $_.Version.ToString() -eq $pinned } |
        Select-Object -First 1

if (-not $have) {
    Write-Host "pester: $pinned not installed, installing from PSGallery"
    Install-Module -Name Pester -RequiredVersion $pinned -Force -SkipPublisherCheck `
                   -Scope CurrentUser -AllowClobber -ErrorAction Stop
}

Remove-Module Pester -Force -ErrorAction SilentlyContinue
Import-Module Pester -RequiredVersion $pinned -Force -ErrorAction Stop
Write-Host "pester: imported $((Get-Module Pester).Version)"

$pc = New-PesterConfiguration
$pc.Run.Path          = $testPath.ToArray()
$pc.Run.PassThru      = $true
$pc.Output.Verbosity  = 'Detailed'
$pc.TestResult.Enabled = $false

$result = Invoke-Pester -Configuration $pc

Write-Host ''
Write-Host ("pester: total={0} passed={1} failed={2} skipped={3} duration={4}" -f
    $result.TotalCount, $result.PassedCount, $result.FailedCount, $result.SkippedCount, $result.Duration)

if ($result.TotalCount -eq 0) {
    Write-Host 'pester: FAIL -- the suite ran zero tests; an empty suite is not a green'
    exit 1
}
if ($result.FailedCount -gt 0) {
    Write-Host "pester: FAIL -- $($result.FailedCount) test(s) failed"
    exit 1
}
Write-Host 'pester: PASS'
exit 0
