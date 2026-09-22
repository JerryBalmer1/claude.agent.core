#Requires -Version 7.4
<#
.SYNOPSIS
    Measures the Ledger sandbox suites INSIDE the images claude.pwsh.image.builder ships,
    and emits one JSON object per suite. docs/plans/2026-09-22-substrate-cutover/BASELINE.md
    is rendered from that JSON; it is never typed.

.DESCRIPTION
    The README's definition of done is "image.builder's in-container suite is green at the
    same pass count it had at cutover". That sentence has a hole: the cutover pass count was
    never recorded. This script is the thing that closes it, and the thing Phase 6 re-runs to
    prove the cutover changed nothing.

    Design decisions worth knowing before you trust a number out of it:

    WHERE THE SUITES COME FROM. image.builder vendors claude.build.ledger as a submodule and
    its Dockerfile copies only `src/ledger/` into the image - `tests/sandbox/` is not baked in.
    So the suites have to be bind-mounted. Mounting image.builder's own submodule working tree
    would let the suites write into a sibling repository, which Phases 1-5 are forbidden to do
    (ledger_chain.ps1 appends two receipts by design; fuzzer_import.ps1 writes fixtures). This
    script instead clones claude.build.ledger into a temp directory, detaches it at the exact
    sha image.builder's submodule pins, and asserts the resulting tree object equals the
    vendored tree before running anything. Same bytes, somewhere disposable.

    WHY A CLONE AND NOT A COPY. continuity.ps1 and no_sabotage.ps1 ask git questions. A copied
    working tree has no .git and those checks degrade to SKIP, which would understate the
    baseline. The clone carries real history.

    WHY GIT_CONFIG_GLOBAL. A bind-mounted tree carries host ownership, and git refuses to
    operate in a repository owned by another user ("detected dubious ownership", exit 128).
    That failure reads as a dozen failed checks rather than as one configuration problem.
    image.builder hit the same wall and solved it the same way; the exception is written into
    the temp directory, scoped to these runs, and neither image carries it.

    HOW A COUNT IS OBTAINED. The suites do not share a summary format, so guessing one would
    be the kind of number this repo does not permit. Three parsers are tried in order and the
    JSON records which one produced the count, per suite, in `count_source`:
      summary-covenant : "=== NO SABOTAGE COVENANT: N passed, M failed ==="
      summary-checks   : "checks run: N" plus "ALL CHECKS PASSED" or "N of M CHECK(S) FAILED"
      markers          : counted "  PASS  " / "  FAIL  " lines emitted by the suite's own
                         assertion helper
      single-verdict   : a suite that is one assertion and says so once (fail_path.ps1)
      none             : nothing parseable - recorded as such, never as zero-of-zero green

    A suite that cannot run in this image is recorded as SKIPPED with the reason. It is never
    omitted: "the suite was not run" and "the suite has no checks" must not look the same.

.PARAMETER Image
    One or more image tags to measure. Both are measured by default because they are not
    interchangeable: the leash image ships no python and the developer image does, and the
    snake is python.

.PARAMETER Json
    Where the measurement object is written. Required - this script's output IS the file.

.PARAMETER Markdown
    Optional. Renders BASELINE.md from the object just measured.

.EXAMPLE
    pwsh -NoProfile -File scripts/Measure-Baseline.ps1 `
        -Json docs/plans/2026-09-22-substrate-cutover/baseline.json `
        -Markdown docs/plans/2026-09-22-substrate-cutover/BASELINE.md
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$ImageBuilderPath = 'C:\__Code\____Claude.Build\claude.pwsh.image.builder',

    [Parameter()]
    [string]$LedgerRepoPath = 'C:\__Code\____Claude.Build\claude.build.ledger',

    [Parameter()]
    [string]$PolicyRepoPath = 'C:\__Code\____Claude.Build\claude.build.policy',

    [Parameter()]
    [string[]]$Image = @('claude.pwsh.image.leash:run-01', 'claude.pwsh.image.developer:run-01'),

    [Parameter()]
    [string]$SubmodulePath = 'vendor/claude.build.ledger',

    [Parameter()]
    [string]$SuiteRoot = 'tests/sandbox',

    [Parameter(Mandatory)]
    [string]$Json,

    [Parameter()]
    [string]$Markdown,

    [Parameter()]
    [ValidateRange(30, 3600)]
    [int]$TimeoutSeconds = 900,

    [Parameter()]
    [string]$SubstrateBaselineRef = 'origin/develop',

    [Parameter()]
    [switch]$SkipSubstratePester
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path $PSScriptRoot -Parent

# --------------------------------------------------------------------------- helpers

function Get-GitValue {
    <#  One git invocation, trimmed, or the empty string. Never throws on a repo that is
        simply not there - the caller records that as a finding, not as a crash. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$GitArgs)
    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $old = $PSNativeCommandUseErrorActionPreference
    $PSNativeCommandUseErrorActionPreference = $false
    try {
        $out = & git -C $Path @GitArgs 2>$null
        if ($LASTEXITCODE -ne 0) { return '' }
        return (($out | Out-String).Trim())
    }
    finally { $PSNativeCommandUseErrorActionPreference = $old }
}

function Get-RepoPin {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][string]$Path)
    $head = Get-GitValue -Path $Path -GitArgs @('rev-parse', 'HEAD')
    return [ordered]@{
        name    = $Name
        path    = $Path
        present = [bool]$head
        branch  = (Get-GitValue -Path $Path -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD'))
        head    = $head
        tree    = (Get-GitValue -Path $Path -GitArgs @('rev-parse', 'HEAD^{tree}'))
        subject = (Get-GitValue -Path $Path -GitArgs @('log', '-1', '--format=%s'))
        # Parenthesised: without them PowerShell binds -split as a parameter of Get-GitValue.
        dirty   = @((Get-GitValue -Path $Path -GitArgs @('status', '--porcelain')) -split "`n" |
                    Where-Object { $_.Trim() }).Count
    }
}

function Remove-Ansi {
    <#  pwsh colourises errors even when stderr is a redirected file, so the escape sequences
        come back with the text and end up inside the committed JSON and the rendered table,
        where they are unreadable and, worse, change the bytes of a document that is supposed
        to be comparable. Stripped at the point of capture, once. #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    return ($Text -replace "`e\[[0-9;]*[A-Za-z]", '')
}

function Measure-SuiteOutput {
    <#  Turn a suite's stdout into {passed, failed, total, count_source}. See .DESCRIPTION.
        Returns count_source = 'none' rather than inventing a zero. #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)

    $lines = $Text -split "`r?`n"

    $covenant = $lines | Where-Object { $_ -match '^=== NO SABOTAGE COVENANT: (\d+) passed, (\d+) failed ===' } | Select-Object -Last 1
    if ($covenant) {
        $null = $covenant -match '^=== NO SABOTAGE COVENANT: (\d+) passed, (\d+) failed ==='
        $p = [int]$Matches[1]; $f = [int]$Matches[2]
        return [ordered]@{ passed = $p; failed = $f; total = $p + $f; count_source = 'summary-covenant' }
    }

    $checksRun = $lines | Where-Object { $_ -match '^checks run: (\d+)\s*$' } | Select-Object -Last 1
    if ($checksRun) {
        $null = $checksRun -match '^checks run: (\d+)\s*$'
        $total = [int]$Matches[1]
        $failLine = $lines | Where-Object { $_ -match '^(\d+) of (\d+) CHECK\(S\) FAILED' } | Select-Object -Last 1
        if ($failLine) {
            $null = $failLine -match '^(\d+) of (\d+) CHECK\(S\) FAILED'
            $f = [int]$Matches[1]
            return [ordered]@{ passed = $total - $f; failed = $f; total = $total; count_source = 'summary-checks' }
        }
        if ($lines | Where-Object { $_ -cmatch '^ALL CHECKS PASSED' }) {
            return [ordered]@{ passed = $total; failed = 0; total = $total; count_source = 'summary-checks' }
        }
    }

    $markPass = @($lines | Where-Object { $_ -cmatch '^\s{2}PASS\s{2}\S' }).Count
    $markFail = @($lines | Where-Object { $_ -cmatch '^\s{2}FAIL\s{2}\S' }).Count
    if (($markPass + $markFail) -gt 0) {
        return [ordered]@{ passed = $markPass; failed = $markFail; total = $markPass + $markFail; count_source = 'markers' }
    }

    $verdictPass = @($lines | Where-Object { $_ -cmatch '^PASS: ' }).Count
    $verdictFail = @($lines | Where-Object { $_ -cmatch '^FAIL: ' }).Count
    if (($verdictPass + $verdictFail) -gt 0) {
        return [ordered]@{ passed = $verdictPass; failed = $verdictFail; total = $verdictPass + $verdictFail; count_source = 'single-verdict' }
    }

    return [ordered]@{ passed = 0; failed = 0; total = 0; count_source = 'none' }
}

function Invoke-ContainerSuite {
    <#  One suite, one container, wall-clocked, killed on timeout rather than left to hang
        the whole measurement. Start-Process + WaitForExit is used instead of the call
        operator so that a timeout is detectable at all. #>
    param(
        [Parameter(Mandatory)][string]$ImageTag,
        [Parameter(Mandatory)][string]$MountPath,
        [Parameter(Mandatory)][string]$SuiteRelPath,
        [Parameter(Mandatory)][int]$Timeout
    )

    $name = 'substrate-baseline-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 12)
    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $mount = $MountPath.Replace('\', '/')

    $dockerArgs = @(
        'run', '--rm', '--name', $name,
        '-v', "${mount}:/work",
        '-w', '/work',
        '-e', 'GIT_CONFIG_GLOBAL=/work/.substrate-baseline.gitconfig',
        '-e', 'LEDGER_PRINCIPAL=substrate-baseline',
        '--entrypoint', 'pwsh',
        $ImageTag,
        '-NoProfile', '-File', "/work/$SuiteRelPath"
    )

    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $proc = Start-Process -FilePath 'docker' -ArgumentList $dockerArgs -NoNewWindow -PassThru `
                          -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
    $exited = $proc.WaitForExit($Timeout * 1000)
    if (-not $exited) {
        & docker kill $name 2>&1 | Out-Null
        $null = $proc.WaitForExit(30000)
    }
    $sw.Stop()

    $stdout = Remove-Ansi -Text $(if (Test-Path -LiteralPath $tmpOut) { [System.IO.File]::ReadAllText($tmpOut) } else { '' })
    $stderr = Remove-Ansi -Text $(if (Test-Path -LiteralPath $tmpErr) { [System.IO.File]::ReadAllText($tmpErr) } else { '' })
    Remove-Item -LiteralPath $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

    return [ordered]@{
        exit      = if ($exited) { $proc.ExitCode } else { -1 }
        timed_out = (-not $exited)
        seconds   = [math]::Round($sw.Elapsed.TotalSeconds, 2)
        stdout    = $stdout
        stderr    = $stderr
    }
}

# --------------------------------------------------------------------------- pins

Write-Host 'baseline: recording source pins'

$pins = @(
    (Get-RepoPin -Name 'claude.agent.substrate'    -Path $RepoRoot),
    (Get-RepoPin -Name 'claude.build.ledger'       -Path $LedgerRepoPath),
    (Get-RepoPin -Name 'claude.build.policy'       -Path $PolicyRepoPath),
    (Get-RepoPin -Name 'claude.pwsh.image.builder' -Path $ImageBuilderPath)
)
foreach ($p in $pins) { Write-Host ("  {0,-28} {1} {2}" -f $p.name, $p.head, $p.branch) }

$submoduleWorktree = Join-Path $ImageBuilderPath $SubmodulePath

# The pin is read from the tree object, not from `git submodule status`. That command's first
# character is a flag (' ', '+', '-', 'U') which a trim silently eats, and a pin whose
# in-sync marker was thrown away is a number with no provenance. `ls-tree` states the gitlink
# outright: "160000 commit <sha>\t<path>".
$lsTree = Get-GitValue -Path $ImageBuilderPath -GitArgs @('ls-tree', 'HEAD', '--', $SubmodulePath)
if ($lsTree -notmatch '^160000\s+commit\s+([0-9a-f]{40})\s') {
    throw "no gitlink at $SubmodulePath in $ImageBuilderPath (ls-tree said: '$lsTree')"
}
$submodulePin = $Matches[1]

$submoduleWorktreeHead = Get-GitValue -Path $submoduleWorktree -GitArgs @('rev-parse', 'HEAD')
$submoduleDirty = @((Get-GitValue -Path $submoduleWorktree -GitArgs @('status', '--porcelain')) -split "`n" |
                    Where-Object { $_.Trim() }).Count
$submoduleInSync = ($submoduleWorktreeHead -eq $submodulePin) -and ($submoduleDirty -eq 0)
$submoduleTree = Get-GitValue -Path $submoduleWorktree -GitArgs @('rev-parse', 'HEAD^{tree}')

Write-Host "  submodule pin                $submodulePin"
Write-Host "  submodule worktree           $submoduleWorktreeHead dirty=$submoduleDirty in_sync=$submoduleInSync"
if (-not $submoduleInSync) {
    throw "the vendored worktree does not match the pin; the baseline would be measured against something image.builder does not actually ship"
}

$ledgerHead = ($pins | Where-Object { $_.name -eq 'claude.build.ledger' }).head
$pinIsHead = ($submodulePin -eq $ledgerHead)
Write-Host "  pin equals ledger HEAD?      $pinIsHead"

# --------------------------------------------------------------------------- suite tree

$work = Join-Path ([System.IO.Path]::GetTempPath()) ('substrate-baseline-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
Write-Host "baseline: materialising the pinned suite tree at $work"

& git clone --no-hardlinks --quiet $LedgerRepoPath $work
& git -C $work checkout --quiet --detach $submodulePin
$workHead = Get-GitValue -Path $work -GitArgs @('rev-parse', 'HEAD')
$workTree = Get-GitValue -Path $work -GitArgs @('rev-parse', 'HEAD^{tree}')

if ($workHead -ne $submodulePin) { throw "clone is at $workHead, expected the pin $submodulePin" }
if ($submoduleTree -and ($workTree -ne $submoduleTree)) {
    throw "clone tree $workTree does not equal the vendored tree $submoduleTree"
}
Write-Host "  tree $workTree matches the vendored tree"

# safe.directory as a FILE, in global scope: a bind mount carries host ownership and git
# refuses a repository it thinks belongs to someone else. Scoped to these runs only.
$gitConfigPath = Join-Path $work '.substrate-baseline.gitconfig'
[System.IO.File]::WriteAllText($gitConfigPath, "[safe]`n`tdirectory = *`n", [System.Text.UTF8Encoding]::new($false))

$suiteDir = Join-Path $work $SuiteRoot
$suites = @(Get-ChildItem -LiteralPath $suiteDir -Filter '*.ps1' -File | Sort-Object Name)
if ($suites.Count -eq 0) { throw "no suites found under $suiteDir" }
Write-Host "  $($suites.Count) suite(s): $(($suites.Name) -join ', ')"

# --------------------------------------------------------------------------- environment

$dockerVersion = (& docker version --format '{{.Server.Version}}').Trim()
$images = @()
foreach ($tag in $Image) {
    $id = (& docker image inspect $tag --format '{{.Id}}').Trim()
    $probe = & docker run --rm --entrypoint pwsh $tag -NoProfile -Command `
        '"{0}|{1}|{2}|{3}" -f $PSVersionTable.PSVersion, ((Get-Module -ListAvailable Pester).Version -join ","), $(if (Get-Command python -EA SilentlyContinue) { "python" } else { "-" }), $(if (Get-Command python3 -EA SilentlyContinue) { (python3 --version) } else { "-" })'
    $parts = ($probe | Out-String).Trim() -split '\|'
    $images += [ordered]@{
        tag     = $tag
        id      = $id
        pwsh    = $parts[0]
        pester  = $parts[1]
        python  = $parts[2]
        python3 = $parts[3]
    }
    Write-Host ("  image {0,-38} {1}" -f $tag, $id)
    Write-Host ("        pwsh={0} pester={1} python={2} python3={3}" -f $parts[0], $parts[1], $parts[2], $parts[3])
}

# --------------------------------------------------------------------------- measure

$runs = @()
foreach ($img in $images) {
    Write-Host ''
    Write-Host "baseline: measuring in $($img.tag)"
    foreach ($s in $suites) {
        $rel = "$SuiteRoot/$($s.Name)"
        Write-Host "  running $rel ..." -NoNewline
        $r = Invoke-ContainerSuite -ImageTag $img.tag -MountPath $work -SuiteRelPath $rel -Timeout $TimeoutSeconds
        $counts = Measure-SuiteOutput -Text ($r.stdout + "`n" + $r.stderr)

        # ABORTED is its own row and not a flavour of RED. A suite that ran eleven checks, passed
        # all eleven and then died on the twelfth reports passed=11 failed=0 exit=1; calling that
        # RED puts "11/11" and "RED" on the same line, which reads as a contradiction and hides
        # the only fact that matters - that the suite never reached its own summary.
        $status = if ($r.timed_out) { 'TIMEOUT' }
                  elseif ($counts.count_source -eq 'none') { 'SKIPPED' }
                  elseif ($r.exit -eq 0 -and $counts.failed -eq 0) { 'GREEN' }
                  elseif ($counts.failed -eq 0) { 'ABORTED' }
                  else { 'RED' }

        # Why a suite did not finish green is the whole value of its row. A PowerShell
        # terminating error goes to stderr and its FIRST line carries the message; the lines
        # after it are the caret diagram. stdout's last line is only worth reading when stderr
        # is empty, and then it says how far the suite got.
        $stdoutLines = @($r.stdout -split "`r?`n" | Where-Object { $_.Trim() })
        $stderrLines = @($r.stderr -split "`r?`n" | Where-Object { $_.Trim() })

        # pwsh spreads one error over several lines: a "Cmdlet: file:line" header, then a
        # "Line |" caret diagram, then the message. Taking only the first line gives the
        # location and no cause; taking the last gives a row of tildes. Drop the diagram and
        # keep the first two lines of prose.
        $prose = @($stderrLines | Where-Object { $_ -notmatch '^\s*(Line\s*\||\||\s*\|)' } |
                   ForEach-Object { $_.Trim() })
        $reason = ''
        if ($status -ne 'GREEN') {
            $reason = if ($r.timed_out) { "killed after $TimeoutSeconds s" }
                      elseif ($prose.Count -gt 0) { (($prose | Select-Object -First 2) -join ' -- ') }
                      elseif ($stdoutLines.Count -gt 0) { 'last output: ' + ($stdoutLines | Select-Object -Last 1).Trim() }
                      else { 'no output at all' }
            if ($reason.Length -gt 300) { $reason = $reason.Substring(0, 300) + '...' }
        }

        # The raw evidence behind the row, trimmed to something a JSON can carry. Without it
        # every number above is an assertion with no receipt.
        $tail = @(($stdoutLines + $stderrLines) | Select-Object -Last 8 |
                  ForEach-Object { if ($_.Length -gt 200) { $_.Substring(0, 200) + '...' } else { $_.Trim() } })

        $runs += [ordered]@{
            image        = $img.tag
            suite        = $s.Name
            exit         = $r.exit
            passed       = $counts.passed
            failed       = $counts.failed
            total        = $counts.total
            count_source = $counts.count_source
            seconds      = $r.seconds
            status       = $status
            reason       = $reason
            tail         = $tail
        }
        Write-Host (" exit={0} {1} {2}/{3} ({4}s)" -f $r.exit, $status, $counts.passed, $counts.total, $r.seconds)
        if ($reason) { Write-Host "      reason: $reason" }
    }
}

# --------------------------------------------------------------------------- substrate pester

$substratePester = [ordered]@{
    measured = $false; ref = $SubstrateBaselineRef; commit = ''
    total = 0; passed = 0; failed = 0; skipped = 0; pester = ''
}
if (-not $SkipSubstratePester) {
    Write-Host ''
    Write-Host "baseline: substrate own suite, from a clean worktree at $SubstrateBaselineRef"

    # NOT the working tree. "Starting total" means the total BEFORE this phase changed
    # anything, and the tree this script runs from already holds Phase 1's own edits - it
    # reported 47 with 2 failures the first time, purely because the policy document had not
    # been regenerated yet. A baseline contaminated by the work it is the baseline for is
    # worse than no baseline: it looks like a measurement.
    $wt = Join-Path ([System.IO.Path]::GetTempPath()) ('substrate-wt-' + [System.Guid]::NewGuid().ToString('N').Substring(0, 8))
    & git -C $RepoRoot worktree add --quiet --detach $wt $SubstrateBaselineRef
    try {
        $substratePester.commit = Get-GitValue -Path $wt -GitArgs @('rev-parse', 'HEAD')
        Write-Host "  worktree at $($substratePester.commit)"
        $old = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
        try {
            $out = & pwsh -NoProfile -File (Join-Path $wt 'scripts/ci/Invoke-Tests.ps1') 2>&1 | Out-String
        }
        finally { $PSNativeCommandUseErrorActionPreference = $old }
    }
    finally {
        & git -C $RepoRoot worktree remove --force $wt 2>&1 | Out-Null
    }

    if ($out -match 'pester: total=(\d+) passed=(\d+) failed=(\d+) skipped=(\d+)') {
        $substratePester.measured = $true
        $substratePester.total    = [int]$Matches[1]
        $substratePester.passed   = [int]$Matches[2]
        $substratePester.failed   = [int]$Matches[3]
        $substratePester.skipped  = [int]$Matches[4]
    }
    if ($out -match 'pester: imported ([0-9.]+)') { $substratePester.pester = $Matches[1] }
    Write-Host ("  total={0} passed={1} failed={2}" -f $substratePester.total, $substratePester.passed, $substratePester.failed)
}

# --------------------------------------------------------------------------- emit

$result = [ordered]@{
    schema           = 'claude.agent.substrate/baseline/1'
    measured_on      = (Get-Date -Format 'yyyy-MM-dd')
    host_pwsh        = $PSVersionTable.PSVersion.ToString()
    docker           = $dockerVersion
    pins             = $pins
    submodule        = [ordered]@{
        path               = $SubmodulePath
        pin                = $submodulePin
        worktree_head      = $submoduleWorktreeHead
        worktree_dirty     = $submoduleDirty
        in_sync            = $submoduleInSync
        tree               = $submoduleTree
        equals_ledger_head = $pinIsHead
        ledger_head        = $ledgerHead
    }
    suite_tree       = [ordered]@{ source = $LedgerRepoPath; head = $workHead; tree = $workTree; root = $SuiteRoot }
    images           = $images
    suites           = @($suites.Name)
    runs             = $runs
    substrate_pester = $substratePester
    command          = "pwsh -NoProfile -File scripts/Measure-Baseline.ps1 -Json <json> -Markdown <md>"
}

$jsonPath = if ([System.IO.Path]::IsPathRooted($Json)) { $Json } else { Join-Path $RepoRoot $Json }
$jsonDir = Split-Path $jsonPath -Parent
if ($jsonDir -and -not (Test-Path -LiteralPath $jsonDir)) { $null = New-Item -ItemType Directory -Path $jsonDir -Force }
$jsonText = ($result | ConvertTo-Json -Depth 10) -replace "`r`n", "`n"
[System.IO.File]::WriteAllText($jsonPath, $jsonText + "`n", [System.Text.UTF8Encoding]::new($false))
Write-Host ''
Write-Host "baseline: wrote $jsonPath"

if ($Markdown) {
    $mdPath = if ([System.IO.Path]::IsPathRooted($Markdown)) { $Markdown } else { Join-Path $RepoRoot $Markdown }
    & (Join-Path $PSScriptRoot 'New-BaselineMarkdown.ps1') -Json $jsonPath -Out $mdPath
}

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

$red = @($runs | Where-Object { $_.status -eq 'RED' }).Count
Write-Host "baseline: $($runs.Count) run(s), $red RED, $(@($runs | Where-Object { $_.status -eq 'GREEN' }).Count) GREEN, $(@($runs | Where-Object { $_.status -eq 'SKIPPED' }).Count) SKIPPED"
Write-Host 'baseline: a RED row is a measurement, not a failure of this script'
exit 0
