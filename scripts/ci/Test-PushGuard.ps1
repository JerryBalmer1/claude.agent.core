#Requires -Version 7.4
<#
.SYNOPSIS
    The push tripwire: a commit landing on a long-lived branch arrived through the flow.

.DESCRIPTION
    THIS CANNOT BLOCK A PUSH, AND IT IS NOT PRETENDING TO.

    Branch protection is not available on a private repository on the free tier - measured, not
    assumed; docs/plans/2026-09-21-repo-policy/PROTECTION.md records three HTTP 403s against
    branches/main, branches/develop and rulesets. By the time this script runs, the push has
    already happened. What it produces is a red run, permanently attached to the commit that did
    it, dated, with the reason written out.

    That is worth having because the failure it catches is not a typo, it is a report. An agent
    pushing straight to main and then saying the work went through the flow is the exact event
    the legacy repo recorded nine times in one day, none of them through develop, and
    nobody noticed until someone counted. A smoke alarm does not stop a fire either.

    TWO GATES, BOTH REPORTED, NEVER SHORT-CIRCUITED:

    1. The commit is a MERGE - two or more parents. Everything that goes through the flow lands
       as a merge commit, because config/repo.json -> merge.strategy is "merge" and squash and
       rebase are disabled at the repository level. A one-parent commit on main or develop did
       not come from a pull request. An octopus merge has more than two parents and still passes:
       it is a merge, and a merge is not a direct push.

    2. The work carries a `who:` trailer from the allowed vocabulary. On a MERGE, the commits
       judged are the non-merge commits it brings in - `git rev-list --no-merges <merge> --not
       <first parent>` - and every one of them must carry the trailer. The merge commit's own
       message is EXEMPT (D012): with review.mode `human` the merge is Jerry's click on GitHub's
       merge button, and GitHub writes that message without a trailer. Judging it made this guard
       red on every legitimate merge (F93). A merge that brings in no non-merge commit fails:
       there is nothing on it to judge. On a one-parent commit, the commit itself is judged.

    The grandfather file is DELIBERATELY NOT CONSULTED. config/trailer-grandfather.txt exempts
    commits inherited from before the guard existed, which is a statement about history. This
    script judges an event happening now. Sharing the list would let an old hash excuse a new
    push, and the exemption would quietly become a skeleton key.

.EXAMPLE
    pwsh -NoProfile -File scripts/ci/Test-PushGuard.ps1 -Sha $env:GITHUB_SHA
#>
[CmdletBinding()]
param(
    [string]$Sha = 'HEAD',
    # The repository whose commit is judged. The rules are always read from this script's own
    # config/repo.json; the parameter exists so tests/PushGuard.Tests.ps1 can judge synthetic
    # repositories (BACKLOG B11) instead of pinning live shas (F78).
    [string]$Repository
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config   = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)
$key      = $config.trailer.key
$allowed  = @($config.trailer.allowed)
if (-not $Repository) { $Repository = $RepoRoot }

Push-Location $Repository
try {
    $full    = (& git rev-parse $Sha | Out-String).Trim()
    $subject = (& git log -1 --format='%s' $full | Out-String).Trim()
    $parents = @((& git log -1 --format='%P' $full | Out-String).Trim() -split '\s+' | Where-Object { $_ -ne '' })
    $who     = (& git log -1 --format="%(trailers:key=$key,valueonly)" $full | Out-String).Trim()

    Write-Host "push-guard: commit $($full.Substring(0, 8))  $subject"
    Write-Host "push-guard: parents $($parents.Count) [$($parents | ForEach-Object { $_.Substring(0, 8) })]"
    Write-Host "push-guard: ${key}: '$who'  (allowed: $($allowed -join ', '))$(if ($parents.Count -ge 2) { ' - exempt on a merge (D012)' })"
    Write-Host ''

    # Both gates are evaluated before either is reported. A guard that stops at the first
    # failure tells you half the story, and the half it withholds is the half you find out
    # about on the next red run.
    $failures = [System.Collections.Generic.List[string]]::new()

    if ($parents.Count -lt 2) {
        $failures.Add("only $($parents.Count) parent(s) - a commit that went through a pull request is a merge commit with two")
    }
    else {
        Write-Host "  OK    merge commit, $($parents.Count) parents"
    }

    if ($parents.Count -ge 2) {
        $brought = @(& git rev-list --no-merges $full --not $parents[0])
        $bad = @(foreach ($c in $brought) {
            $w = (& git log -1 --format="%(trailers:key=$key,valueonly)" $c | Out-String).Trim()
            if ($allowed -notcontains $w) {
                "$($c.Substring(0, 8)) ${key}: '$w' -- $((& git log -1 --format='%s' $c | Out-String).Trim())"
            }
        })
        if ($brought.Count -eq 0) {
            $failures.Add("the merge brings in no non-merge commit, so no trailer can be judged")
        }
        elseif ($bad.Count -gt 0) {
            $failures.Add("$($bad.Count) of $($brought.Count) commit(s) the merge brings in lack an allowed '${key}:' trailer: $($bad -join '; ')")
        }
        else {
            Write-Host "  OK    ${key}: on all $($brought.Count) non-merge commit(s) the merge brings in"
        }
    }
    elseif ([string]::IsNullOrWhiteSpace($who)) {
        $failures.Add("no '${key}:' trailer")
    }
    elseif ($allowed -notcontains $who) {
        $failures.Add("${key}: '$who' is not in the allowed vocabulary [$($allowed -join ', ')]")
    }
    else {
        Write-Host "  OK    ${key}: $who"
    }

    if ($failures.Count -gt 0) {
        foreach ($f in $failures) { Write-Host "  FAIL  $f" }
        Write-Host ''
        Write-Host "push-guard: FAIL -- $($failures.Count) of 2 gates failed on $($full.Substring(0, 8))"
        Write-Host 'push-guard: this branch takes merge commits from pull requests. Nothing here could refuse'
        Write-Host '            the push - the free tier has no branch protection - so this run is the record.'
        Write-Host ("::error title=direct push to a protected branch::{0} failed the push guard: {1}" -f
            $full.Substring(0, 8), ($failures -join '; '))
        exit 1
    }

    Write-Host 'push-guard: PASS -- 2 of 2 gates passed; this arrived through the flow'
    exit 0
}
finally { Pop-Location }
