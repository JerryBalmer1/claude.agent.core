#Requires -Version 7.4
<#
.SYNOPSIS
    CI check "trailer-guard": every commit in <Base>..HEAD carries an allowed `who:` trailer.

.DESCRIPTION
    The trailer key and its allowed values come from config/repo.json -> trailer.

    WHY MERGE COMMITS ARE EXCLUDED BY DEFAULT, stated plainly rather than hidden:

    A merge commit in this repo is created by GitHub at merge time, by the automerge workflow,
    not by an agent making a change. If one ever landed without a trailer, it could not be
    repaired afterwards - amending or rewriting a pushed commit is forbidden here - and the
    check would be permanently red on every later PR whose range contained it. A gate that can
    be wedged into permanent failure by its own tooling is not a gate, it is a trap.

    So the PR gate runs with --no-merges. That is NOT the same as not checking them:
    `.github/workflows/automerge.yml` writes `who: claude` into the merge commit body, and
    docs/plans/2026-09-21-repo-policy/verify.ps1 runs this script with -IncludeMerges against
    origin/main to confirm it actually did. The check exists; it just is not the thing that can
    deadlock the flow.

    THE GRANDFATHER FILE (added 2026-09-21).

    config/trailer-grandfather.txt names, by exact full 40-character hash, the commits that
    predate the guard and carry no trailer. They cannot be given one: repairing them means
    rewriting pushed history, which this repo forbids for a better reason than tidiness - the
    forensic chain cites hashes.

    The exemption is BY EXACT HASH and nothing else. Not by date, not by author, not by a
    pattern, not by "everything before commit X". Those all quietly widen over time; a list of
    forty-character strings has a length you can assert, and tests/Trailers.Tests.ps1 asserts it.

    An absent grandfather file is treated as an EMPTY list, loudly, never as permission. The
    quietest possible failure mode for an exemption list is for its deletion to make everything
    pass, and that is exactly what does not happen here: delete the file and a full-history run
    goes red on the seed commit.

    -Base is OPTIONAL. Without it the range is every commit reachable from -Head, root included,
    which is the run the grandfather file exists to make possible. With it the range is
    <Base>..<Head>, which is what CI passes and which never contains the root commit at all.

.EXAMPLE
    pwsh -NoProfile -File scripts/ci/Test-Trailers.ps1 -Base origin/develop

.EXAMPLE
    pwsh -NoProfile -File scripts/ci/Test-Trailers.ps1 -Head HEAD -IncludeMerges
#>
[CmdletBinding()]
param(
    [string]$Base = '',
    [string]$Head = 'HEAD',
    [switch]$IncludeMerges,
    [string]$GrandfatherPath = ''
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config   = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)
$key      = $config.trailer.key
$allowed  = @($config.trailer.allowed)

if ([string]::IsNullOrWhiteSpace($GrandfatherPath)) {
    $GrandfatherPath = Join-Path $RepoRoot 'config/trailer-grandfather.txt'
}

# A `#` comment and blank lines are tolerated so the file can say what the hashes are without
# the parser caring. Everything before the first `#` on a line is the datum.
$grandfathered = @()
if (Test-Path -LiteralPath $GrandfatherPath) {
    $grandfathered = @(Get-Content -LiteralPath $GrandfatherPath |
                       ForEach-Object { ($_ -split '#')[0].Trim() } |
                       Where-Object { $_ -ne '' })
}
else {
    Write-Host "trailer-guard: WARNING -- no grandfather file at $GrandfatherPath; the exemption list is EMPTY, not permissive"
}

Push-Location $RepoRoot
try {
    $range = if ([string]::IsNullOrWhiteSpace($Base)) { $Head } else { "$Base..$Head" }
    Write-Host "trailer-guard: range $range, key '$key', allowed [$($allowed -join ', ')]"
    Write-Host ("trailer-guard: merge commits are {0}" -f $(if ($IncludeMerges) { 'INCLUDED (-IncludeMerges)' } else { 'excluded (see .DESCRIPTION)' }))
    Write-Host ("trailer-guard: grandfathered {0} commit(s) from {1}" -f
        $grandfathered.Count, [System.IO.Path]::GetRelativePath($RepoRoot, $GrandfatherPath).Replace('\', '/'))

    # Not $args: that is an automatic variable, and splatting it is a trap waiting to be sprung.
    $logArgs = @('log', '--format=%H', $range)
    if (-not $IncludeMerges) { $logArgs += '--no-merges' }
    $shas = @(& git @logArgs)

    if ($shas.Count -eq 0) {
        Write-Host 'trailer-guard: PASS -- no commits in range'
        exit 0
    }

    $bad   = [System.Collections.Generic.List[string]]::new()
    $usedG = [System.Collections.Generic.List[string]]::new()
    foreach ($sha in $shas) {
        $value   = (& git log -1 --format="%(trailers:key=$key,valueonly)" $sha | Out-String).Trim()
        $subject = (& git log -1 --format='%s' $sha | Out-String).Trim()
        $short   = $sha.Substring(0, 8)

        if ([string]::IsNullOrWhiteSpace($value)) {
            # Exact, full-hash membership. $sha is always 40 chars from --format=%H, so a
            # shortened entry simply never matches rather than matching a prefix by accident.
            if ($grandfathered -ccontains $sha) {
                Write-Host "  GRAND $short  no '${key}:' trailer, exempted by exact hash  -- $subject"
                $usedG.Add($sha); continue
            }
            Write-Host "  MISS  $short  no '${key}:' trailer  -- $subject"
            $bad.Add($sha); continue
        }
        if ($allowed -notcontains $value) {
            Write-Host "  BAD   $short  ${key}: '$value' is not in the allowed vocabulary  -- $subject"
            $bad.Add($sha); continue
        }

        # Advisory, not a gate: the trailer is supposed to be the LAST line. Reported so drift
        # is visible, but not failed on - the gate is presence and vocabulary, per the spec.
        $body     = (& git log -1 --format='%B' $sha | Out-String)
        $lastLine = (($body -split "`r?`n") | Where-Object { $_.Trim() -ne '' } | Select-Object -Last 1)
        $note     = if ($lastLine -match "^\s*$key\s*:") { '' } else { "  [note: '${key}:' is not the last line]" }
        Write-Host "  OK    $short  ${key}: $value$note  -- $subject"
    }

    Write-Host "trailer-guard: $($shas.Count) commit(s) checked, $($usedG.Count) grandfathered, $($bad.Count) non-compliant"

    # An exemption listed but not needed in this range is not an error - a PR range legitimately
    # does not contain the seed. It is reported so that a list which has stopped meaning anything
    # is visible rather than inherited forever.
    $unused = @($grandfathered | Where-Object { $usedG -cnotcontains $_ })
    foreach ($u in $unused) {
        $show = if ($u.Length -ge 8) { $u.Substring(0, 8) } else { $u }
        Write-Host "  note: grandfather entry $show was not needed in this range"
    }

    if ($bad.Count -gt 0) {
        Write-Host 'trailer-guard: FAIL'
        exit 1
    }
    Write-Host 'trailer-guard: PASS'
    exit 0
}
finally { Pop-Location }
