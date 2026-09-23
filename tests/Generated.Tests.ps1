#Requires -Version 7.4
<#
    The drift test. docs/POLICY.md and .github/PULL_REQUEST_TEMPLATE.md are rendered from
    config/repo.json; this is what stops someone editing the rendered prose and leaving the
    config saying something else. It is the same switch CI runs as "generated-match-config".

    The generator is invoked as a child process on purpose: it ends in `exit 0` / `exit 1`, and
    dot-sourcing or `&`-calling it would take the Pester session down with it.
#>

BeforeDiscovery {
    # THE LIST LIVES HERE AND NOWHERE ELSE, and it has to be a discovery-time variable because
    # every test below is a -ForEach case over it and -ForEach is expanded during discovery. The
    # first version of this put it in BeforeAll, which runs later: the list was $null when Pester
    # expanded -ForEach, so the per-file cases silently became zero cases and the suite total did
    # not move. Measured, not reasoned about -- 176 before and 176 after was the tell.
    #
    # Repo-relative, so each case can name the file it is about. assets/header.svg is registered
    # because the drift check renders it whenever config/repo.json carries a header block, and a
    # generated file nothing asserts is a generated file that can be hand-edited.
    $script:GeneratedRelative = @(
        'docs/POLICY.md'
        '.github/PULL_REQUEST_TEMPLATE.md'
        'assets/header.svg'
    )
}

BeforeAll {
    $script:RepoRoot  = Split-Path $PSScriptRoot -Parent
    $script:Generator = Join-Path $script:RepoRoot 'scripts/Generate-Policy.ps1'

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

    It 'the generated file <_> exists' -ForEach $script:GeneratedRelative {
        (Join-Path $script:RepoRoot $_) | Should -Exist
    }

    It '<_> says it is generated' -ForEach $script:GeneratedRelative {
        # Six lines, because assets/header.svg has to spend its first line on the XML declaration
        # before it can carry the comment.
        $head = (Get-Content -LiteralPath (Join-Path $script:RepoRoot $_) -TotalCount 6) -join "`n"
        $head | Should -Match 'GENERATED FILE - DO NOT EDIT BY HAND'
        $head | Should -Match 'scripts/Generate-Policy\.ps1'
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

    It 'the check is falsifiable on <_>: one changed byte makes it exit 1' -ForEach $script:GeneratedRelative {
        # The one-word control above proves a MEANINGFUL edit is caught, and only in the policy
        # document. This proves the weakest possible edit is caught, in every registered file --
        # including assets/header.svg, where there is no sentence to reword and a single byte is
        # the whole of what a hand-edit might look like. The guard is a sha256 comparison, so
        # which byte moves does not matter; that is the claim being tested.
        $target   = Join-Path $script:RepoRoot $_
        $original = [System.IO.File]::ReadAllBytes($target)
        $original.Length | Should -BeGreaterThan 0 -Because 'a zero-length file would make this vacuous'
        try {
            $mutated = [byte[]]::new($original.Length)
            [System.Array]::Copy($original, $mutated, $original.Length)
            $at = [int]($original.Length / 2)
            $mutated[$at] = if ($original[$at] -eq 0x41) { 0x42 } else { 0x41 }
            [System.IO.File]::WriteAllBytes($target, $mutated)

            $red = Invoke-GeneratorCheck
            $red.ExitCode | Should -Be 1 -Because 'one byte of drift is drift'
            $red.Output   | Should -Match 'DRIFT'
        }
        finally {
            [System.IO.File]::WriteAllBytes($target, $original)
        }

        (Invoke-GeneratorCheck).ExitCode | Should -Be 0 -Because 'restoring the exact bytes must restore the green'
    }

    It 'the banner is a self-contained SVG: no script, no style, no external reference' {
        # An SVG referenced from Markdown is loaded as an IMAGE, so a browser refuses script and
        # external resources anyway -- but a sanitiser between here and the reader may also strip
        # <style>, which is why the animation is SMIL. This asserts the file stays that way, so
        # the reasoning in New-HeaderSvg cannot quietly stop being true.
        $svg = Join-Path $script:RepoRoot 'assets/header.svg'
        $xml = [xml][System.IO.File]::ReadAllText($svg)
        foreach ($name in 'script', 'style', 'image', 'foreignObject') {
            @($xml.DocumentElement.SelectNodes("//*[local-name()='$name']")).Count |
                Should -Be 0 -Because "<$name> has no business in a committed banner"
        }
        @($xml.DocumentElement.SelectNodes("//*[local-name()='animate']")).Count |
            Should -BeGreaterThan 0 -Because 'the animation is declarative and must be present to run'
        [System.IO.File]::ReadAllText($svg) |
            Should -Not -Match 'https?://(?!www\.w3\.org)' -Because 'the only URL may be the SVG namespace'
    }
}
