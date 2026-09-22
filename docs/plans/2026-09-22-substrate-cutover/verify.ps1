#Requires -Version 7.4
<#
.SYNOPSIS
    Re-derives every claim this release makes, from the repository, without trusting REPORT.md.

.DESCRIPTION
    Eight checks, printed as 19 PASS/FAIL lines: four of them have more than one subject -- seven
    check scripts, two forbidden suites, three manifests, three blobs. The script exits 1 if any
    line failed.

      1  HASHES.txt and COMBINED recompute from the files on disk
      2  every check script in scripts/ci/ still passes against HEAD, plus the forensic chain
      3  BASELINE.md has exactly one commit and it is Phase 1's
      4  modules/ holds the three named modules and nothing else, and the two suites that are
         NOT substrate's are nowhere under it
      5  no tracked .py file sits outside config/repo.json -> runtimes.python.allowed_under
      6  the per-module table in README.md equals a live Pester run
      7  the three manifests import under their bare names and export what they claim
      8  the three provenance blobs are the bytes that were copied, recomputed without git

    The manifest and the COMBINED join are byte-for-byte the same construction as
    docs/plans/2026-09-21-repo-policy/verify.ps1: every file in this folder except HASHES.txt and
    TRANSCRIPT.log, ordinal-sorted by name, one "<sha256>  <name>" line each, and COMBINED is the
    sha256 of the concatenated hashes with nothing between them. Two run orders that hash their
    evidence two different ways have not hashed it.

    TRANSCRIPT.log is excluded for two reasons and both matter. It grows while the run that hashes
    it is still going, and Start-Transcript writes CRLF into a repository whose .gitattributes
    says LF -- so its bytes on disk and its bytes in the object store are different, and neither
    is tampering (FINDINGS F50).

    On check 2: the scripts are not run blind with no arguments. Test-BranchFlow needs a head/base
    pair, and Test-Trailers is given a head and no base, so the range is this repository's whole
    history. Substrate passed it a seed sha to skip past a trailerless root commit; core has no
    such commit and no such object, so there is nothing to skip. FINDINGS F78.
    Test-Trailers runs over full history WITHOUT -IncludeMerges: forensic record seq 4 measured
    why -- actions/checkout gives CI a synthetic merge commit that carries no trailer and can
    never be given one, and a check that goes green off that commit is green for the wrong reason.

    On check 6: this is the check that stops README.md from rotting. The release states four
    per-module numbers; this parses them back out of the markdown and compares them to
    scripts/Measure-Modules.ps1 run live, writing its JSON to a scratch path OUTSIDE the
    repository so that verifying does not dirty the tree being verified.

.EXAMPLE
    pwsh -NoProfile -File docs/plans/2026-09-22-substrate-cutover/verify.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 3.0

$PlanDir  = $PSScriptRoot
$RepoRoot = Split-Path (Split-Path (Split-Path $PlanDir -Parent) -Parent) -Parent
$Excluded = @('HASHES.txt', 'TRANSCRIPT.log')
$Modules  = @('ledger', 'policy', 'plans')

$results = [System.Collections.Generic.List[object]]::new()
function Add-Result {
    param([string]$Name, [bool]$Ok, [string]$Detail = '')
    $results.Add([pscustomobject]@{ Name = $Name; Ok = $Ok; Detail = $Detail })
    Write-Host ("{0}  {1}  {2}" -f $(if ($Ok) { 'PASS' } else { 'FAIL' }), $Name.PadRight(76), $Detail)
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
    <#  git's own object id for a file, computed from the bytes on disk: sha1("blob <len>\0" + content).
        No git process, so this answers "are these the copied bytes" even in a tree with no .git. #>
    param([string]$Path)
    $bytes  = [System.IO.File]::ReadAllBytes($Path)
    $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
    $all    = [byte[]]::new($header.Length + $bytes.Length)
    [Array]::Copy($header, 0, $all, 0, $header.Length)
    [Array]::Copy($bytes, 0, $all, $header.Length, $bytes.Length)
    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA1]::HashData($all)).ToLowerInvariant()
}

function Get-PlanManifest {
    $files = Get-ChildItem -LiteralPath $PlanDir -File -Force |
             Where-Object { $Excluded -notcontains $_.Name } |
             Sort-Object -Property Name -CaseSensitive
    $lines = foreach ($f in $files) { '{0}  {1}' -f (Get-Sha256OfFile $f.FullName), $f.Name }
    $combined = Get-Sha256OfText (($lines | ForEach-Object { ($_ -split '  ')[0] }) -join '')
    return [pscustomobject]@{ Lines = @($lines); Combined = $combined }
}

Write-Host "verify: repo root $RepoRoot"
Write-Host "verify: plan dir  $PlanDir"
Write-Host ''

# ------------------------------------------------------------------ 1 hashes

$manifest = Get-PlanManifest
$hashFile = Join-Path $PlanDir 'HASHES.txt'
if (-not (Test-Path -LiteralPath $hashFile)) {
    Add-Result 'HASHES.txt recomputes' $false 'HASHES.txt is missing'
}
else {
    $onDisk   = @([System.IO.File]::ReadAllLines($hashFile) | Where-Object { $_.Trim() -ne '' })
    $expected = @($manifest.Lines) + @("COMBINED $($manifest.Combined)")
    $same     = ($onDisk.Count -eq $expected.Count)
    if ($same) {
        for ($i = 0; $i -lt $expected.Count; $i++) {
            if ($onDisk[$i] -cne $expected[$i]) { $same = $false; break }
        }
    }
    Add-Result 'HASHES.txt recomputes' $same "COMBINED $($manifest.Combined)"
    if (-not $same) {
        Write-Host '      on disk:'; $onDisk   | ForEach-Object { Write-Host "        $_" }
        Write-Host '      computed:'; $expected | ForEach-Object { Write-Host "        $_" }
    }
}

# ------------------------------------------------------------------ 2 check scripts

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
    $path  = Join-Path $RepoRoot $inv.Script
    $shown = if ($inv.Args.Count) { " $($inv.Args -join ' ')" } else { '' }
    $PSNativeCommandUseErrorActionPreference = $false
    $null = & pwsh -NoProfile -File $path @($inv.Args) 2>&1
    Add-Result "$($inv.Script)$shown" ($LASTEXITCODE -eq 0) "exit $LASTEXITCODE"
}

# ------------------------------------------------------------------ 3 the baseline never moved

$baselineRel = 'docs/plans/2026-09-22-substrate-cutover/BASELINE.md'
$baselineLog = @(& git -C $RepoRoot log --format='%h %s' -- $baselineRel)
Add-Result 'BASELINE.md has exactly one commit' ($baselineLog.Count -eq 1) `
    "$($baselineLog.Count) commit(s): $($baselineLog -join ' | ')"

# ------------------------------------------------------------------ 4 the modules, and the two that are not here

$modulesRoot = Join-Path $RepoRoot 'modules'
$present = @(Get-ChildItem -LiteralPath $modulesRoot -Directory | ForEach-Object { $_.Name } | Sort-Object)
$namesOk = (@(Compare-Object $present ($Modules | Sort-Object)).Count -eq 0)
Add-Result 'modules/ holds exactly ledger, policy, plans' $namesOk ($present -join ', ')

$notOurs = @('fuzzer_import.ps1', 'hook_pre_tool.ps1')
$strays  = @(Get-ChildItem -LiteralPath $modulesRoot -Recurse -File -Force |
             Where-Object { $notOurs -contains $_.Name } |
             ForEach-Object { [System.IO.Path]::GetRelativePath($RepoRoot, $_.FullName).Replace('\', '/') })
Add-Result 'fuzzer_import.ps1 and hook_pre_tool.ps1 are nowhere under modules/' ($strays.Count -eq 0) `
    $(if ($strays.Count) { $strays -join ', ' } else { 'neither present; FINDINGS F37 names their destination repos' })

# ------------------------------------------------------------------ 5 python only where the config says

$config  = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)
$allowed = @($config.runtimes.python.allowed_under)
Push-Location $RepoRoot
try { $pyFiles = @(git ls-files -- '*.py') }
finally { Pop-Location }
$outside = @($pyFiles | Where-Object { $rel = $_; -not (@($allowed | Where-Object { $rel.StartsWith($_) }).Count) })
Add-Result 'every tracked .py is under runtimes.python.allowed_under' ($outside.Count -eq 0) `
    "$($pyFiles.Count) tracked .py, allowed under $($allowed -join ', ')$(if ($outside.Count) { "; outside: $($outside -join ', ')" })"

# ------------------------------------------------------------------ 6 the README's numbers are the measured numbers

$scratch = Join-Path ([System.IO.Path]::GetTempPath()) ("substrate-modules-{0}.json" -f $PID)
$PSNativeCommandUseErrorActionPreference = $false
$null = & pwsh -NoProfile -File (Join-Path $RepoRoot 'scripts/Measure-Modules.ps1') -Json $scratch 2>&1
$measureExit = $LASTEXITCODE

if ($measureExit -ne 0 -or -not (Test-Path -LiteralPath $scratch)) {
    Add-Result "README per-module counts match a live run" $false "Measure-Modules.ps1 exited $measureExit"
}
else {
    try {
        $measured = Get-Content -LiteralPath $scratch -Raw | ConvertFrom-Json -Depth 8
        $byName = @{}
        foreach ($m in $measured.byModule) { $byName[$m.Name] = [int]$m.Total }

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

        # Five rows, or the README stopped stating what this check exists to check.
        $wanted = @('ledger', 'policy', 'plans', 'repo', 'total')
        $missing = @($wanted | Where-Object { -not $stated.Contains($_) })
        $mismatch = [System.Collections.Generic.List[string]]::new()
        if ($missing.Count -eq 0) {
            foreach ($name in $Modules + @('repo')) {
                if ($byName[$name] -ne $stated[$name]) {
                    $mismatch.Add("{0}: README {1}, measured {2}" -f $name, $stated[$name], $byName[$name])
                }
            }
            if ($stated['total'] -ne [int]$measured.total) {
                $mismatch.Add("total: README $($stated['total']), measured $($measured.total)")
            }
        }
        $ok = ($missing.Count -eq 0) -and ($mismatch.Count -eq 0)
        $detail = if ($missing.Count) { "README states no row for: $($missing -join ', ')" }
                  elseif ($mismatch.Count) { $mismatch -join '; ' }
                  else { ($wanted | ForEach-Object { "$_=$($stated[$_])" }) -join ' ' }
        Add-Result 'README per-module counts match a live run' $ok $detail
    }
    finally { Remove-Item -LiteralPath $scratch -Force -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------------------ 7 the manifests are what they say

$expectedExports = @{
    ledger = @('Get-LedgerEntry', 'Get-LedgerStatus', 'Get-LedgerVerify', 'Invoke-LedgerForce')
    policy = @('Get-PolicyRules')
    plans  = @('Test-PlanStructure')
}

foreach ($name in $Modules) {
    $manifestPath = Join-Path $modulesRoot "$name/$name.psd1"
    $ok = $false
    $detail = ''
    try {
        if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
            $detail = "no manifest at modules/$name/$name.psd1"
        }
        else {
            Remove-Module -Name $name -Force -ErrorAction SilentlyContinue
            Import-Module -Name $manifestPath -Force -ErrorAction Stop
            $mod = Get-Module -Name $name
            if (-not $mod) { $detail = "imported but Get-Module -Name '$name' found nothing" }
            else {
                $exports = @($mod.ExportedFunctions.Keys | Sort-Object)
                $diff = @(Compare-Object $exports $expectedExports[$name])
                $ok = ($diff.Count -eq 0) -and ($mod.Version.ToString() -eq '0.2.0')
                $detail = "v$($mod.Version) exports $($exports -join ',')"
            }
            Remove-Module -Name $name -Force -ErrorAction SilentlyContinue
        }
    }
    catch { $detail = $_.Exception.Message }
    Add-Result "modules/$name/$name.psd1 imports as '$name'" $ok $detail
}

# ------------------------------------------------------------------ 8 the copied bytes are still the copied bytes

$provenance = @(
    @{ Path = 'modules/ledger/ledger.psm1';       Blob = '37d63403e7f0e21c5a8aa34ac6f80bbacb792d5a'; From = 'claude.build.ledger@d57938d src/ledger/Ledger.psm1' }
    @{ Path = 'modules/policy/policy.psm1';       Blob = '72dc1ec6010897d56cb2ca3aa10351393b72d5ef'; From = 'claude.build.policy@3be10c4 src/claude.build.policy/claude.build.policy.psm1' }
    @{ Path = 'modules/plans/PlanValidator.ps1';  Blob = '8e5da7682f212499e4fb33c2cdaafe1fb1aa2a09'; From = 'claude.pwsh.image.builder@a6b61dd src/PlanValidator.ps1' }
)

foreach ($p in $provenance) {
    $full = Join-Path $RepoRoot $p.Path
    if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
        Add-Result "$($p.Path) is the copied blob" $false 'file is missing'
        continue
    }
    $actual = Get-GitBlobId $full
    Add-Result "$($p.Path) is the copied blob" ($actual -ceq $p.Blob) "$actual  <- $($p.From)"
}

# ------------------------------------------------------------------ informational, not a check

$tag = (& git -C $RepoRoot tag -l 'v0.1.0' | Out-String).Trim()
if ($tag) {
    $tagged = (& git -C $RepoRoot rev-list -n1 v0.1.0 | Out-String).Trim()
    $onMain = @(& git -C $RepoRoot branch -a --contains $tagged) -match 'main'
    Write-Host ''
    Write-Host "INFO  v0.1.0 -> $tagged  (on a branch named main: $([bool]$onMain))"
}
else {
    Write-Host ''
    Write-Host 'INFO  v0.1.0 does not exist yet in this clone; the tag is pushed after the main merge'
}

# ------------------------------------------------------------------ verdict

Write-Host ''
$failed = @($results | Where-Object { -not $_.Ok })
Write-Host ("verify: {0} check(s), {1} passed, {2} failed" -f $results.Count, ($results.Count - $failed.Count), $failed.Count)
if ($failed.Count -gt 0) {
    foreach ($f in $failed) { Write-Host "  FAILED: $($f.Name)  $($f.Detail)" }
    exit 1
}
Write-Host "verify: COMBINED $($manifest.Combined)"
exit 0
