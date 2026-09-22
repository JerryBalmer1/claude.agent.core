#Requires -Version 7.4
<#
    The policy module's ten checks, ported from tests/sandbox/policy_suite.ps1.

    ONE It PER ORIGINAL CHECK, numbered to match, in the original order. Nothing merged, nothing
    dropped, nothing added. Ten checks in, ten tests out, so the Pester total moves by exactly the
    number the run order predicts and a difference is a defect rather than a rounding.

    The sandbox script stays in the tree at tests/sandbox/policy_suite.ps1 as provenance. It is
    NOT the oracle the run order expected it to be: checks 2, 6 and 7 reach for build.ps1,
    ../claude.build.ledger and ../claude.build.fuzzer, none of which exist here, so it cannot be
    run in substrate at all. FINDINGS.md F1 recorded that before the copy; F23 records what each
    of those three became. Three of them are fixture-backed here and say so in their names.

    Nothing in this file resolves a path outside modules/policy.
#>

BeforeAll {
    # tests -> modules/policy. The module under test is the whole subtree above this file.
    $script:ModuleRoot = Split-Path $PSScriptRoot -Parent
    $script:Manifest = Join-Path $script:ModuleRoot 'policy.psd1'
    $script:Fixtures = Join-Path $PSScriptRoot 'fixtures'
    $script:Sandbox = Join-Path $PSScriptRoot 'sandbox/policy_suite.ps1'
    $script:TempFiles = [System.Collections.Generic.List[string]]::new()

    # NOT $env:TEMP. That variable is Windows-only; on the ubuntu-latest runner it is unset, and
    # Join-Path then throws "Cannot bind argument to parameter 'Path' because it is null". The
    # sandbox script this file is ported from uses $env:TEMP throughout and was only ever run on
    # Windows, so the port inherited a Windows-only dependency that passes 72/72 locally and fails
    # on CI. GetTempPath() is correct on both. FINDINGS.md F26.
    $script:TempRoot = [System.IO.Path]::GetTempPath()

    function script:New-TempSource {
        <#  A policy source in the temp directory, registered for deletion by check 10. Outside the
            repo on purpose: check 10's whole claim is that parsing writes nothing under the module,
            and a fixture written inside it would falsify that by existing. #>
        param(
            [Parameter(Mandatory)][string]$Name,
            [Parameter(Mandatory)][AllowEmptyString()][string]$Content
        )
        $path = Join-Path -Path $script:TempRoot -ChildPath ('policy-pester-{0}-{1}.md' -f $PID, $Name)
        [System.IO.File]::WriteAllText($path, $Content, [System.Text.UTF8Encoding]::new($false))
        $script:TempFiles.Add($path)
        return $path
    }

    function script:Get-ModuleSnapshot {
        <#  Relative path -> SHA-256, for every file under the module. .git cannot appear under
            modules/policy, so there is nothing to exclude. #>
        param([Parameter(Mandatory)][string]$Root)
        $snapshot = [ordered]@{}
        foreach ($file in (Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
            $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        return $snapshot
    }

    function script:Assert-RuleShape {
        <#  The eight documented properties and the five closed vocabularies. Lifted assertion for
            assertion from the sandbox script's Test-RuleShape. #>
        param([Parameter(Mandatory)][object]$Rule)

        $expected = @('Id', 'Kind', 'Scope', 'Source', 'Basis', 'Weight', 'Verb', 'Hash')
        $actual = @($Rule.PSObject.Properties.Name)

        $actual.Count | Should -Be $expected.Count -Because "rule '$($Rule.Id)' must carry exactly the eight documented properties, got: $($actual -join ',')"
        (Compare-Object $actual $expected) | Should -BeNullOrEmpty -Because "rule '$($Rule.Id)' property names must be exactly: $($expected -join ',')"

        foreach ($name in $expected) {
            $value = $Rule.$name
            $value | Should -BeOfType ([string]) -Because "$($Rule.Id): $name must be a string"
            [string]::IsNullOrWhiteSpace($value) | Should -BeFalse -Because "$($Rule.Id): $name must be non-empty, got '$value'"
        }

        $Rule.Hash   | Should -MatchExactly '^[0-9a-f]{64}$' -Because "$($Rule.Id): Hash must be 64 lowercase hex"
        $Rule.Kind   | Should -BeIn @('module', 'path', 'claim', 'verb', 'errorid', 'receipt', 'law')
        $Rule.Scope  | Should -BeIn @('repo', 'module', 'session', 'target')
        $Rule.Weight | Should -BeIn @('halt', 'warn', 'log')
        $Rule.Verb   | Should -BeIn @('import', 'write', 'claim', 'execute', 'publish', 'none')
        $Rule.Source | Should -Match ':\d+$' -Because "$($Rule.Id): Source must end in a 1-based line number, got '$($Rule.Source)'"
    }

    # Taken before the first check runs, compared by check 10. The sandbox script snapshotted its
    # whole repository; here the module is a subtree of a repository whose other suites legitimately
    # rewrite files during the same Pester run, so the root is the module. FINDINGS.md F23.
    $script:SnapshotBefore = script:Get-ModuleSnapshot -Root $script:ModuleRoot

    Import-Module -Name $script:Manifest -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'policy' -Force -ErrorAction SilentlyContinue
}

Describe 'the policy module, ported from the sandbox suite' -Tag 'policy' {

    It 'check 1 -- the manifest loads and Get-PolicyRules is the only export' {
        Get-Command -Name 'Get-PolicyRules' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty

        $module = Get-Module -Name 'policy'
        $module | Should -Not -BeNullOrEmpty
        $module.Version.ToString() | Should -Be '0.2.0'
        (@($module.ExportedFunctions.Keys) -join ',') | Should -Be 'Get-PolicyRules'
        $module.PowerShellVersion.ToString() | Should -Be '7.4'
    }

    It 'check 2 (fixture) -- a child process reads the manifest and reports the build identity' {
        # Original: & pwsh -NoProfile -File <repo>/build.ps1. Substrate has no build.ps1; the
        # fixture is that script's contract against the copied manifest. FINDINGS.md F23.
        $fixture = Join-Path $script:Fixtures 'build/build.ps1'
        $fixture | Should -Exist

        $PSNativeCommandUseErrorActionPreference = $false
        $output = @(& pwsh -NoProfile -File $fixture 2>&1 | ForEach-Object { $_.ToString() })
        $exit = $LASTEXITCODE
        $joined = $output -join "`n"
        if ($exit -ne 0) { Write-Host $joined }

        $exit | Should -Be 0
        $joined | Should -Match '0\.2\.0'
        $joined | Should -Match '(?m)^\[build\] name policy$'
    }

    It 'check 3 -- a missing path throws PolicyPathNotFound' {
        $missing = Join-Path -Path $script:TempRoot -ChildPath ('policy-pester-{0}-does-not-exist' -f $PID)
        (Test-Path -LiteralPath $missing) | Should -BeFalse

        $errorId = ''
        $threw = $false
        try { Get-PolicyRules -Path $missing | Out-Null }
        catch { $threw = $true; $errorId = $_.FullyQualifiedErrorId }

        $threw | Should -BeTrue
        $errorId | Should -BeLike 'PolicyPathNotFound*'
    }

    It 'check 4 -- the module root walk yields well-formed rules' {
        # Original walked the policy repo root. Here the module IS the thing that was copied, so
        # its root is the walk target; substrate's own root is not the module's law. FINDINGS.md F23.
        $rules = @(Get-PolicyRules -Path $script:ModuleRoot)
        $rules.Count | Should -BeGreaterThan 0

        foreach ($rule in $rules) { script:Assert-RuleShape -Rule $rule }

        $ids = @($rules | ForEach-Object { $_.Id })
        $ids.Count | Should -Be (@($ids | Sort-Object -Unique)).Count -Because 'Ids are deduplicated within a call'

        foreach ($source in @($rules | ForEach-Object { ($_.Source -split ':')[0] } | Sort-Object -Unique)) {
            $source | Should -BeIn @('AGENTS.md', 'docs/do-not.md', 'CLAUDE.md') -Because 'the walk opens exactly those three names'
        }
    }

    It 'check 5 -- Hash is stable across two parses of the same file' {
        $target = Join-Path $script:ModuleRoot 'docs/do-not.md'
        $first = @(Get-PolicyRules -Path $target)
        $second = @(Get-PolicyRules -Path $target)

        $first.Count | Should -BeGreaterThan 0
        $second.Count | Should -Be $first.Count

        $firstById = @{}
        foreach ($rule in $first) { $firstById[$rule.Id] = $rule.Hash }

        foreach ($rule in $second) {
            $firstById.ContainsKey($rule.Id) | Should -BeTrue -Because "Id '$($rule.Id)' must appear in both parses"
            $firstById[$rule.Id] | Should -BeExactly $rule.Hash -Because "Hash for '$($rule.Id)' must not move between parses"
        }
    }

    It 'check 6 (fixture) -- an AGENTS.md-shaped source yields an import or Ledger rule' {
        # Original: ../claude.build.ledger/AGENTS.md. Out of reach and out of scope. FINDINGS.md F23.
        $target = Join-Path $script:Fixtures 'sibling-agents.md'
        $target | Should -Exist

        $rules = @(Get-PolicyRules -Path $target)
        $rules.Count | Should -BeGreaterThan 0

        $matching = @($rules | Where-Object {
                $_.Kind -in @('module', 'law') -and
                (($_.Basis -match '(?i)import') -or ($_.Basis -match '(?i)ledger') -or
                 ($_.Id -match '(?i)import') -or ($_.Id -match '(?i)ledger'))
            })
        $matching.Count | Should -BeGreaterThan 0 -Because 'at least one module or law rule must mention import or Ledger'

        foreach ($rule in $matching) { script:Assert-RuleShape -Rule $rule }
    }

    It 'check 7 (fixture) -- a do-not.md-shaped source yields at least one rule' {
        # Original: ../claude.build.fuzzer/docs/do-not.md. Out of reach and out of scope. FINDINGS.md F23.
        $target = Join-Path $script:Fixtures 'sibling-do-not.md'
        $target | Should -Exist

        $rules = @(Get-PolicyRules -Path $target)
        $rules.Count | Should -BeGreaterThan 0

        foreach ($rule in $rules) { script:Assert-RuleShape -Rule $rule }
    }

    It 'check 8 -- a file with no law yields zero rules' {
        $plain = script:New-TempSource -Name 'plain' -Content "hello world`n"

        # Deliberately not `{ ... } | Should -Not -Throw`: the result of this call is an EMPTY
        # collection, and the natural-looking `$rules | Should -Not -BeNullOrEmpty` guard against an
        # unassigned variable asserts the opposite of the contract. Assigned-and-empty and
        # never-assigned are told apart by the $null test, exactly as the sandbox script does it.
        $rules = $null
        $threw = $false
        try { $rules = @(Get-PolicyRules -Path $plain) }
        catch { $threw = $true; Write-Host "threw: $($_.Exception.Message)" }

        $threw | Should -BeFalse -Because 'parsing plain prose does not throw'
        ($null -ne $rules) | Should -BeTrue -Because 'the call returned and the variable was assigned'
        $rules.Count | Should -Be 0

        $empty = script:New-TempSource -Name 'empty' -Content ''
        @(Get-PolicyRules -Path $empty).Count | Should -Be 0 -Because 'an empty file emits nothing and does not throw'
    }

    It 'check 9 -- a Do-not bullet yields a halt-weight law rule' {
        $lawFile = script:New-TempSource -Name 'law' -Content "- Do not import Ledger`n"
        $rules = @(Get-PolicyRules -Path $lawFile)
        $rules.Count | Should -BeGreaterThan 0

        $laws = @($rules | Where-Object { $_.Kind -eq 'law' })
        $laws.Count | Should -BeGreaterThan 0

        foreach ($law in $laws) {
            $law.Weight | Should -Be 'halt'
            $law.Verb | Should -Be 'none'
            script:Assert-RuleShape -Rule $law
        }

        @($rules | Where-Object { $_.Kind -eq 'module' }).Count |
            Should -BeGreaterThan 0 -Because 'the same line also yields the import rule'
    }

    It 'check 10 -- the port wrote nothing under modules/policy and cleaned up the temp directory' {
        foreach ($path in $script:TempFiles) {
            if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
        }
        foreach ($path in $script:TempFiles) {
            (Test-Path -LiteralPath $path) | Should -BeFalse -Because "temp source '$path' must be gone"
        }
        $script:TempFiles.Count | Should -Be 3 -Because 'checks 8 and 9 create three temp sources between them; a zero here would make this check vacuous'

        $after = script:Get-ModuleSnapshot -Root $script:ModuleRoot
        $after.Count | Should -Be $script:SnapshotBefore.Count -Because "file count under the module must not move ($($script:SnapshotBefore.Count) before)"

        foreach ($relative in $script:SnapshotBefore.Keys) {
            $after.Contains($relative) | Should -BeTrue -Because "'$relative' must still be present"
            $after[$relative] | Should -Be $script:SnapshotBefore[$relative] -Because "'$relative' must be byte-identical"
        }
        foreach ($relative in $after.Keys) {
            $script:SnapshotBefore.Contains($relative) | Should -BeTrue -Because "'$relative' is new under the module; parsing writes nothing"
        }

        # Original asserted tests/sandbox/.gitkeep survived. The copy brought no .gitkeep into
        # modules/policy/tests/sandbox; the provenance script itself is the file that must survive
        # untouched, so it is the one asserted. FINDINGS.md F23.
        $script:Sandbox | Should -Exist
        (Get-FileHash -LiteralPath $script:Sandbox -Algorithm SHA256).Hash |
            Should -Be $script:SnapshotBefore['tests/sandbox/policy_suite.ps1'] -Because 'the sandbox oracle is provenance and is never rewritten by its own port'
    }
}
