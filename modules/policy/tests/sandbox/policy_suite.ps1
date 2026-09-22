#Requires -Version 7.4
<#
.SYNOPSIS
    Prove claude.build.policy v0: Get-PolicyRules loads, parses, hashes stably, and
    writes nothing.

.DESCRIPTION
    Ten numbered checks. Exit 0 and print ALL CHECKS PASSED, or exit 1 with a
    failure count. No Pester. Plain assertions.

      1. the manifest imports and Get-PolicyRules exists
      2. build.ps1 exits 0 and names the version and the module
      3. a missing path throws PolicyPathNotFound
      4. this repo root yields rules, all eight properties populated, 64 hex Hash
      5. the same file parsed twice gives the same Hash per Id
      6. ../claude.build.ledger/AGENTS.md yields an import or Ledger rule
      7. ../claude.build.fuzzer/docs/do-not.md yields at least one rule
      8. a temp file of "hello world" yields zero rules and does not throw
      9. a temp file of "- Do not import Ledger" yields a halt-weight law rule
     10. the repo tree is byte-identical to where it started and the temp files
         are gone

    Every file this script creates lives in $env:TEMP and is deleted before exit.
    Nothing under the repo is written.

.EXAMPLE
    pwsh -NoProfile -File tests/sandbox/policy_suite.ps1

.EXAMPLE
    pwsh -NoProfile -File tests/sandbox/policy_suite.ps1 -Verbose
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'Continue' }

$repo = [System.IO.Path]::GetFullPath((Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..'))
$workspace = Split-Path -Parent $repo
$srcDir = Join-Path -Path $repo -ChildPath 'src' -AdditionalChildPath 'claude.build.policy'
$manifest = Join-Path -Path $srcDir -ChildPath 'claude.build.policy.psd1'
$buildScript = Join-Path -Path $repo -ChildPath 'build.ps1'

if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) { throw "manifest not found at $manifest" }

$script:Failures = 0
$script:CheckFailed = $false
$script:CheckNotes = [System.Collections.Generic.List[string]]::new()
$script:TempFiles = [System.Collections.Generic.List[string]]::new()

function Assert-That {
    param(
        [Parameter(Mandatory)][AllowNull()][object]$Condition,
        [Parameter(Mandatory)][string]$Message,
        [Parameter()][string]$Detail = ''
    )

    if ($Condition) {
        Write-Verbose "    ok: $Message"
        return
    }

    $script:CheckFailed = $true
    $note = if ($Detail) { "$Message ($Detail)" } else { $Message }
    $script:CheckNotes.Add($note)
}

function Invoke-Check {
    param(
        [Parameter(Mandatory)][int]$Number,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Body
    )

    $script:CheckFailed = $false
    $script:CheckNotes.Clear()

    try {
        & $Body
    }
    catch {
        $script:CheckFailed = $true
        $script:CheckNotes.Add("unexpected error: $($_.Exception.Message)")
    }

    if ($script:CheckFailed) {
        $script:Failures++
        Write-Host ("CHECK {0} — {1} — FAIL" -f $Number, $Name) -ForegroundColor Red
        foreach ($note in $script:CheckNotes) {
            Write-Host "    $note" -ForegroundColor Red
        }
    }
    else {
        Write-Host ("CHECK {0} — {1} — PASS" -f $Number, $Name) -ForegroundColor Green
    }
}

function New-TempSource {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][AllowEmptyString()][string]$Content
    )

    $path = Join-Path -Path $env:TEMP -ChildPath ('policy-suite-{0}-{1}.md' -f $PID, $Name)
    [System.IO.File]::WriteAllText($path, $Content, [System.Text.UTF8Encoding]::new($false))
    $script:TempFiles.Add($path)
    return $path
}

function Get-RepoSnapshot {
    param([Parameter(Mandatory)][string]$Root)

    $snapshot = [ordered]@{}
    $files = Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
        Where-Object { $_.FullName -notmatch '\\\.git\\' } |
        Sort-Object FullName

    foreach ($file in $files) {
        $relative = $file.FullName.Substring($Root.Length).TrimStart('\', '/')
        $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }

    return $snapshot
}

function Test-RuleShape {
    param([Parameter(Mandatory)][object]$Rule)

    $expected = @('Id', 'Kind', 'Scope', 'Source', 'Basis', 'Weight', 'Verb', 'Hash')
    $actual = @($Rule.PSObject.Properties.Name)

    Assert-That (($actual.Count -eq $expected.Count) -and (-not (Compare-Object $actual $expected))) `
        'rule has exactly the eight documented properties' ($actual -join ',')

    foreach ($name in $expected) {
        $value = $Rule.$name
        Assert-That ($value -is [string] -and -not [string]::IsNullOrWhiteSpace($value)) `
            "$name is a non-empty string" "$($Rule.Id): $name = '$value'"
    }

    Assert-That ($Rule.Hash -cmatch '^[0-9a-f]{64}$') 'Hash is 64 lowercase hex' "$($Rule.Id): $($Rule.Hash)"
    Assert-That ($Rule.Kind -in @('module', 'path', 'claim', 'verb', 'errorid', 'receipt', 'law')) 'Kind is legal' $Rule.Kind
    Assert-That ($Rule.Scope -in @('repo', 'module', 'session', 'target')) 'Scope is legal' $Rule.Scope
    Assert-That ($Rule.Weight -in @('halt', 'warn', 'log')) 'Weight is legal' $Rule.Weight
    Assert-That ($Rule.Verb -in @('import', 'write', 'claim', 'execute', 'publish', 'none')) 'Verb is legal' $Rule.Verb
    Assert-That ($Rule.Source -match ':\d+$') 'Source ends in a 1-based line number' $Rule.Source
}

$snapshotBefore = Get-RepoSnapshot -Root $repo
Write-Verbose "Snapshot: $($snapshotBefore.Count) file(s) under $repo"

Import-Module -Name $manifest -Force -ErrorAction Stop

# ------------------------------------------------------------------------ 1
Invoke-Check 1 'manifest loads and exports Get-PolicyRules' {
    $command = Get-Command -Name 'Get-PolicyRules' -ErrorAction SilentlyContinue
    Assert-That ($null -ne $command) 'Get-PolicyRules is available after import'

    $module = Get-Module -Name 'claude.build.policy'
    Assert-That ($null -ne $module) 'module claude.build.policy is loaded'
    Assert-That ($module.Version.ToString() -eq '0.2.0') 'ModuleVersion is 0.2.0' $module.Version
    Assert-That ((@($module.ExportedFunctions.Keys) -join ',') -eq 'Get-PolicyRules') `
        'Get-PolicyRules is the only exported function' (@($module.ExportedFunctions.Keys) -join ',')
    Assert-That ($module.PowerShellVersion.ToString() -eq '7.4') 'manifest PowerShellVersion is 7.4' $module.PowerShellVersion
}

# ------------------------------------------------------------------------ 2
Invoke-Check 2 'build.ps1 exits 0 and prints version and name' {
    $output = @(& pwsh -NoProfile -File $buildScript 2>&1 | ForEach-Object { $_.ToString() })
    $exit = $LASTEXITCODE
    $joined = $output -join "`n"

    Assert-That ($exit -eq 0) 'build.ps1 exit code is 0' "exit $exit"
    Assert-That ($joined -match '0\.2\.0') 'stdout contains 0.2.0' $joined
    Assert-That ($joined -match 'claude\.build\.policy') 'stdout contains claude.build.policy' $joined
}

# ------------------------------------------------------------------------ 3
Invoke-Check 3 'a missing path throws PolicyPathNotFound' {
    $missing = Join-Path -Path $env:TEMP -ChildPath ('policy-suite-{0}-does-not-exist' -f $PID)
    Assert-That (-not (Test-Path -LiteralPath $missing)) 'the missing path really is missing'

    $errorId = ''
    $threw = $false
    try {
        Get-PolicyRules -Path $missing | Out-Null
    }
    catch {
        $threw = $true
        $errorId = $_.FullyQualifiedErrorId
    }

    Assert-That $threw 'Get-PolicyRules threw'
    Assert-That ($errorId -like 'PolicyPathNotFound*') 'ErrorId is PolicyPathNotFound' $errorId
}

# ------------------------------------------------------------------------ 4
Invoke-Check 4 'this repo root yields well-formed rules' {
    $rules = @(Get-PolicyRules -Path $repo)
    Assert-That ($rules.Count -ge 1) 'at least one rule from the repo root' "$($rules.Count) rule(s)"

    foreach ($rule in $rules) {
        Test-RuleShape -Rule $rule
    }

    $ids = @($rules | ForEach-Object { $_.Id })
    Assert-That ($ids.Count -eq (@($ids | Sort-Object -Unique)).Count) 'Ids are unique within a call'

    $sources = @($rules | ForEach-Object { ($_.Source -split ':')[0] } | Sort-Object -Unique)
    foreach ($source in $sources) {
        Assert-That ($source -in @('AGENTS.md', 'docs/do-not.md', 'CLAUDE.md')) `
            'Source names one of the three walked files' $source
    }

    Write-Verbose "    repo root: $($rules.Count) rule(s) across $($sources.Count) file(s)"
}

# ------------------------------------------------------------------------ 5
Invoke-Check 5 'Hash is stable across two parses of the same file' {
    $target = Join-Path -Path $repo -ChildPath 'AGENTS.md'
    $first = @(Get-PolicyRules -Path $target)
    $second = @(Get-PolicyRules -Path $target)

    Assert-That ($first.Count -ge 1) 'AGENTS.md yields rules' "$($first.Count) rule(s)"
    Assert-That ($first.Count -eq $second.Count) 'both parses yield the same count' "$($first.Count) vs $($second.Count)"

    $firstById = @{}
    foreach ($rule in $first) { $firstById[$rule.Id] = $rule.Hash }

    foreach ($rule in $second) {
        Assert-That ($firstById.ContainsKey($rule.Id)) "Id $($rule.Id) present in both parses"
        if ($firstById.ContainsKey($rule.Id)) {
            Assert-That ($firstById[$rule.Id] -ceq $rule.Hash) "Hash for $($rule.Id) is identical" $rule.Hash
        }
    }
}

# ------------------------------------------------------------------------ 6
Invoke-Check 6 'ledger AGENTS.md yields an import or Ledger rule' {
    $target = Join-Path -Path $workspace -ChildPath 'claude.build.ledger' -AdditionalChildPath 'AGENTS.md'
    Assert-That (Test-Path -LiteralPath $target -PathType Leaf) 'sibling ledger AGENTS.md exists' $target
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return }

    $rules = @(Get-PolicyRules -Path $target)
    Assert-That ($rules.Count -ge 1) 'ledger AGENTS.md yields rules' "$($rules.Count) rule(s)"

    $matching = @($rules | Where-Object {
            $_.Kind -in @('module', 'law') -and
            (($_.Basis -match '(?i)import') -or ($_.Basis -match '(?i)ledger') -or
             ($_.Id -match '(?i)import') -or ($_.Id -match '(?i)ledger'))
        })

    Assert-That ($matching.Count -ge 1) 'at least one module or law rule mentions import or Ledger' "$($matching.Count) match(es)"
    Write-Verbose "    ledger AGENTS.md: $($rules.Count) rule(s), $($matching.Count) about import/Ledger"
}

# ------------------------------------------------------------------------ 7
Invoke-Check 7 'fuzzer docs/do-not.md yields at least one rule' {
    $target = Join-Path -Path $workspace -ChildPath 'claude.build.fuzzer' -AdditionalChildPath 'docs', 'do-not.md'
    Assert-That (Test-Path -LiteralPath $target -PathType Leaf) 'sibling fuzzer docs/do-not.md exists' $target
    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { return }

    $rules = @(Get-PolicyRules -Path $target)
    Assert-That ($rules.Count -ge 1) 'fuzzer do-not.md yields rules' "$($rules.Count) rule(s)"
    Write-Verbose "    fuzzer docs/do-not.md: $($rules.Count) rule(s)"
}

# ------------------------------------------------------------------------ 8
Invoke-Check 8 'a file with no law yields zero rules' {
    $plain = New-TempSource -Name 'plain' -Content "hello world`n"

    $rules = $null
    $threw = $false
    try {
        $rules = @(Get-PolicyRules -Path $plain)
    }
    catch {
        $threw = $true
        $script:CheckNotes.Add("threw: $($_.Exception.Message)")
    }

    Assert-That (-not $threw) 'parsing plain prose does not throw'
    Assert-That ($null -ne $rules -and $rules.Count -eq 0) 'zero rules emitted' "$(if ($null -eq $rules) { 'null' } else { $rules.Count })"

    $empty = New-TempSource -Name 'empty' -Content ''
    $emptyRules = @(Get-PolicyRules -Path $empty)
    Assert-That ($emptyRules.Count -eq 0) 'an empty file emits zero rules too' "$($emptyRules.Count)"
}

# ------------------------------------------------------------------------ 9
Invoke-Check 9 'a Do-not bullet yields a halt-weight law rule' {
    $lawFile = New-TempSource -Name 'law' -Content "- Do not import Ledger`n"
    $rules = @(Get-PolicyRules -Path $lawFile)

    Assert-That ($rules.Count -ge 1) 'the bullet yields rules' "$($rules.Count) rule(s)"

    $laws = @($rules | Where-Object { $_.Kind -eq 'law' })
    Assert-That ($laws.Count -ge 1) 'at least one Kind=law rule' "$($laws.Count) law rule(s)"

    foreach ($law in $laws) {
        Assert-That ($law.Weight -eq 'halt') 'the law rule has Weight=halt' $law.Weight
        Assert-That ($law.Verb -eq 'none') 'the law rule has Verb=none' $law.Verb
        Test-RuleShape -Rule $law
    }

    $imports = @($rules | Where-Object { $_.Kind -eq 'module' })
    Assert-That ($imports.Count -ge 1) 'the same line also yields the import rule' "$($imports.Count) module rule(s)"
}

# ----------------------------------------------------------------------- 10
Invoke-Check 10 'the suite wrote nothing under the repo and cleaned up $env:TEMP' {
    foreach ($path in $script:TempFiles) {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    foreach ($path in $script:TempFiles) {
        Assert-That (-not (Test-Path -LiteralPath $path)) 'temp file deleted' $path
    }

    $snapshotAfter = Get-RepoSnapshot -Root $repo
    Assert-That ($snapshotAfter.Count -eq $snapshotBefore.Count) `
        'the repo has the same file count' "$($snapshotBefore.Count) -> $($snapshotAfter.Count)"

    foreach ($relative in $snapshotBefore.Keys) {
        Assert-That ($snapshotAfter.Contains($relative)) 'file still present' $relative
        if ($snapshotAfter.Contains($relative)) {
            Assert-That ($snapshotAfter[$relative] -eq $snapshotBefore[$relative]) 'file unchanged' $relative
        }
    }

    foreach ($relative in $snapshotAfter.Keys) {
        Assert-That ($snapshotBefore.Contains($relative)) 'no new file under the repo' $relative
    }

    Assert-That (Test-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '.gitkeep')) `
        'tests/sandbox/.gitkeep survives'
}

Write-Host ''
if ($script:Failures -eq 0) {
    Write-Host 'ALL CHECKS PASSED' -ForegroundColor Green
    exit 0
}
Write-Host "$($script:Failures) CHECK(S) FAILED" -ForegroundColor Red
exit 1
