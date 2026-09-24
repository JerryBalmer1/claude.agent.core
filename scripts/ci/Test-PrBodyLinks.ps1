#Requires -Version 7.4
<#
.SYNOPSIS
    Part of the CI check "trailer-guard": every repository path named in a pull request body is a
    sha-pinned permalink.

.DESCRIPTION
    A pull request body that says `modules/ledger/ledger.psm1:1121` is making a claim about a file
    at a moment. The branch moves, the line moves, and six months later the sentence points at
    something else -- or at nothing. A blob permalink at a 40-hex commit sha cannot rot: it names
    the bytes that were there when the claim was made. This is the same argument as the `who:`
    trailer and the receipt chain, applied to prose.

    This runs as a SECOND STEP of the existing `trailer-guard` job rather than as a new job. The
    job key is the check name GitHub reports and the automerge workflow waits on, and
    config/repo.json -> required_checks is asserted to equal the set of job keys, so a new job
    means a new required check name. FINDINGS F17 records why that is not free: a newly required
    check that branch protection has never seen is a check that can go red while the merge
    proceeds anyway. `trailer-guard` is the right host because it already judges the pull request
    object rather than the tree, and it already runs only on `pull_request`.

    THE RULE. A path token is any run of characters beginning with a tracked top-level directory
    plus a separator, or a bare tracked top-level file. Both sets are MEASURED with
    `git ls-tree HEAD` rather than hard-coded, for the same reason Test-Runtimes.ps1 reads
    `git ls-files`: a list of directories written into a check is a list that goes stale without
    telling anyone. Each token must be the visible text of a Markdown link whose target is
    https://github.com/<owner>/<repo>/blob/<40-hex-sha>/<the same path>, and where the text
    carries a :N or :N-M suffix the URL fragment must be the matching #LN or #LN-LM. Owner and
    repo come from the git remote, falling back to config/repo.json -> repo.

    EXEMPTIONS, and why each one is there.

    - Fenced code blocks are exempt. A pasted command, diff, or commit message quoted verbatim
      names paths, and rewriting evidence into links would falsify the paste. This is the escape
      hatch, and it is deliberate.
    - Inline backticks are NOT exempt. Wrap the backticks in the link instead:
      [`docs/POLICY.md`](https://github.com/o/r/blob/<sha>/docs/POLICY.md). A backtick is
      formatting, not a citation.
    - A bare URL is not a path token. A permalink is already pinned; there is nothing to check.
    - HTML comment bodies are exempt. Nothing inside <!-- --> is rendered, so nothing inside one is
      a citation, and the template ships two kinds that name paths: its own GENERATED FILE header
      and the per-section prompts. Measured, not predicted -- the first run of this check against
      a freshly generated template failed on `config/repo.json` and `scripts/Generate-Policy.ps1`
      inside that header, which was the check being wrong rather than the template.
    - A token ending in `/` is a directory reference and is satisfied by a `/tree/<sha>/` link
      rather than `/blob/`. Without this the rule would be unsatisfiable for a directory, since
      no blob URL exists for one, and a check nobody can satisfy gets switched off.

    An empty body is a violation. The template guarantees a body is never empty, so an empty one
    means the template was deleted rather than filled in.

.PARAMETER Body
    The body text, for a local run. When omitted, $env:PR_BODY is read instead, which is how the
    workflow supplies it -- as an environment variable rather than interpolated into the command
    line, so a body containing quotes or a newline cannot become part of the command.

.EXAMPLE
    pwsh -NoProfile -File scripts/ci/Test-PrBodyLinks.ps1 -Body '[`README.md`](https://github.com/o/r/blob/0000000000000000000000000000000000000000/README.md)'

.EXAMPLE
    $env:PR_BODY = (gh pr view 12 --json body --jq .body); pwsh -NoProfile -File scripts/ci/Test-PrBodyLinks.ps1
#>
[CmdletBinding()]
param(
    [AllowEmptyString()] [string]$Body,
    [string]$Remote = 'origin'
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent

# -Body wins when it is bound, even bound to the empty string, because "the body is empty" is a
# result this check has an opinion about and must be able to be handed deliberately.
$text = if ($PSBoundParameters.ContainsKey('Body')) { $Body } else { $env:PR_BODY }
if ($null -eq $text) { $text = '' }

# --------------------------------------------------------------- owner and repo

function Get-OwnerRepo {
    param([Parameter(Mandatory)] [string]$Root, [Parameter(Mandatory)] [string]$RemoteName)

    $PSNativeCommandUseErrorActionPreference = $false
    $url = (& git -C $Root remote get-url $RemoteName 2>$null | Select-Object -First 1)
    $PSNativeCommandUseErrorActionPreference = $true

    if ($url -and $url -match 'github\.com[:/](?<owner>[^/]+)/(?<repo>[^/]+?)(?:\.git)?/?\s*$') {
        return [pscustomobject]@{ Owner = $Matches['owner']; Repo = $Matches['repo']; Source = "git remote $RemoteName" }
    }

    # No remote in this clone. config/repo.json states the same pair and is itself schema-checked.
    $cfgPath = Join-Path $Root 'config/repo.json'
    if (Test-Path -LiteralPath $cfgPath) {
        $cfg = [System.IO.File]::ReadAllText($cfgPath) | ConvertFrom-Json -Depth 20
        if ($cfg.repo -match '^(?<owner>[^/]+)/(?<repo>[^/]+)$') {
            return [pscustomobject]@{ Owner = $Matches['owner']; Repo = $Matches['repo']; Source = 'config/repo.json' }
        }
    }
    throw 'pr-body-links: cannot determine owner/repo from the remote or config/repo.json'
}

$slug = Get-OwnerRepo -Root $RepoRoot -RemoteName $Remote

# ------------------------------------------------------- the tracked top level

$PSNativeCommandUseErrorActionPreference = $false
$topDirs = @(& git -C $RepoRoot ls-tree --name-only -d HEAD)
$topAll  = @(& git -C $RepoRoot ls-tree --name-only HEAD)
$PSNativeCommandUseErrorActionPreference = $true

$topDirs  = @($topDirs  | Where-Object { $_ })
$topAll   = @($topAll   | Where-Object { $_ })
$topFiles = @($topAll | Where-Object { $topDirs -notcontains $_ })

if ($topDirs.Count -eq 0 -and $topFiles.Count -eq 0) {
    throw 'pr-body-links: git ls-tree HEAD returned nothing; refusing to pass by looking at an empty set'
}

# Longest alternative first, so `.gitattributes` is never matched as `.gitignore`'s prefix or
# the other way round.
$byLengthDesc = { ($_ -as [string]).Length }
$dirAlt  = (@($topDirs  | Sort-Object -Property $byLengthDesc -Descending) | ForEach-Object { [regex]::Escape($_) }) -join '|'
$fileAlt = (@($topFiles | Sort-Object -Property $byLengthDesc -Descending) | ForEach-Object { [regex]::Escape($_) }) -join '|'

$tokenRx = [regex]::new(
    '(?<![A-Za-z0-9_./\\-])' +
    '(?:(?:' + $dirAlt + ')[/\\][A-Za-z0-9_./\\-]*|(?:' + $fileAlt + '))' +
    '(?::(?<n>\d+)(?:-(?<m>\d+))?)?')

$linkRx  = [regex]::new('\[(?<text>[^\]]*)\]\((?<url>[^)\s]+)\)')
$urlRx   = [regex]::new('^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/(?<kind>blob|tree)/(?<ref>[^/]+)/(?<path>[^#?\s]+?)/?(?:#(?<frag>\S+))?$')
$fenceRx = [regex]::new('^\s{0,3}(?:`{3,}|~{3,})')

# ------------------------------------------------------------------- the check

$violations = [System.Collections.Generic.List[string]]::new()
$checked    = 0

if ([string]::IsNullOrWhiteSpace($text)) {
    $violations.Add('pr-body-links: FAIL  (whole body)  the body is empty; the template is there to be filled in, not deleted')
}
else {
    # Blank out HTML comment bodies before anything else looks at the text. Masked in place, one
    # 'x' per character and newlines left alone, so every line number and column below still
    # refers to the body the author wrote.
    $buf = $text.ToCharArray()
    foreach ($cm in [regex]::Matches($text, '<!--.*?-->', [System.Text.RegularExpressions.RegexOptions]::Singleline)) {
        for ($k = 0; $k -lt $cm.Length; $k++) {
            $at = $cm.Index + $k
            if ($buf[$at] -ne "`n" -and $buf[$at] -ne "`r") { $buf[$at] = 'x' }
        }
    }

    $lines   = (-join $buf) -split "`r?`n"
    $inFence = $false

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $no   = $i + 1

        if ($fenceRx.IsMatch($line)) { $inFence = -not $inFence; continue }
        if ($inFence) { continue }

        $links = @($linkRx.Matches($line))

        # Mask every URL so the path inside a permalink is not itself read as a bare path. Same
        # length, so every index below still refers to the real line.
        $chars = $line.ToCharArray()
        foreach ($lm in $links) {
            $g = $lm.Groups['url']
            for ($k = 0; $k -lt $g.Length; $k++) { $chars[$g.Index + $k] = 'x' }
        }
        $maskedLine = (-join $chars)
        foreach ($bm in [regex]::Matches($maskedLine, 'https?://[^\s)\]]+')) {
            for ($k = 0; $k -lt $bm.Length; $k++) { $chars[$bm.Index + $k] = 'x' }
        }
        $maskedLine = (-join $chars)

        foreach ($tm in $tokenRx.Matches($maskedLine)) {
            # The character class has to contain '.' and '-' to match a filename, which means it
            # also swallows the full stop that ends a sentence. Give those back.
            $token = $tm.Value
            while ($token.Length -gt 0 -and ($token[-1] -eq '.' -or $token[-1] -eq '-')) {
                $token = $token.Substring(0, $token.Length - 1)
            }
            if ($token.Length -eq 0) { continue }

            $pathPart = $token
            $l1 = $null
            $l2 = $null
            if ($token -match '^(?<p>.+?):(?<n>\d+)(?:-(?<m>\d+))?$') {
                $pathPart = $Matches['p']
                $l1 = $Matches['n']
                $l2 = $Matches['m']
            }
            $pathNorm = $pathPart.Replace('\', '/')
            $isDir    = $pathNorm.EndsWith('/')
            $pathCmp  = $pathNorm.TrimEnd('/')
            $checked++

            $hostLink = $null
            foreach ($lm in $links) {
                $t = $lm.Groups['text']
                if ($tm.Index -ge $t.Index -and ($tm.Index + $token.Length) -le ($t.Index + $t.Length)) {
                    $hostLink = $lm
                    break
                }
            }

            if ($null -eq $hostLink) {
                $violations.Add("pr-body-links: FAIL  line ${no}  $token  bare path -- it is not the visible text of a link")
                continue
            }

            $url = $hostLink.Groups['url'].Value
            $um  = $urlRx.Match($url)
            if (-not $um.Success) {
                $violations.Add("pr-body-links: FAIL  line ${no}  $token  target is not a github blob or tree URL: $url")
                continue
            }
            if ($um.Groups['owner'].Value -ne $slug.Owner -or $um.Groups['repo'].Value -ne $slug.Repo) {
                $violations.Add("pr-body-links: FAIL  line ${no}  $token  target repository is $($um.Groups['owner'].Value)/$($um.Groups['repo'].Value), not $($slug.Owner)/$($slug.Repo)")
                continue
            }
            $ref = $um.Groups['ref'].Value
            if ($ref -notmatch '^[0-9a-fA-F]{40}$') {
                $violations.Add("pr-body-links: FAIL  line ${no}  $token  ref '$ref' is not a 40-hex commit sha, so the link is not pinned")
                continue
            }
            $wantKind = if ($isDir) { 'tree' } else { 'blob' }
            if ($um.Groups['kind'].Value -ne $wantKind) {
                $violations.Add("pr-body-links: FAIL  line ${no}  $token  is a $(if ($isDir) { 'directory' } else { 'file' }) reference and needs /$wantKind/, not /$($um.Groups['kind'].Value)/")
                continue
            }
            if ($um.Groups['path'].Value.TrimEnd('/') -ne $pathCmp) {
                $violations.Add("pr-body-links: FAIL  line ${no}  $token  link points at $($um.Groups['path'].Value), a different path")
                continue
            }

            $frag = if ($um.Groups['frag'].Success) { $um.Groups['frag'].Value } else { '' }
            if ($l1) {
                $want = if ($l2) { "L$l1-L$l2" } else { "L$l1" }
                if ($frag -ne $want) {
                    $shown = if ($frag) { "#$frag" } else { 'no fragment' }
                    $violations.Add("pr-body-links: FAIL  line ${no}  $token  text says :$l1$(if ($l2) { "-$l2" }) but the link has $shown, expected #$want")
                    continue
                }
            }
        }
    }
}

# ------------------------------------------------------------------ the report

Write-Host "pr-body-links: owner/repo $($slug.Owner)/$($slug.Repo), from $($slug.Source)"
Write-Host "pr-body-links: $($topDirs.Count) tracked top-level director(ies), $($topFiles.Count) tracked top-level file(s)"

foreach ($v in $violations) { Write-Host $v }

if ($violations.Count -gt 0) {
    Write-Host "pr-body-links: FAIL -- $($violations.Count) violation(s) in $checked path token(s)"
    exit 1
}

Write-Host "pr-body-links: PASS -- $checked path token(s) checked, every one a sha-pinned permalink"
exit 0
