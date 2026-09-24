#Requires -Version 7.4
<#
.SYNOPSIS
    Re-derives what this repository claims at HEAD, from the repository. The live verifier.

.DESCRIPTION
    docs/plans/2026-09-22-substrate-cutover/verify.ps1 is the archived verifier of the release
    that produced this repository. It is listed in that folder's HASHES.txt, so it cannot be
    edited without falsifying the archive, and it goes on reporting the four pins the tree has
    since moved past on purpose. This script is its successor for HEAD. The archive is kept as it
    was, and check 1 here proves it still is. DECISIONS D008.

    The same eight checks, with two changes. Each one is written down:

      7  the manifests export what they export TODAY: ledger adds Add-LedgerRecord (D002),
         plans adds Get-PlanSchemaPath (the Phase 7 rewrite, cutover F70). Both are D008.
      8  a byte pin that a decision retired is reported as SKIP with a SkipWhen:<kebab-reason>
         naming that decision, and the decision must exist in docs/DECISIONS.md. A retirement
         with no written decision is a FAIL, not a skip. ledger.psm1 is D002, and
         PlanValidator.ps1 is D008.

    Exits 0 only when no line failed. A SKIP is not a failure, and it is never silent.

.PARAMETER Json
    Optional path. Writes every line and the per-module measurement this run made, so that
    scripts/Update-Status.ps1 can regenerate the status lines from a run instead of by hand.

.EXAMPLE
    pwsh -NoProfile -File scripts/verify.ps1
#>
[CmdletBinding()]
param(
    [string]$Json
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot  = Split-Path $PSScriptRoot -Parent
$PlanDir   = Join-Path $RepoRoot 'docs/plans/2026-09-22-substrate-cutover'
$Excluded  = @('HASHES.txt', 'TRANSCRIPT.log')
$Modules   = @('ledger', 'policy', 'plans')
$Decisions = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'docs/DECISIONS.md'))

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param([string]$Name, [ValidateSet('PASS', 'FAIL', 'SKIP')][string]$Verdict, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Name = $Name; Verdict = $Verdict; Detail = $Detail })
    Write-Host ("{0}  {1}  {2}" -f $Verdict, $Name.PadRight(76), $Detail)
}
function Add-Check {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    Add-Result $Name $(if ($Ok) { 'PASS' } else { 'FAIL' }) $Detail
}

function Get-Sha256OfFile {
    param([string]$Path)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData([System.IO.File]::ReadAllBytes($Path))
    ).ToLowerInvariant()
}

function Get-Sha256OfText {
    param([string]$Text)
    return [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))
    ).ToLowerInvariant()
}

function Get-GitBlobId {
    # git's object id for a file, from the bytes on disk: sha1("blob <len>\0" + content). No git.
    param([string]$Path)
    $bytes  = [System.IO.File]::ReadAllBytes($Path)
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $all    = [byte[]]::new($header.Length + $bytes.Length)
    [Array]::Copy($header, 0, $all, 0, $header.Length)
    [Array]::Copy($bytes, 0, $all, $header.Length, $bytes.Length)
    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData($all)).ToLowerInvariant()
}

Write-Host "verify: repo root $RepoRoot"
Write-Host ''

# ------------------------------------------------------------------ 1 the archive is still the archive

$files = Get-ChildItem -LiteralPath $PlanDir -File -Force |
         Where-Object { $Excluded -notcontains $_.Name } |
         Sort-Object -Property Name -CaseSensitive
$lines    = @(foreach ($f in $files) { '{0}  {1}' -f (Get-Sha256OfFile $f.FullName), $f.Name })
$combined = Get-Sha256OfText (($lines | ForEach-Object { ($_ -split '  ')[0] }) -join '')
$onDisk   = @([System.IO.File]::ReadAllLines((Join-Path $PlanDir 'HASHES.txt')) | Where-Object { $_.Trim() -ne '' })
$expected = @($lines) + @("COMBINED $combined")
$same     = ($onDisk.Count -eq $expected.Count) -and
            (@(for ($i = 0; $i -lt $expected.Count; $i++) { if ($onDisk[$i] -cne $expected[$i]) { $i } }).Count -eq 0)
Add-Check 'cutover archive: HASHES.txt recomputes' $same "COMBINED $combined"

# ------------------------------------------------------------------ 2 check scripts

$PSNativeCommandUseErrorActionPreference = $false
$branch   = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD | Out-String).Trim()
$flowBase = if ($branch -eq 'develop') { 'main' } else { 'develop' }

$invocations = @(
    @{ Script = 'scripts/ci/Test-RequiresHeader.ps1';         Args = @() }
    @{ Script = 'scripts/ci/Test-Runtimes.ps1';               Args = @() }
    @{ Script = 'scripts/ci/Test-Trailers.ps1';               Args = @('-Head', 'HEAD') }
    @{ Script = 'scripts/ci/Test-BranchFlow.ps1';             Args = @('-Head', $branch, '-Base', $flowBase) }
    @{ Script = 'scripts/ci/Test-GeneratedMatchesConfig.ps1'; Args = @() }
    @{ Script = 'scripts/ci/Invoke-Tests.ps1';                Args = @() }
    @{ Script = 'scripts/forensic.ps1';                       Args = @('-Verify') }
)
foreach ($inv in $invocations) {
    $shown = if ($inv.Args.Count) { " $($inv.Args -join ' ')" } else { '' }
    $null = & pwsh -NoProfile -File (Join-Path $RepoRoot $inv.Script) @($inv.Args) 2>&1
    Add-Check "$($inv.Script)$shown" ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
}

# ------------------------------------------------------------------ 3 the baseline never moved

$baselineLog = @(& git -C $RepoRoot log --format='%h %s' -- 'docs/plans/2026-09-22-substrate-cutover/BASELINE.md')
Add-Check 'BASELINE.md has exactly one commit' ($baselineLog.Count -eq 1) "$($baselineLog.Count) commit(s)"

# ------------------------------------------------------------------ 4 the modules, and the two that are not here

$modulesRoot = Join-Path $RepoRoot 'modules'
$present = @(Get-ChildItem -LiteralPath $modulesRoot -Directory | ForEach-Object { $_.Name } | Sort-Object)
Add-Check 'modules/ holds exactly ledger, policy, plans' (@(Compare-Object $present ($Modules | Sort-Object)).Count -eq 0) ($present -join ', ')

$strays = @(Get-ChildItem -LiteralPath $modulesRoot -Recurse -File -Force |
            Where-Object { @('fuzzer_import.ps1', 'hook_pre_tool.ps1') -contains $_.Name })
Add-Check 'fuzzer_import.ps1 and hook_pre_tool.ps1 are nowhere under modules/' ($strays.Count -eq 0) "$($strays.Count) present"

# ------------------------------------------------------------------ 5 python only where the config says

$config  = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)
$allowed = @($config.runtimes.python.allowed_under)
$pyFiles = @(& git -C $RepoRoot ls-files -- '*.py')
$outside = @($pyFiles | Where-Object { $rel = $_; -not (@($allowed | Where-Object { $rel.StartsWith($_) }).Count) })
Add-Check 'every tracked .py is under runtimes.python.allowed_under' ($outside.Count -eq 0) "$($pyFiles.Count) tracked .py, $($outside.Count) outside"

# ------------------------------------------------------------------ 6 the README's numbers are the measured numbers

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("core-modules-{0}.json" -f $PID)
$null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'scripts/Measure-Modules.ps1') -Json $scratch 2>&1
$measureExit = $LASTEXITCODE
$measured = $null
if (Test-Path -LiteralPath $scratch) {
    $measured = Get-Content -LiteralPath $scratch -Raw | ConvertFrom-Json -Depth 8
    Remove-Item -LiteralPath $scratch -Force
}
Add-Check 'scripts/Measure-Modules.ps1' ($measureExit -eq 0) $(
    if ($measured) { "exit $measureExit, total=$($measured.total) failed=$($measured.failed) exceptions=$($measured.exceptions)" } else { "exit $measureExit, no JSON" })

if ($measured) {
    $byName = @{}
    foreach ($m in $measured.byModule) { $byName[$m.Name] = [int]$m.Total }
    $byName['total'] = [int]$measured.total
    $readme = [System.IO.File]::ReadAllText((Join-Path $RepoRoot 'README.md'))
    $stated = [ordered]@{}
    foreach ($name in $Modules) {
        $m = [regex]::Match($readme, ('(?m)^\|\s*`{0}`\s*\|.*?\*\*(\d+)\*\*\s*\|' -f [regex]::Escape($name)))
        if ($m.Success) { $stated[$name] = [int]$m.Groups[1].Value }
    }
    $m = [regex]::Match($readme, '(?m)^\|.*`tests/`.*?\*\*(\d+)\*\*\s*\|')
    if ($m.Success) { $stated['repo'] = [int]$m.Groups[1].Value }
    $m = [regex]::Match($readme, '(?m)^\|.*\*\*total\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|')
    if ($m.Success) { $stated['total'] = [int]$m.Groups[1].Value }

    $wanted   = @('ledger', 'policy', 'plans', 'repo', 'total')
    $missing  = @($wanted | Where-Object { -not $stated.Contains($_) })
    $mismatch = @($wanted | Where-Object { $stated.Contains($_) -and $stated[$_] -ne $byName[$_] } |
                  ForEach-Object { "${_}: README $($stated[$_]), measured $($byName[$_])" })
    $detail = if ($missing.Count) { "README states no row for: $($missing -join ', ')" }
              elseif ($mismatch.Count) { $mismatch -join '; ' }
              else { ($wanted | ForEach-Object { "$_=$($stated[$_])" }) -join ' ' }
    Add-Check 'README per-module counts match a live run' (($missing.Count + $mismatch.Count) -eq 0) $detail
}
else {
    Add-Check 'README per-module counts match a live run' $false 'no measurement to compare'
}

# ------------------------------------------------------------------ 7 the manifests are what they say

# Today's exports. The archive pinned four for ledger and one for plans; D008 says why these moved.
$expectedExports = @{
    ledger = @('Add-LedgerRecord', 'Get-LedgerEntry', 'Get-LedgerStatus', 'Get-LedgerVerify', 'Invoke-LedgerForce')
    policy = @('Get-PolicyRules')
    plans  = @('Get-PlanSchemaPath', 'Test-PlanStructure')
}
foreach ($name in $Modules) {
    $ok = $false
    $detail = ''
    try {
        Remove-Module -Name $name -Force -ErrorAction SilentlyContinue
        Import-Module -Name (Join-Path $modulesRoot "$name/$name.psd1") -Force -ErrorAction Stop
        $mod = Get-Module -Name $name
        $exports = @($mod.ExportedFunctions.Keys | Sort-Object)
        $ok = (@(Compare-Object $exports $expectedExports[$name]).Count -eq 0) -and ($mod.Version.ToString() -eq '0.2.0')
        $detail = "v$($mod.Version) exports $($exports -join ',')"
        Remove-Module -Name $name -Force -ErrorAction SilentlyContinue
    }
    catch { $detail = $_.Exception.Message }
    Add-Check "modules/$name/$name.psd1 imports as '$name'" $ok $detail
}

# ------------------------------------------------------------------ 8 the copied bytes that are still claimed to be copied

$provenance = @(
    @{ Path = 'modules/ledger/ledger.psm1';      Blob = '37d63403e7f0e21c5a8aa34ac6f80bbacb792d5a'; RetiredBy = 'D002' }
    @{ Path = 'modules/policy/policy.psm1';      Blob = '72dc1ec6010897d56cb2ca3aa10351393b72d5ef'; RetiredBy = '' }
    @{ Path = 'modules/plans/PlanValidator.ps1'; Blob = '8e5da7682f212499e4fb33c2cdaafe1fb1aa2a09'; RetiredBy = 'D008' }
)
foreach ($p in $provenance) {
    $name   = "$($p.Path) is the copied blob"
    $actual = Get-GitBlobId (Join-Path $RepoRoot $p.Path)
    if ($p.RetiredBy) {
        if ($Decisions -cmatch ('(?m)^## {0} ' -f [regex]::Escape($p.RetiredBy))) {
            Add-Result $name 'SKIP' "SkipWhen:retired-by-$($p.RetiredBy.ToLowerInvariant())  now $actual"
        }
        else {
            Add-Check $name $false "retired by $($p.RetiredBy), which docs/DECISIONS.md does not contain"
        }
        continue
    }
    Add-Check $name ($actual -ceq $p.Blob) $actual
}

# ------------------------------------------------------------------ verdict

$failed  = @($results | Where-Object Verdict -eq 'FAIL')
$skipped = @($results | Where-Object Verdict -eq 'SKIP')
$passed  = $results.Count - $failed.Count - $skipped.Count
Write-Host ''
Write-Host ("verify: {0} check(s), {1} passed, {2} failed, {3} skipped" -f $results.Count, $passed, $failed.Count, $skipped.Count)
foreach ($f in $failed) { Write-Host "  FAILED: $($f.Name)  $($f.Detail)" }

if ($Json) {
    $payload = [ordered]@{
        head     = (& git -C $RepoRoot rev-parse HEAD | Out-String).Trim()
        checks   = $results.Count
        passed   = $passed
        failed   = $failed.Count
        skipped  = $skipped.Count
        lines    = @($results)
        measured = $measured
    }
    [System.IO.File]::WriteAllText([System.IO.Path]::GetFullPath($Json, (Get-Location).Path),
        (ConvertTo-Json $payload -Depth 10), [System.Text.UTF8Encoding]::new($false))
}

if ($failed.Count) { exit 1 }
exit 0
