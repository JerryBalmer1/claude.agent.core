#Requires -Version 7.4
<#
    The runtime declaration, asserted from the other side.

    scripts/ci/Test-Runtimes.ps1 enforces the rule in CI. These tests enforce the things a CI
    run on a clean tree cannot: that the check would actually go red if the rule were broken,
    and that the two places the PowerShell floor is now written stay equal.

    The falsification here is a UNIT proof, for the reason the Phase 0 closeout recorded as
    F-C2: driving the real script over a fixture tree is repeatable on every CI run forever,
    where planting a .py in the working tree and looking at it is true once. The physical
    proof was also performed and is in TRANSCRIPT.log; this is the one that still fails if
    someone deletes the prefix check next month.
#>

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:ConfigPath = Join-Path $script:RepoRoot 'config/repo.json'
    $script:SchemaPath = Join-Path $script:RepoRoot 'schemas/repo.schema.json'
    $script:Config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json -Depth 20
    $script:Checker = Join-Path $script:RepoRoot 'scripts/ci/Test-Runtimes.ps1'

    function script:Invoke-Checker {
        <#  Run the real check script against a throwaway repository and return its exit code.
            The script reads `git ls-files`, so the fixture has to be a real git repo - a
            directory of files would report zero tracked .py and pass vacuously. #>
        param(
            [Parameter(Mandatory)][string]$ConfigJson,
            [Parameter()][string[]]$Files = @()
        )
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ('runtimes-' + [Guid]::NewGuid().ToString('N').Substring(0, 8))
        try {
            $null = New-Item -ItemType Directory -Path (Join-Path $work 'config') -Force
            $null = New-Item -ItemType Directory -Path (Join-Path $work 'scripts/ci') -Force
            [System.IO.File]::WriteAllText((Join-Path $work 'config/repo.json'), $ConfigJson)
            Copy-Item -LiteralPath $script:Checker -Destination (Join-Path $work 'scripts/ci/Test-Runtimes.ps1')

            foreach ($f in $Files) {
                $full = Join-Path $work $f
                $dir = Split-Path $full -Parent
                if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
                [System.IO.File]::WriteAllText($full, "# fixture`n")
            }

            $PSNativeCommandUseErrorActionPreference = $false
            & git -C $work init --quiet 2>&1 | Out-Null
            & git -C $work add --all 2>&1 | Out-Null
            $out = & pwsh -NoProfile -File (Join-Path $work 'scripts/ci/Test-Runtimes.ps1') 2>&1
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($out | Out-String) }
        }
        finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'the runtime declaration is in the config' {

    It 'declares a python version and at least one allowed prefix' {
        $script:Config.runtimes.python.version | Should -MatchExactly '^\d+\.\d+$'
        @($script:Config.runtimes.python.allowed_under).Count | Should -BeGreaterThan 0
    }

    It 'every allowed prefix ends in a slash' {
        # Without the slash, "modules/ledger" would also permit "modules/ledgerplayground/x.py".
        foreach ($p in $script:Config.runtimes.python.allowed_under) {
            $p | Should -MatchExactly '/$'
        }
    }

    It 'states the same PowerShell floor in both places' {
        $script:Config.runtimes.powershell | Should -BeExactly $script:Config.scripts.requires_version
    }

    It 'the schema rejects a config with no runtimes block at all' {
        $bad = (Get-Content -LiteralPath $script:ConfigPath -Raw) -replace '(?s)\s*"runtimes":\s*\{.*?\n  \},', ''
        $bad | Should -Not -Match '"runtimes"' -Because 'the fixture must really have lost the block, or this proves nothing'
        { Test-Json -Json $bad -SchemaFile $script:SchemaPath -ErrorAction Stop } | Should -Throw
    }

    It 'the schema rejects an allowed prefix with no trailing slash' {
        $bad = (Get-Content -LiteralPath $script:ConfigPath -Raw) -replace '"modules/ledger/python/"', '"modules/ledger/python"'
        { Test-Json -Json $bad -SchemaFile $script:SchemaPath -ErrorAction Stop } | Should -Throw
    }
}

Describe 'the check enforces it' {

    BeforeAll {
        $script:GoodConfig = Get-Content -LiteralPath $script:ConfigPath -Raw
    }

    It 'passes on a tree with no python at all' {
        $r = script:Invoke-Checker -ConfigJson $script:GoodConfig
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'no tracked \.py files'
    }

    It 'passes on a .py inside an allowed prefix' {
        $r = script:Invoke-Checker -ConfigJson $script:GoodConfig -Files @('modules/ledger/python/cli.py')
        $r.ExitCode | Should -Be 0
        $r.Output | Should -Match 'OK\s+modules/ledger/python/cli\.py'
    }

    It 'FAILS on a .py outside every allowed prefix' {
        # The planted defect. If this ever goes green the check has stopped checking, and the
        # run order's "Python stays in one place" is a sentence in a document and nothing else.
        $r = script:Invoke-Checker -ConfigJson $script:GoodConfig -Files @('scripts/sneaky.py')
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'DENIED scripts/sneaky\.py'
    }

    It 'is not fooled by a prefix that is only a string prefix of a sibling directory' {
        $r = script:Invoke-Checker -ConfigJson $script:GoodConfig -Files @('modules/ledger/pythonic/x.py')
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'DENIED modules/ledger/pythonic/x\.py'
    }

    It 'FAILS when the two PowerShell floors disagree' {
        $bad = $script:GoodConfig -replace '"powershell": "7.4"', '"powershell": "7.2"'
        $bad | Should -Match '"powershell": "7\.2"'
        $r = script:Invoke-Checker -ConfigJson $bad
        $r.ExitCode | Should -Be 1
        $r.Output | Should -Match 'does not equal scripts\.requires_version'
    }
}

Describe 'the check is wired into a required job, without inventing a new check name' {

    BeforeAll {
        $script:Ci = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot '.github/workflows/ci.yml'))
    }

    It 'ci.yml runs Test-Runtimes.ps1' {
        $script:Ci | Should -Match 'Test-Runtimes\.ps1'
    }

    It 'runs it inside the existing requires-header job, not a new one' {
        # Everything from `requires-header:` to the next job key at two spaces of indent.
        $script:Ci | Should -Match '(?s)\n  requires-header:.*?Test-Runtimes\.ps1.*?\n\n  \S'
    }

    It 'has not added a seventh required check' {
        @($script:Config.required_checks).Count | Should -Be 6
        $script:Config.required_checks | Should -Contain 'requires-header'
        $script:Config.required_checks | Should -Not -Contain 'runtimes'
    }
}

Describe 'the policy document states the permission' {

    BeforeAll {
        $script:Policy = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'docs/POLICY.md'))
    }

    It 'has a Runtimes section' {
        $script:Policy | Should -Match '(?m)^## Runtimes\s*$'
    }

    It 'names python and every allowed prefix' {
        # Closeout F-C4 recorded the opposite case: a rule enforced by a guard and absent from
        # the generated policy. A permission nobody wrote down is indistinguishable from one
        # nobody granted.
        $script:Policy | Should -Match ('Python \*\*{0}\+\*\*' -f [regex]::Escape($script:Config.runtimes.python.version))
        foreach ($p in $script:Config.runtimes.python.allowed_under) {
            $script:Policy | Should -BeLike "*$p*"
        }
    }
}
