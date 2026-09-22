#Requires -Version 7.4
<#
.SYNOPSIS
    Renders BASELINE.md from the JSON that scripts/Measure-Baseline.ps1 emitted.

.DESCRIPTION
    Split from the measuring script on purpose. The rule for this run is "every number is
    reproducible by a script in the repo"; keeping the renderer separate means the document
    can be re-rendered from a JSON somebody else produced, and it means the renderer contains
    no measurement of its own to disagree with the measurement.

    Every figure in the output comes from the JSON. There is no default, no fallback value
    and no arithmetic here that the JSON does not already contain, except the row totals,
    which are sums of the per-suite numbers in it.

.EXAMPLE
    pwsh -NoProfile -File scripts/New-BaselineMarkdown.ps1 -Json docs/plans/2026-09-22-substrate-cutover/baseline.json -Out docs/plans/2026-09-22-substrate-cutover/BASELINE.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Json,
    [Parameter(Mandatory)][string]$Out
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot = Split-Path $PSScriptRoot -Parent
$jsonPath = if ([System.IO.Path]::IsPathRooted($Json)) { $Json } else { Join-Path $RepoRoot $Json }
$outPath  = if ([System.IO.Path]::IsPathRooted($Out))  { $Out }  else { Join-Path $RepoRoot $Out }

$b = [System.IO.File]::ReadAllText($jsonPath) | ConvertFrom-Json -Depth 20

$lines = [System.Collections.Generic.List[string]]::new()
$add = { param([string]$s) $lines.Add($s) }

& $add '# BASELINE — the cutover pass counts'
& $add ''
& $add 'The README says substrate is done when image.builder''s submodule points here and its'
& $add 'in-container suite is green **at the same pass count it had at cutover**. That count had'
& $add 'never been recorded. This file is the record. Phase 6 is measured against it.'
& $add ''
& $add ('Measured on {0}. Host pwsh {1}, docker {2}.' -f $b.measured_on, $b.host_pwsh, $b.docker)
& $add ''
& $add 'Generated from `baseline.json`. Do not edit by hand and do not regenerate: this file is'
& $add 'committed exactly once, in Phase 1, and nothing in Phases 2-6 touches it. A baseline that'
& $add 'moves is not a baseline.'
& $add ''
& $add '## The exact command'
& $add ''
& $add '```powershell'
& $add 'pwsh -NoProfile -File scripts/Measure-Baseline.ps1 `'
& $add '    -Json docs/plans/2026-09-22-substrate-cutover/baseline.json `'
& $add '    -Markdown docs/plans/2026-09-22-substrate-cutover/BASELINE.md'
& $add '```'
& $add ''
& $add '## Source pins'
& $add ''
& $add '| Repository | Branch | HEAD | Dirty |'
& $add '|---|---|---|---|'
foreach ($p in $b.pins) {
    & $add ('| `{0}` | `{1}` | `{2}` | {3} |' -f $p.name, $p.branch, $p.head, $p.dirty)
}
& $add ''
& $add ('The suites measured below are **not** `claude.build.ledger` at HEAD. They are the tree')
& $add ('`claude.pwsh.image.builder` pins as its submodule:')
& $add ''
& $add '| | |'
& $add '|---|---|'
& $add ('| Submodule path | `{0}` |' -f $b.submodule.path)
& $add ('| Pinned commit | `{0}` |' -f $b.submodule.pin)
& $add ('| Pinned tree | `{0}` |' -f $b.submodule.tree)
& $add ('| `claude.build.ledger` HEAD | `{0}` |' -f $b.submodule.ledger_head)
& $add ('| Pin equals that HEAD | **{0}** |' -f $b.submodule.equals_ledger_head.ToString().ToLowerInvariant())
& $add ''
if (-not $b.submodule.equals_ledger_head) {
    & $add 'The pin is behind the sibling''s HEAD, so **the pin is the baseline**, not HEAD. The suite'
    & $add 'tree is cloned from the sibling and detached at the pin, and the measuring script asserts'
    & $add 'the resulting tree object equals the vendored one before it runs anything.'
}
else {
    & $add 'The pin and the sibling''s HEAD are the same commit.'
}
& $add ''
& $add '## Images'
& $add ''
& $add '| Tag | Image id | pwsh | Pester | `python` | `python3` |'
& $add '|---|---|---|---|---|---|'
foreach ($i in $b.images) {
    & $add ('| `{0}` | `{1}` | {2} | {3} | `{4}` | {5} |' -f $i.tag, $i.id, $i.pwsh, $i.pester, $i.python, $i.python3)
}
& $add ''
& $add 'Both images are measured because they are not interchangeable. The snake is Python.'
& $add ''

$statusOrder = @{ 'GREEN' = 0; 'RED' = 1; 'ABORTED' = 2; 'SKIPPED' = 3; 'TIMEOUT' = 4 }

foreach ($i in $b.images) {
    $rows = @($b.runs | Where-Object { $_.image -eq $i.tag })
    # Only a suite that reached its own verdict contributes to the total. An ABORTED suite has
    # a real partial count, and adding a partial to a total is how a baseline starts lying.
    $ran  = @($rows | Where-Object { $_.status -in @('GREEN', 'RED') })
    $skip = @($rows | Where-Object { $_.status -in @('ABORTED', 'SKIPPED', 'TIMEOUT') })

    & $add ('## `{0}`' -f $i.tag)
    & $add ''
    & $add '| Suite | Exit | Passed | Failed | Total | Status | Seconds | Count from |'
    & $add '|---|---|---|---|---|---|---|---|'
    foreach ($r in ($rows | Sort-Object @{ e = { $statusOrder[$_.status] } }, suite)) {
        & $add ('| `{0}` | {1} | {2} | {3} | {4} | {5} | {6} | `{7}` |' -f
            $r.suite, $r.exit, $r.passed, $r.failed, $r.total, $r.status, $r.seconds, $r.count_source)
    }
    & $add ''
    $p = ($ran | Measure-Object -Property passed -Sum).Sum
    $f = ($ran | Measure-Object -Property failed -Sum).Sum
    $t = ($ran | Measure-Object -Property total  -Sum).Sum
    if ($null -eq $p) { $p = 0 }; if ($null -eq $f) { $f = 0 }; if ($null -eq $t) { $t = 0 }
    & $add ('**{0} suite(s) produced a count: {1} passed, {2} failed, {3} checks total.**' -f $ran.Count, $p, $f, $t)
    & $add ''

    if ($skip.Count -gt 0) {
        & $add '### Not counted in that total'
        & $add ''
        & $add 'Recorded, never omitted: "the suite did not run", "the suite died partway" and "the'
        & $add 'suite has no checks" must not look the same in a table. `ABORTED` means the suite'
        & $add 'passed everything it reached and then hit a terminating error before its own summary'
        & $add 'line, so its count is a partial and is excluded from the total above.'
        & $add ''
        & $add '| Suite | Exit | Status | Reached | Why |'
        & $add '|---|---|---|---|---|'
        foreach ($r in ($skip | Sort-Object suite)) {
            $reached = if ($r.status -eq 'ABORTED') { ('{0} check(s)' -f $r.passed) } else { '-' }
            & $add ('| `{0}` | {1} | {2} | {3} | {4} |' -f
                $r.suite, $r.exit, $r.status, $reached, ($r.reason -replace '\|', '\|'))
        }
        & $add ''
    }
}

& $add '## Substrate''s own starting Pester total'
& $add ''
if ($b.substrate_pester.measured) {
    & $add ('Pester {0}, run by `scripts/ci/Invoke-Tests.ps1` in a clean worktree at `{1}`' -f
            $b.substrate_pester.pester, $b.substrate_pester.ref)
    & $add ('(`{0}`) — deliberately not in the Phase 1 working tree, which already holds Phase 1''s' -f $b.substrate_pester.commit)
    & $add 'own edits:'
    & $add ''
    & $add '| Total | Passed | Failed | Skipped |'
    & $add '|---|---|---|---|'
    & $add ('| **{0}** | {1} | {2} | {3} |' -f
        $b.substrate_pester.total, $b.substrate_pester.passed, $b.substrate_pester.failed, $b.substrate_pester.skipped)
    & $add ''
    & $add 'This is the **starting** total: the repository as it stood before Phase 1 changed'
    & $add 'anything. Phase 1 itself ends higher, because it lands tests of its own, so Phase 2''s'
    & $add '"the total went up by exactly 10" is measured against the END of Phase 1 and not'
    & $add ('against {0}. `FINDINGS.md` F15 carries both numbers and why they differ.' -f $b.substrate_pester.total)
}
else {
    & $add 'Not measured in this run.'
}
& $add ''
& $add '## What this file is not'
& $add ''
& $add 'It is not a claim that every suite above *should* be green. Several are red or unrunnable'
& $add 'in a container, and the reasons are in the tables and in `FINDINGS.md`. The baseline''s job'
& $add 'is to say what was true on the measured date, so that Phase 6 can prove the cutover changed'
& $add 'nothing — including not changing the failures.'

$text = ($lines.ToArray() -join "`n") + "`n"
$dir = Split-Path $outPath -Parent
if ($dir -and -not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
[System.IO.File]::WriteAllText($outPath, $text, [System.Text.UTF8Encoding]::new($false))
Write-Host "baseline: wrote $outPath ($($lines.Count) lines)"
exit 0
