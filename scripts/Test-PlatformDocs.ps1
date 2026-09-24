#Requires -Version 7.4
<#
.SYNOPSIS
    Is docs/claude-platform/ still true? Re-fetches every URL in its manifest and compares hashes.

.DESCRIPTION
    docs/claude-platform/ summarises Claude Code's extension surface from pages fetched on a
    stated date. Each summary is only as good as the bytes it was written from, and those bytes
    live on somebody else's server. This script is the instrument that says whether they still
    do: it fetches every URL in docs/claude-platform/manifest.json as raw bytes, hashes them with
    SHA-256, and compares the result with the hash recorded when the summary was written.

    THE THREE EXIT CODES, AND WHY THERE ARE THREE.

        0   Every URL answered 200 and hashed to the recorded value. The tree may be trusted.
        1   At least one URL drifted: a different hash, or a status other than 200. One object
            per drifted URL is emitted and every drifted URL is printed. The summaries citing it
            are stale until they are refetched and re-read.
        2   The question could not be asked: the manifest is missing, malformed or empty, or a
            URL could not be fetched at all (DNS, TLS, timeout). Said on stderr.

    2 is kept apart from 0 for the reason scripts/Invoke-Preflight.ps1 gives: "no drift" and
    "no answer" are the same silence and only one of them is safe to act on. Drift outranks
    blindness: if one URL drifted and another could not be fetched, the answer is 1, because a
    known drift is already enough to stop trusting the tree, and the unfetched URLs are still
    listed.

    A 404 is DRIFT, not blindness. The server answered; what it said is that the page the
    summary was written from is no longer there.

    IT OBSERVES AND DOES NOT ACT. The manifest is never rewritten, no page is saved, and nothing
    is refetched into the tree. Refreshing the reference is a deliberate act with a human-readable
    diff, described in docs/claude-platform/README.md, not a side effect of checking it.

    Invoke-WebRequest IS CALLED BY NAME with no injected fetcher, for the reason
    scripts/AutoMerge.Lib.ps1 gives: tests/PlatformDocs.Tests.ps1 mocks the command and drives
    this file byte-for-byte as shipped. CI never touches the network; the real fetch is a manual
    step, run on a workstation.

.PARAMETER ManifestPath
    Defaults to docs/claude-platform/manifest.json under the repository root.

.PARAMETER TimeoutSec
    Per-request timeout. A timeout is exit 2, not exit 0.

.EXAMPLE
    pwsh -NoProfile -File scripts/Test-PlatformDocs.ps1

.OUTPUTS
    [pscustomobject] with Url, Reason, Expected and Actual -- one per DRIFTED url.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$ManifestPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/claude-platform/manifest.json'),

    [Parameter()]
    [ValidateRange(1, 600)]
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

function Exit-CannotSee {
    <#
    .SYNOPSIS
        Exit 2, loudly, on stderr. [Console]::Error rather than Write-Error, because under
        ErrorActionPreference Stop a Write-Error throws and the exit code stops being 2.
    #>
    param([Parameter(Mandatory)] [string]$Reason)
    [Console]::Error.WriteLine("platform-docs: CANNOT SEE -- $Reason")
    [Console]::Error.WriteLine('platform-docs: exit 2 is not exit 0. No answer was obtained; do not read this as "still true".')
    exit 2
}

# ------------------------------------------------------------------ the manifest

if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    Exit-CannotSee "no manifest at $ManifestPath"
}

$manifest = $null
try { $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json -Depth 20 }
catch { Exit-CannotSee "the manifest is not JSON: $($_.Exception.Message)" }

if ($null -eq $manifest -or $manifest.PSObject.Properties.Name -notcontains 'pages') {
    Exit-CannotSee 'the manifest has no "pages" array'
}

$pages = @($manifest.pages)
if ($pages.Count -eq 0) {
    Exit-CannotSee 'the manifest lists zero pages; a check that checks nothing is not a check'
}

foreach ($p in $pages) {
    # Shape-checked before it is read: under StrictMode a missing property throws, pwsh exits 1,
    # and a malformed manifest would be indistinguishable from real drift.
    foreach ($field in 'url', 'sha256', 'fetched', 'bytes') {
        if ($null -eq $p -or $p.PSObject.Properties.Name -notcontains $field) {
            Exit-CannotSee "a manifest entry has no '$field'"
        }
    }
    if ([string]$p.sha256 -notmatch '^[0-9a-f]{64}$') {
        Exit-CannotSee "the manifest entry for $($p.url) has a sha256 that is not 64 lowercase hex"
    }
}

$oldest = @($pages | ForEach-Object { [string]$_.fetched } | Sort-Object)[0]
Write-Host "platform-docs: manifest $ManifestPath"
Write-Host "platform-docs: $($pages.Count) url(s), oldest fetch $oldest"

# ------------------------------------------------------------------ fetch and compare

$drift  = [System.Collections.Generic.List[object]]::new()
$unseen = [System.Collections.Generic.List[string]]::new()

foreach ($p in $pages) {
    $url = [string]$p.url
    $expected = ([string]$p.sha256).ToLowerInvariant()

    $resp = $null
    try {
        # -SkipHttpErrorCheck so a 404 comes back as an answer rather than an exception: a missing
        # page is drift, and only a failure to get any answer at all is blindness.
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -SkipHttpErrorCheck -TimeoutSec $TimeoutSec
    }
    catch {
        Write-Host "  UNSEEN  $url -- $($_.Exception.Message)"
        $unseen.Add($url)
        continue
    }

    $status = [int]$resp.StatusCode
    if ($status -ne 200) {
        Write-Host "  DRIFT   $url -- HTTP $status"
        $drift.Add([pscustomobject]@{ Url = $url; Reason = "HTTP $status"; Expected = $expected; Actual = '' })
        continue
    }

    # The raw bytes, never .Content: .Content is a decoded string, and a hash over a decoding is a
    # hash over this machine's idea of the charset rather than over what the server sent.
    $bytes  = $resp.RawContentStream.ToArray()
    $actual = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()

    if ($actual -ne $expected) {
        $reason = 'sha256 {0} -> {1}, bytes {2} -> {3}' -f $expected.Substring(0, 12), $actual.Substring(0, 12), $p.bytes, $bytes.Length
        Write-Host "  DRIFT   $url -- $reason"
        $drift.Add([pscustomobject]@{ Url = $url; Reason = $reason; Expected = $expected; Actual = $actual })
        continue
    }

    Write-Host "  same    $url"
}

# ------------------------------------------------------------------ the answer

if ($drift.Count -gt 0) {
    $drift
    Write-Host "platform-docs: DRIFT -- $($drift.Count) of $($pages.Count) url(s) changed:"
    foreach ($d in $drift) { Write-Host "  $($d.Url)" }
    if ($unseen.Count -gt 0) {
        Write-Host "platform-docs: and $($unseen.Count) url(s) could not be fetched:"
        foreach ($u in $unseen) { Write-Host "  $u" }
    }
    exit 1
}

if ($unseen.Count -gt 0) {
    Exit-CannotSee "$($unseen.Count) of $($pages.Count) url(s) could not be fetched: $($unseen -join ', ')"
}

Write-Host "platform-docs: CLEAN -- all $($pages.Count) url(s) match the manifest"
exit 0
