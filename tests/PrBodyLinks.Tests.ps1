#Requires -Version 7.4
<#
    scripts/ci/Test-PrBodyLinks.ps1 -- the check that a path named in a pull request body is a
    sha-pinned permalink and not a sentence that will point somewhere else next month.

    The script is invoked as a CHILD PROCESS, the same way tests/Generated.Tests.ps1 invokes the
    generator, and for the same reason: it ends in `exit 0` / `exit 1`, and dot-sourcing it would
    take the Pester session down with it. $LASTEXITCODE is the assertion target throughout.

    The body is handed over in $env:PR_BODY rather than as an argument, because that is the path
    the workflow uses and a test that exercised a different path would be testing something else.
    One It covers -Body as well, so the local-run parameter is not left unmeasured.
#>

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:Check    = Join-Path $script:RepoRoot 'scripts/ci/Test-PrBodyLinks.ps1'

    # A syntactically valid 40-hex sha that is not a commit in this repository. The check asserts
    # the SHAPE of the pin, not that the object exists, so a fixture sha is the honest fixture:
    # using a real sha would make these tests depend on history they do not care about.
    $script:Sha  = '0123456789abcdef0123456789abcdef01234567'
    $script:Blob = "https://github.com/JerryBalmer1/claude.agent.core/blob/$script:Sha"
    $script:Tree = "https://github.com/JerryBalmer1/claude.agent.core/tree/$script:Sha"

    function Invoke-Check {
        param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Body)
        $previous = $env:PR_BODY
        $env:PR_BODY = $Body
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $output = & pwsh -NoProfile -File $script:Check 2>&1
            return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join "`n") }
        }
        finally { $env:PR_BODY = $previous }
    }

    # The body every negative case is a mutation of. Two tokens, one bare filename and one with a
    # line range, so both halves of the rule are exercised by the green as well as by the reds.
    $script:GoodBody = @"
The wording lives in [``README.md``]($script:Blob/README.md), and the reason a new check is a
step rather than a job is [``scripts/ci/Test-Runtimes.ps1:12-17``]($script:Blob/scripts/ci/Test-Runtimes.ps1#L12-L17).
"@
}

Describe 'pr-body-links' {

    It 'a body whose every path is a sha-pinned permalink passes' {
        $r = Invoke-Check -Body $script:GoodBody
        if ($r.ExitCode -ne 0) { Write-Host $r.Output }
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'PASS -- 2 path token\(s\) checked'
    }

    It 'a bare path fails' {
        $r = Invoke-Check -Body 'The check lives in scripts/ci/Test-Runtimes.ps1 and nobody linked it.'
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'bare path'
    }

    It 'a link on a branch name instead of a sha fails' {
        # The whole point of the check. develop moves; a 40-hex sha does not.
        $url = 'https://github.com/JerryBalmer1/claude.agent.core/blob/develop/README.md'
        $r = Invoke-Check -Body "[``README.md``]($url)"
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match "ref 'develop' is not a 40-hex commit sha"
    }

    It 'a path inside a fenced block passes, because pasted evidence is not a citation' {
        $body = @"
What the diff said:

``````
 M scripts/ci/Test-Runtimes.ps1
 M README.md
``````
"@
        $r = Invoke-Check -Body $body
        if ($r.ExitCode -ne 0) { Write-Host $r.Output }
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'PASS -- 0 path token\(s\) checked'
    }

    It 'inline backticks are NOT exempt, so the backticks go inside the link' {
        $r = Invoke-Check -Body 'The floor is stated in `config/repo.json` and nowhere else.'
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'bare path'
    }

    It 'a line suffix that does not match the fragment fails' {
        $r = Invoke-Check -Body "[``README.md:41``]($script:Blob/README.md#L99)"
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'text says :41 but the link has #L99, expected #L41'
    }

    It 'a link to a different path than the text names fails' {
        $r = Invoke-Check -Body "[``README.md``]($script:Blob/AGENTS.md)"
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'link points at AGENTS\.md, a different path'
    }

    It 'a directory reference is satisfied by a tree link, not a blob one' {
        # Without this the rule would be unsatisfiable for a directory: there is no blob URL for
        # one, and a check nobody can satisfy is a check that gets switched off.
        $ok = Invoke-Check -Body "[``modules/ledger/``]($script:Tree/modules/ledger)"
        if ($ok.ExitCode -ne 0) { Write-Host $ok.Output }
        $ok.ExitCode | Should -Be 0

        $bad = Invoke-Check -Body "[``modules/ledger/``]($script:Blob/modules/ledger)"
        $bad.ExitCode | Should -Be 1
        $bad.Output   | Should -Match 'needs /tree/, not /blob/'
    }

    It 'a bare URL is not a path token, because a permalink is already pinned' {
        $r = Invoke-Check -Body "See $script:Blob/README.md for the exact wording."
        if ($r.ExitCode -ne 0) { Write-Host $r.Output }
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'PASS -- 0 path token\(s\) checked'
    }

    It 'an HTML comment body is exempt, because nothing inside one is rendered' {
        # Measured, not predicted: the first run of this check against a freshly generated
        # template went red on config/repo.json and scripts/Generate-Policy.ps1 inside the
        # template's own GENERATED FILE header. Invisible text cannot be a citation, so that was
        # the check being wrong. The template's per-section prompts are comments too.
        $body = @"
<!--
  Rendered from config/repo.json by scripts/Generate-Policy.ps1.
-->

Nothing outside the comment names a path.
"@
        $r = Invoke-Check -Body $body
        if ($r.ExitCode -ne 0) { Write-Host $r.Output }
        $r.ExitCode | Should -Be 0
        $r.Output   | Should -Match 'PASS -- 0 path token\(s\) checked'
    }

    It 'a path outside the comment on the same line is still caught' {
        # The exemption must be the comment, not the line the comment is on -- otherwise one
        # trailing <!-- --> would launder every path beside it.
        $r = Invoke-Check -Body 'See scripts/ci/Test-Runtimes.ps1 <!-- config/repo.json -->'
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'scripts/ci/Test-Runtimes\.ps1  bare path'
        $r.Output   | Should -Not -Match 'config/repo\.json'
    }

    It 'an empty body fails' {
        $r = Invoke-Check -Body ''
        $r.ExitCode | Should -Be 1
        $r.Output   | Should -Match 'the body is empty'
    }

    It '-Body is honoured for a local run, not only $env:PR_BODY' {
        $previous = $env:PR_BODY
        $env:PR_BODY = 'scripts/ci/Test-Runtimes.ps1'   # would FAIL if the parameter were ignored
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            $null = & pwsh -NoProfile -File $script:Check -Body "[``README.md``]($script:Blob/README.md)" 2>&1
            $LASTEXITCODE | Should -Be 0 -Because '-Body must win over the environment variable'
        }
        finally { $env:PR_BODY = $previous }
    }

    It 'the falsification control: the green above is not the check passing by blindness' {
        # Every It that asserts a PASS is only worth something if the same body goes red when one
        # link is taken away. Mutate the good body, confirm red, confirm the original is still
        # green -- the same shape as tests/Generated.Tests.ps1's one-word-edit control.
        $green = Invoke-Check -Body $script:GoodBody
        $green.ExitCode | Should -Be 0

        $mutated = $script:GoodBody -replace [regex]::Escape("[``README.md``]($script:Blob/README.md)"), 'README.md'
        $mutated | Should -Not -Be $script:GoodBody -Because 'the mutation must actually change something'

        $red = Invoke-Check -Body $mutated
        $red.ExitCode | Should -Be 1 -Because 'one unlinked path is enough to fail the body'
        $red.Output   | Should -Match 'bare path'

        $again = Invoke-Check -Body $script:GoodBody
        $again.ExitCode | Should -Be 0 -Because 'restoring the link restores the green'
    }

    It 'the tracked top-level set is measured, so the token pattern is not matching nothing' {
        # If git ls-tree came back empty the pattern would match no path and every body would
        # pass. The script throws rather than passing in that case; this asserts it reports a
        # non-empty measurement on the way through.
        $r = Invoke-Check -Body $script:GoodBody
        $r.Output | Should -Match 'tracked top-level director\(ies\)'
        $r.Output | Should -Not -Match '^pr-body-links: 0 tracked'
    }
}
