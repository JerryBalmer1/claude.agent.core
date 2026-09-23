#Requires -Version 7.4
<#
    Assertions about the shape of the repository. These exist so the `pester` check is never an
    empty green: if this file were deleted the suite would still report zero failures, which is
    why Invoke-Tests.ps1 also fails on a zero total.

    Several of these are the wall from AGENTS.md, expressed as a test. A wall nobody measures is
    a suggestion.
#>

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:ConfigPath = Join-Path $script:RepoRoot 'config/repo.json'
    $script:SchemaPath = Join-Path $script:RepoRoot 'schemas/repo.schema.json'
    $script:Config = Get-Content -LiteralPath $script:ConfigPath -Raw | ConvertFrom-Json -Depth 20
}

Describe 'config is the source of truth' {

    It 'config/repo.json validates against its own draft-07 schema' {
        $json = Get-Content -LiteralPath $script:ConfigPath -Raw
        Test-Json -Json $json -SchemaFile $script:SchemaPath | Should -BeTrue
    }

    It 'the schema actually rejects a bad review.mode' {
        # Guards the guard. A schema that accepts everything validates nothing, and this suite
        # would go green on a config that says review.mode is "vibes".
        #
        # The plant matches the mode VALUE, whatever it currently is, rather than the literal
        # "auto" it was written against: Phase 6.4 flipped the mode to "human" and the old
        # -replace silently matched nothing, leaving $bad identical to the real config, which
        # validates. The test went red -- correctly, but for the wrong reason, and a falsification
        # whose defect is keyed to the value under test stops being a falsification the first
        # time that value moves. FINDINGS F64.
        $good = Get-Content -LiteralPath $script:ConfigPath -Raw
        $bad  = $good -replace '"mode":\s*"[^"]*"', '"mode": "vibes"'
        $bad | Should -Not -Be $good -Because 'the planted defect must actually change the config, or this asserts nothing'
        { Test-Json -Json $bad -SchemaFile $script:SchemaPath -ErrorAction Stop } | Should -Throw
    }

    It 'the merge strategy is a merge commit, never a squash or a rebase' {
        $script:Config.merge.strategy | Should -Be 'merge'
    }

    It 'the flow has no row that reaches main without passing through develop' {
        $intoMain = @($script:Config.flow | Where-Object { $_[1] -eq $script:Config.branches.main })
        $intoMain.Count | Should -Be 1
        $intoMain[0][0] | Should -Be $script:Config.branches.develop
    }

    It 'every required check name is a kebab-case slug' {
        foreach ($c in $script:Config.required_checks) {
            $c | Should -MatchExactly '^[a-z0-9]+(-[a-z0-9]+)*$'
        }
    }
}

Describe 'the skeleton exists' {

    It 'has exactly one README.md at the root' {
        @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter 'README.md' -File).Count | Should -Be 1
    }

    It 'CODEOWNERS is present and names every owner from config' {
        $owners = Join-Path $script:RepoRoot 'CODEOWNERS'
        $owners | Should -Exist
        $text = Get-Content -LiteralPath $owners -Raw
        foreach ($o in $script:Config.owners) { $text | Should -BeLike "*$o*" }
    }

    It 'AGENTS.md is present' {
        (Join-Path $script:RepoRoot 'AGENTS.md') | Should -Exist
    }

    It '.gitattributes forces lf so byte comparisons mean the same thing on every runner' {
        $ga = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.gitattributes') -Raw
        $ga | Should -Match 'text=auto eol=lf'
        $ga | Should -Match '\*\.ps1 text eol=lf'
    }
}

Describe 'the wall holds' {

    It 'src/ contains nothing but .gitkeep' {
        $found = @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'src') -Recurse -Force -File |
                   ForEach-Object { $_.Name })
        $found | Should -Be @('.gitkeep') -Because 'substrate is a skeleton; module code needs a run order that says so'
    }

    It 'modules/ holds only the modules a run order named' {
        # This test used to demand that modules/ contain nothing but .gitkeep. The wall MOVED, it
        # did not come down: docs/plans/2026-09-22-substrate-cutover/RUN-ORDER.md authorises
        # modules/ledger, modules/policy and modules/plans, and nothing else authorises anything.
        #
        # So the assertion is now the narrower one that run order's Phase 5.1 spells out - module
        # code outside a named module's directory is still red - and it still fails on the two
        # things worth catching: a modules/<unnamed>/ subtree, and a loose file at the top of
        # modules/ that no module owns.
        $modulesRoot = Join-Path $script:RepoRoot 'modules'
        $named = @('ledger', 'policy', 'plans')

        $stray = @(Get-ChildItem -LiteralPath $modulesRoot -Recurse -Force -File |
                   ForEach-Object { [System.IO.Path]::GetRelativePath($modulesRoot, $_.FullName).Replace('\', '/') } |
                   Where-Object { $_ -ne '.gitkeep' } |
                   Where-Object {
                       $parts = $_ -split '/'
                       ($parts.Count -lt 2) -or ($named -notcontains $parts[0])
                   })

        $stray | Should -BeNullOrEmpty -Because "modules/ is authorised for $($named -join ', ') only, by docs/plans/2026-09-22-substrate-cutover/RUN-ORDER.md"
    }

    It 'there is no vendor/ directory' {
        (Join-Path $script:RepoRoot 'vendor') | Should -Not -Exist
    }

    It 'core is never a container' {
        foreach ($f in 'Dockerfile', 'Containerfile', 'docker-compose.yml', '.dockerignore') {
            (Join-Path $script:RepoRoot $f) | Should -Not -Exist -Because 'image builder builds containers; substrate is consumed by it'
        }
    }
}

Describe 'the forensic chain' {

    It 'scripts/forensic.ps1 is present and notes where it was copied from' {
        $f = Join-Path $script:RepoRoot 'scripts/forensic.ps1'
        $f | Should -Exist
        $head = (Get-Content -LiteralPath $f -TotalCount 20) -join "`n"
        $head | Should -Match 'claude\.pwsh\.image\.builder'
        $head | Should -Match '[0-9a-f]{40}' -Because 'the origin commit must be recorded, not just the repo name'
    }

    It 'the chain verifies' {
        $PSNativeCommandUseErrorActionPreference = $false
        $out = & pwsh -NoProfile -File (Join-Path $script:RepoRoot 'scripts/forensic.ps1') -Verify 2>&1
        if ($LASTEXITCODE -ne 0) { Write-Host ($out -join "`n") }
        $LASTEXITCODE | Should -Be 0
    }

    It 'the chain is not empty' {
        # Found by falsifying forensic-verify: the script exits 0 when the chain file does not
        # exist, because an absent chain has no broken link in it. That makes "forensic-verify
        # is green" true of a repository where someone deleted .continuity/forensic.jsonl
        # outright - the loudest possible tampering producing the quietest possible signal.
        # The verify script is a verbatim copy and is not modified here; the emptiness is
        # asserted against from this side instead.
        $chain = Join-Path $script:RepoRoot '.continuity/forensic.jsonl'
        $chain | Should -Exist -Because 'an absent chain verifies green; that is the hole this closes'
        $records = @([System.IO.File]::ReadAllLines($chain) | Where-Object { $_.Trim() -ne '' })
        $records.Count | Should -BeGreaterThan 0
    }
}
