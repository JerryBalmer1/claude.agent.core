#Requires -Version 7.4
<#
.SYNOPSIS
    Preflight: does any OPEN pull request already touch a file this work intends to touch?

.DESCRIPTION
    A PREFLIGHT, NOT A CHECK. This never runs in CI. `config/repo.json` -> required_checks stays
    at six, and FINDINGS F17 is the reason: the job keys in .github/workflows/ci.yml are the
    required check names branch protection knows about, and a newly required check it has never
    seen is a check that can go red while the merge proceeds anyway. This script is run by a
    human or an agent BEFORE work starts, on a workstation, and its answer is advice.

    THE SIGNAL IS OVERLAP, NOT EXISTENCE.

    "Is a pull request open?" is the wrong question and answering it produces a preflight nobody
    runs. Two docs-only branches collide with nothing; two branches editing the same module
    collide with certainty. So the only thing reported is the INTERSECTION between the paths this
    work declares and the paths an open pull request already touches. An open pull request with a
    disjoint file set is not a finding and is not printed as one.

    THE THREE EXIT CODES, AND WHY THERE ARE THREE.

        0   No open pull request touches any declared path. Nothing is emitted.
        1   At least one does. One object per overlapping pull request is emitted.
        2   The question could not be asked: `gh` is missing, unauthenticated, erroring, or
            answering something that is not the JSON it was asked for. Said on stderr.

    The third one is the point of the script. A preflight that cannot see MUST NOT report that it
    found nothing, because "no overlap" and "no answer" are the same silence and only one of them
    is safe to act on. Collapsing 2 into 0 would make the failure mode of this tool identical to
    its success, which is the absence-that-looks-like-success problem docs/IDEAS.md is about. A
    caller that treats non-zero as "stop and look" is correct under either reading; a caller that
    treats zero as "clear" is only correct because 2 exists.

    IT OBSERVES AND DOES NOT ACT. No file is written, no receipt is appended, no branch is
    created, no pull request is touched. The forensic chain records the DECISION to have this
    script, which is a fact about the repository; a preflight run is a fact about a workstation
    at a moment and does not belong in a chain that has to verify for ever.

    JSON ONLY, NEVER THE HUMAN-READABLE OUTPUT. `gh pr list` with no --json prints a table that
    is laid out for a terminal: it truncates titles, it has changed shape between gh releases,
    and it is explicitly not a contract. Scraping it would produce a tool that quietly stops
    finding overlaps after somebody upgrades gh, which is the same silent-failure shape as
    collapsing exit 2 into exit 0.

    `gh` IS CALLED AS A BARE COMMAND NAME, with no -GhCommand parameter and no injected callable,
    for the reason scripts/AutoMerge.Lib.ps1 states about itself: PowerShell resolves functions
    ahead of applications, so tests/Preflight.Tests.ps1 shadows the name with a function and
    drives this file byte-for-byte as shipped. A seam that exists only for a test is a seam the
    shipped path never takes, and a test that drives a path nobody ships proves nothing.

.PARAMETER Path
    The files or globs the upcoming work intends to touch. Accepts pipeline input, so the output
    of a `git diff --name-only` or a plan can be piped straight in.

    PIPING REQUIRES AN IN-PROCESS INVOCATION, and this was measured rather than assumed.
    `... | pwsh -NoProfile -File scripts/Invoke-Preflight.ps1` does NOT work: `-File` hands the
    child process a raw stdin stream, not a PowerShell pipeline, so nothing binds and the run dies
    on "missing mandatory parameters: Path". Use `... | ./scripts/Invoke-Preflight.ps1` from a
    pwsh session, or `pwsh -NoProfile -Command "... | ./scripts/Invoke-Preflight.ps1"`. Both were
    measured working; the -File form was measured failing.

    A pattern is matched with -like against each path an open pull request touches, so a literal
    `docs/IDEAS.md` and a glob `docs/*.md` both match the same file. Separators are normalised to
    `/` on both sides, so a Windows-style `docs\IDEAS.md` matches too. There is no directory
    shorthand: `docs` matches the file `docs` and nothing else, and a whole directory is written
    `docs/*`, which under -like also matches deeper paths such as `docs/plans/REPORT.md`.

    MATCHING IS CASE-INSENSITIVE, which git is not. That is the deliberate direction: the
    expensive error for a preflight is a false "clear", and case-insensitive matching can only
    ever report MORE overlap than git would, never less.

.PARAMETER Repo
    owner/name to ask about. Defaults to `repo` in config/repo.json rather than a literal in this
    file, so the script does not carry a second, staler copy of a fact the config already states.

.EXAMPLE
    pwsh -NoProfile -File scripts/Invoke-Preflight.ps1 -Path docs/IDEAS.md

.EXAMPLE
    pwsh -NoProfile -Command "git diff --name-only develop | ./scripts/Invoke-Preflight.ps1"

.OUTPUTS
    [pscustomobject] with Number, Title, Branch and Paths -- one per OVERLAPPING pull request.
    Paths is the intersection, not the pull request's whole file list.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path,

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$Repo
)

begin {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true
    Set-StrictMode -Version 3.0

    # Collected raw here and normalised in `end`. Nothing but accumulation happens per pipeline
    # item, so a caller piping ten thousand paths in pays for one pass and one gh conversation.
    $declared = [System.Collections.Generic.List[string]]::new()
}

process {
    foreach ($p in $Path) { $declared.Add($p) }
}

end {

    function ConvertTo-PreflightPath {
        <#
        .SYNOPSIS
            One spelling for a repository-relative path, so both sides of the comparison agree.
        #>
        param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)
        $t = $Text.Trim().Replace('\', '/')
        while ($t.StartsWith('./')) { $t = $t.Substring(2) }
        return $t.TrimStart('/')
    }

    function Exit-CannotSee {
        <#
        .SYNOPSIS
            Exit 2, loudly, on stderr.
        .DESCRIPTION
            [Console]::Error rather than Write-Error: $ErrorActionPreference is 'Stop' here, so a
            Write-Error would throw and the exit code would become pwsh's own rather than the 2
            this contract promises. The whole value of 2 is that it is distinguishable.
        #>
        param([Parameter(Mandatory)] [string]$Reason)
        [Console]::Error.WriteLine("preflight: CANNOT SEE -- $Reason")
        [Console]::Error.WriteLine('preflight: exit 2 is not exit 0. No answer was obtained; do not read this as "no overlap".')
        exit 2
    }

    # ------------------------------------------------------------------ the declared paths

    $patterns = @($declared | ForEach-Object { ConvertTo-PreflightPath $_ } | Where-Object { $_ } | Sort-Object -Unique)
    if ($patterns.Count -eq 0) {
        Exit-CannotSee 'every -Path entry was blank after normalisation; there is nothing to compare against'
    }

    # ------------------------------------------------------------------ owner/name

    if (-not $PSBoundParameters.ContainsKey('Repo')) {
        $configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'config/repo.json'
        if (-not (Test-Path -LiteralPath $configPath)) {
            Exit-CannotSee "no -Repo was given and $configPath does not exist"
        }
        try {
            $Repo = [string]((Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json -Depth 20).repo)
        }
        catch {
            Exit-CannotSee "config/repo.json could not be read: $($_.Exception.Message)"
        }
    }
    if ([string]::IsNullOrWhiteSpace($Repo)) {
        Exit-CannotSee 'the repository is empty; config/repo.json -> repo states owner/name'
    }

    Write-Host "preflight: repo $Repo"
    Write-Host "preflight: $($patterns.Count) declared path pattern(s)"
    foreach ($p in $patterns) { Write-Host "  want  $p" }

    # ------------------------------------------------------------------ can the question be asked

    if (-not (Get-Command -Name gh -ErrorAction SilentlyContinue)) {
        Exit-CannotSee 'gh is not on PATH'
    }

    # --limit is explicit because gh's default is 30 and a default that silently truncates is the
    # exact failure this script exists to refuse: the 31st open pull request would be invisible and
    # the run would report "no overlap" while meaning "I stopped looking".
    $listRaw = $null
    try {
        $listRaw = gh pr list --repo $Repo --state open --limit 200 --json number,title,headRefName | Out-String
    }
    catch {
        Exit-CannotSee "gh pr list failed: $($_.Exception.Message)"
    }
    if ([string]::IsNullOrWhiteSpace($listRaw)) {
        Exit-CannotSee 'gh pr list returned nothing at all; an empty answer is not an empty list'
    }

    $open = @()
    try { $open = @($listRaw | ConvertFrom-Json -Depth 20) }
    catch {
        Exit-CannotSee "gh pr list did not return JSON: $($_.Exception.Message)"
    }

    Write-Host "preflight: $($open.Count) open pull request(s)"

    # ------------------------------------------------------------------ the intersection

    $findings = [System.Collections.Generic.List[object]]::new()

    foreach ($pr in $open) {
        # SHAPE-CHECKED BEFORE IT IS READ. Set-StrictMode turns a missing property into a thrown
        # error, and an uncaught throw here would leave pwsh's own exit 1 behind -- which this
        # contract already spends on "overlap found". A malformed answer would then be
        # indistinguishable from a real finding. It is a cannot-see, so it exits 2.
        foreach ($field in 'number', 'title', 'headRefName') {
            if ($pr.PSObject.Properties.Name -notcontains $field) {
                Exit-CannotSee "gh pr list returned a record with no '$field'; this is not the JSON it was asked for"
            }
        }
        $number = $pr.number

        $viewRaw = $null
        try {
            $viewRaw = gh pr view $number --repo $Repo --json files | Out-String
        }
        catch {
            Exit-CannotSee "gh pr view $number failed: $($_.Exception.Message)"
        }
        if ([string]::IsNullOrWhiteSpace($viewRaw)) {
            Exit-CannotSee "gh pr view $number returned nothing"
        }

        $view = $null
        try { $view = $viewRaw | ConvertFrom-Json -Depth 20 }
        catch {
            Exit-CannotSee "gh pr view $number did not return JSON: $($_.Exception.Message)"
        }

        # A pull request with no files is possible and is not an error; it is simply disjoint.
        $touched = @()
        if ($view.PSObject.Properties.Name -contains 'files' -and $null -ne $view.files) {
            $touched = @($view.files | ForEach-Object { ConvertTo-PreflightPath ([string]$_.path) } | Where-Object { $_ })
        }

        $hits = [System.Collections.Generic.List[string]]::new()
        foreach ($t in $touched) {
            foreach ($pat in $patterns) {
                if ($t -like $pat) { $hits.Add($t); break }
            }
        }

        if ($hits.Count -eq 0) {
            Write-Host ("  clear #{0} {1} -- {2} file(s), none declared" -f $number, $pr.headRefName, $touched.Count)
            continue
        }

        $paths = @($hits | Sort-Object -Unique)
        Write-Host ("  OVERLAP #{0} {1} -- {2}" -f $number, $pr.headRefName, ($paths -join ', '))
        $findings.Add([pscustomobject]@{
            Number = [int]$number
            Title  = [string]$pr.title
            Branch = [string]$pr.headRefName
            Paths  = $paths
        })
    }

    # ------------------------------------------------------------------ the answer

    if ($findings.Count -eq 0) {
        Write-Host 'preflight: CLEAR -- no open pull request touches a declared path'
        exit 0
    }

    $findings
    Write-Host "preflight: OVERLAP -- $($findings.Count) open pull request(s) touch a declared path"
    exit 1
}
