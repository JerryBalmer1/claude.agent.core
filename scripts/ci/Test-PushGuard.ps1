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

    2. It carries a `who:` trailer from the allowed vocabulary. The automerge workflow writes
       `who: claude` into every merge commit body it creates, so a merge commit without one was
       not made by the automation either.

    The grandfather file is DELIBERATELY NOT CONSULTED. config/trailer-grandfather.txt exempts
    commits inherited from before the guard existed, which is a statement about history. This
    script judges an event happening now. Sharing the list would let an old hash excuse a new
    push, and the exemption would quietly become a skeleton key.

.EXAMPLE
    pwsh -NoProfile -File scripts/ci/Test-PushGuard.ps1 -Sha $env:GITHUB_SHA
#>
[CmdletBinding()]
param(
    [string]$Sha = 'HEAD'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$config   = (Get-Content -LiteralPath (Join-Path $RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20)
$key      = $config.trailer.key
$allowed  = @($config.trailer.allowed)

Push-Location $RepoRoot
try {
    $full    = (& git rev-parse $Sha | Out-String).Trim()
    $subject = (& git log -1 --format='%s' $full | Out-String).Trim()
    $parents = @((& git log -1 --format='%P' $full | Out-String).Trim() -split '\s+' | Where-Object { $_ -ne '' })
    $who     = (& git log -1 --format="%(trailers:key=$key,valueonly)" $full | Out-String).Trim()

    Write-Host "push-guard: commit $($full.Substring(0, 8))  $subject"
    Write-Host "push-guard: parents $($parents.Count) [$($parents | ForEach-Object { $_.Substring(0, 8) })]"
    Write-Host "push-guard: ${key}: '$who'  (allowed: $($allowed -join ', '))"
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

    if ([string]::IsNullOrWhiteSpace($who)) {
        $failures.Add("no '${key}:' trailer - automerge writes one into every merge commit it creates, so this was not made by the automation")
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
