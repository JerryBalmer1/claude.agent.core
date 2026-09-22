#Requires -Version 7.4
<#
    The drift test. docs/POLICY.md and .github/PULL_REQUEST_TEMPLATE.md are rendered from
    config/repo.json; this is what stops someone editing the rendered prose and leaving the
    config saying something else. It is the same switch CI runs as "generated-match-config".

    The generator is invoked as a child process on purpose: it ends in `exit 0` / `exit 1`, and
    dot-sourcing or `&`-calling it would take the Pester session down with it.
#>

BeforeAll {
    $script:RepoRoot  = Split-Path $PSScriptRoot -Parent
    $script:Generator = Join-Path $script:RepoRoot 'scripts/Generate-Policy.ps1'
    $script:Generated = @(
        Join-Path $script:RepoRoot 'docs/POLICY.md'
        Join-Path $script:RepoRoot '.github/PULL_REQUEST_TEMPLATE.md'
    )

    function Invoke-GeneratorCheck {
        # $LASTEXITCODE is the assertion target, so native errors must not be terminating here.
        $PSNativeCommandUseErrorActionPreference = $false
        $output = & pwsh -NoProfile -File $script:Generator -Check 2>&1
        return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
    }
}

Describe 'generated files' {

    It 'the generator exists and declares the version floor' {
        $script:Generator | Should -Exist
        $first = (Get-Content -LiteralPath $script:Generator -TotalCount 1)
        $first | Should -Match '^#Requires -Version 7\.4\s*$'
    }

    It 'every generated file exists' {
        foreach ($g in $script:Generated) { $g | Should -Exist }
    }

    It 'every generated file says it is generated' {
        foreach ($g in $script:Generated) {
            $head = (Get-Content -LiteralPath $g -TotalCount 6) -join "`n"
            $head | Should -Match 'GENERATED FILE - DO NOT EDIT BY HAND'
            $head | Should -Match 'scripts/Generate-Policy\.ps1'
        }
    }

    It 'Generate-Policy.ps1 -Check exits 0 against the committed files' {
        $r = Invoke-GeneratorCheck
        if ($r.ExitCode -ne 0) { Write-Host $r.Output }
        $r.ExitCode | Should -Be 0 -Because 'the committed files must be byte-identical to what config/repo.json renders'
    }

    It 'the check is falsifiable: a one-word edit makes it exit 1' {
        # The point of this test is that the green above is not vacuous. Mutate a committed
        # generated file, confirm the guard goes red, and restore the exact bytes.
        $target   = Join-Path $script:RepoRoot 'docs/POLICY.md'
        $original = [System.IO.File]::ReadAllBytes($target)
        try {
            $text    = [System.Text.Encoding]::UTF8.GetString($original)
            $mutated = $text -replace 'Merge commits only', 'Squash commits only'
            $mutated | Should -Not -Be $text -Because 'the mutation must actually change something'
            [System.IO.File]::WriteAllText($target, $mutated, [System.Text.UTF8Encoding]::new($false))

            $red = Invoke-GeneratorCheck
            $red.ExitCode | Should -Be 1 -Because 'an edited generated file is drift'
            $red.Output   | Should -Match 'DRIFT'
        }
        finally {
            [System.IO.File]::WriteAllBytes($target, $original)
        }

        $green = Invoke-GeneratorCheck
        $green.ExitCode | Should -Be 0 -Because 'restoring the original bytes must restore the green'
    }
}
