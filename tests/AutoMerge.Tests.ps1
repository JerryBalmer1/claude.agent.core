#Requires -Version 7.4
<#
    The review-mode gate is the single decision that authorises an unattended merge, so it is
    the thing most worth being able to falsify without merging anything.

    scripts/Invoke-AutoMerge.ps1 documented this as a KNOWN HOLE and left it open: review.mode
    was read from the pull request HEAD, which means a branch that flips the mode to "auto" in
    its own diff authorises its own merge. The gate and the thing being gated were the same
    object. These tests are the proof that it is closed, and they are written so that reverting
    the fix turns them red rather than leaving them green on a technicality.

    `gh` is shadowed by a GLOBAL FUNCTION rather than mocked. Command resolution puts functions
    ahead of applications, so the library's bare `gh` call finds this one; nothing in
    scripts/AutoMerge.Lib.ps1 has a test-only branch or an injected fetcher, and the code path
    exercised here is byte-for-byte the one that runs in CI.
#>

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    . (Join-Path $script:RepoRoot 'scripts/AutoMerge.Lib.ps1')

    # ref -> the review.mode that `gh api .../config/repo.json?ref=<ref>` should answer with.
    $global:AutoMergeRefModes = @{}

    # A SIMPLE function, deliberately: no param() and no [CmdletBinding()], so PowerShell does
    # no parameter binding and every token -- including `--jq` -- lands in $args as a string.
    # An advanced function would try to bind `--jq` to a parameter named jq and throw.
    # How the shim should behave: 'ok', 'throw' (a real gh failure, e.g. 404) or 'empty'.
    # A SWITCH rather than redefining the function per test. Saving and restoring
    # function:global:gh worked when the file ran alone and failed inside the full suite, because
    # it depends on what else has touched that name; a variable the shim reads cannot be
    # polluted by ordering.
    $global:AutoMergeGhMode = 'ok'

    function global:gh {
        if ($global:AutoMergeGhMode -eq 'throw')   { throw 'gh: Not Found (HTTP 404)' }
        if ($global:AutoMergeGhMode -eq 'empty')   { return '' }
        if ($global:AutoMergeGhMode -eq 'wrapped') { return $global:AutoMergeWrapped }

        $url = @($args) | Where-Object { $_ -like '*contents/config/repo.json?ref=*' } | Select-Object -First 1
        if (-not $url) { throw "AutoMerge test shim: unexpected gh invocation: $(@($args) -join ' ')" }

        $ref = ($url -split '\?ref=')[-1]
        if (-not $global:AutoMergeRefModes.ContainsKey($ref)) {
            throw "AutoMerge test shim: no config registered for ref '$ref'"
        }

        $json = '{"review":{"mode":"' + $global:AutoMergeRefModes[$ref] + '"}}'
        return [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($json))
    }

    function script:New-FakePullRequest {
        param([string]$BaseRefName = 'develop',
              [string]$HeadRefOid  = 'f00dfeed00000000000000000000000000000000',
              [string]$HeadRefName = 'feature/self-authorising')
        return [pscustomobject]@{
            number      = 99
            baseRefName = $BaseRefName
            headRefOid  = $HeadRefOid
            headRefName = $HeadRefName
        }
    }
}

AfterAll {
    Remove-Item -LiteralPath 'function:global:gh' -ErrorAction SilentlyContinue
    Remove-Variable -Name 'AutoMergeRefModes' -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name 'AutoMergeGhMode' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'the review-mode gate reads the base, not the head' {

    It 'refuses to automerge when the base says human, however loudly the head says auto' {
        # THE FALSIFICATION. Under the old head-reading gate this returns IsAuto = $true and
        # the pull request merges itself. Reverting Get-ReviewConfigRef to $PullRequest.headRefOid
        # turns this red, which is the only reason it is worth having.
        $head = 'f00dfeed00000000000000000000000000000000'
        $global:AutoMergeRefModes = @{ 'develop' = 'human'; $head = 'auto' }

        $pr     = New-FakePullRequest -BaseRefName 'develop' -HeadRefOid $head
        $result = Test-ReviewModeAuto -Repo 'JerryBalmer1/claude.agent.substrate' -PullRequest $pr

        $result.IsAuto | Should -BeFalse -Because 'a pull request must not be able to authorise its own merge'
        $result.Mode   | Should -Be 'human'
        $result.Ref    | Should -Be 'develop'
    }

    It 'still automerges when the base says auto and the head says human' {
        # Guards the guard. A "fix" that hardcoded IsAuto to false, or that always stood down,
        # would pass the test above and fail this one. The claim is that the gate reads the
        # BASE -- not that it is permanently shut.
        $head = 'f00dfeed00000000000000000000000000000000'
        $global:AutoMergeRefModes = @{ 'develop' = 'auto'; $head = 'human' }

        $pr     = New-FakePullRequest -BaseRefName 'develop' -HeadRefOid $head
        $result = Test-ReviewModeAuto -Repo 'JerryBalmer1/claude.agent.substrate' -PullRequest $pr

        $result.IsAuto | Should -BeTrue
        $result.Mode   | Should -Be 'auto'
        $result.Ref    | Should -Be 'develop'
    }

    It 'reads the base branch by name so a mode flip governs pull requests opened before it' {
        $global:AutoMergeRefModes = @{ 'main' = 'human' }
        $pr = New-FakePullRequest -BaseRefName 'main'

        (Get-ReviewConfigRef -PullRequest $pr) | Should -Be 'main' -Because 'the tip of the base at gate time is what governs'
        (Test-ReviewModeAuto -Repo 'o/r' -PullRequest $pr).IsAuto | Should -BeFalse
    }

    It 'treats the mode as case-sensitive, so "AUTO" is not "auto"' {
        # ConvertFrom-Json preserves the string; the comparison is -ceq. A config that shouts
        # is a config that did not come from the schema, and it must not open the gate.
        $global:AutoMergeRefModes = @{ 'develop' = 'AUTO' }
        $pr = New-FakePullRequest -BaseRefName 'develop'

        (Test-ReviewModeAuto -Repo 'o/r' -PullRequest $pr).IsAuto | Should -BeFalse
    }

    It 'decodes a base64 payload that the contents API has wrapped across lines' {
        # The real endpoint wraps at 60 characters. The decode strips whitespace first; this
        # asserts that it does, because a FromBase64String on wrapped input throws.
        $wrapped = "{`n  `"review`" : {`n    `"mode`" : `"auto`"`n  }`n}"
        $b64     = [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($wrapped))
        $chunked = ($b64 -split '(.{1,60})' | Where-Object { $_ }) -join "`n"

        # Goes through the shim's MODE SWITCH rather than redefining function:global:gh.
        # The earlier version replaced the shim permanently and never put it back, so every
        # test declared after this one was talking to a stub that returns one fixed string -
        # which would have made the two "stands down" tests below pass for the wrong reason.
        # A test that silently disarms its neighbours is worse than no test.
        $global:AutoMergeWrapped = $chunked
        try {
            $global:AutoMergeGhMode = 'wrapped'
            $config = Get-RepoConfigAtRef -Repo 'o/r' -Ref 'develop'
            $config.review.mode | Should -Be 'auto'
        }
        finally {
            $global:AutoMergeGhMode = 'ok'
            Remove-Variable -Name 'AutoMergeWrapped' -Scope Global -ErrorAction SilentlyContinue
        }
    }
}

Describe 'a base branch with no config at all' {
    <#
        The bootstrap case, found in the legacy repo on the first pull request that
        used this gate. Reading review.mode from the base means the PR that INTRODUCES
        config/repo.json is opened against a base that does not have it, so the API answers 404.

        That part is correct and permanent - the bootstrap PR is merged by a human, once. What
        was wrong was the crash: a bare `gh` under $PSNativeCommandUseErrorActionPreference threw
        and failed the whole automerge run, contradicting the script's own contract that a pull
        request which is not ready is not an error.
    #>

    It 'stands down instead of throwing when the base has no config' {
        try {
            $global:AutoMergeGhMode = 'throw'
            $pr = New-FakePullRequest -BaseRefName 'develop'
            $result = Test-ReviewModeAuto -Repo 'o/r' -PullRequest $pr

            $result.IsAuto | Should -BeFalse -Because 'no config on the base means no authorisation'
            $result.Config | Should -BeNullOrEmpty
            $result.Mode   | Should -Match 'no config'
        }
        finally { $global:AutoMergeGhMode = 'ok' }
    }

    It 'stands down when the config comes back empty' {
        # A caller with native errors turned off gets nothing rather than an exception. Nothing
        # must not be decoded as a config.
        try {
            $global:AutoMergeGhMode = 'empty'
            $pr = New-FakePullRequest -BaseRefName 'develop'
            (Test-ReviewModeAuto -Repo 'o/r' -PullRequest $pr).IsAuto | Should -BeFalse
        }
        finally { $global:AutoMergeGhMode = 'ok' }
    }
}

Describe 'there is exactly one place that reads the review config' {

    It 'Invoke-AutoMerge.ps1 dot-sources the library instead of carrying its own copy' {
        # Count-and-subtract, not a grep for the fix. The claim is that the repository contains
        # ONE implementation of the config read: if Invoke-AutoMerge.ps1 grows a second
        # `contents/config/repo.json` call of its own, the gate can be correct in the library
        # and wrong in the thing that ships, and every test above would still be green.
        $script = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'scripts/Invoke-AutoMerge.ps1') -Raw

        $script | Should -Match 'AutoMerge\.Lib\.ps1' -Because 'the shipped script must use the tested gate'
        @([regex]::Matches($script, 'contents/config/repo\.json')).Count |
            Should -Be 0 -Because 'the only config read lives in scripts/AutoMerge.Lib.ps1'
    }

    It 'the library dot-sources cleanly and defines the gate' {
        $lib = Join-Path $script:RepoRoot 'scripts/AutoMerge.Lib.ps1'
        $lib | Should -Exist
        (Get-Content -LiteralPath $lib -TotalCount 1) | Should -Match '^#Requires -Version 7\.4\s*$'

        foreach ($fn in 'Get-RepoConfigAtRef', 'Get-ReviewConfigRef', 'Test-ReviewModeAuto') {
            (Get-Command -Name $fn -CommandType Function -ErrorAction SilentlyContinue) |
                Should -Not -BeNullOrEmpty -Because "$fn is part of the gate's surface"
        }
    }
}

Describe 'the workflow listens for the event that un-drafts a pull request' {

    # FINDINGS F65. Invoke-AutoMerge.ps1 stands down on a draft, which is right. But a draft that
    # is opened, CI'd, and only then marked ready has no event left that reaches the workflow
    # unless `ready_for_review` is in the pull_request types: no commit is pushed, so ci does not
    # re-run and no workflow_run completes either. The pull request sits open, un-drafted, every
    # check green, and never lands. Nothing turns red, because standing down and merging share an
    # exit code -- which is why this has to be a test and not a comment.

    It 'automerge.yml lists ready_for_review in the pull_request types' {
        $path = Join-Path $script:RepoRoot '.github/workflows/automerge.yml'
        $path | Should -Exist
        $lines = [System.IO.File]::ReadAllLines($path)

        # PARSED, NOT GREPPED, and this is the whole point of the It. `$yaml -match
        # 'ready_for_review'` would be satisfied by the comment block above the trigger that
        # explains why the entry is needed -- so deleting the entry and keeping the prose would
        # leave this green while the trap was wide open. That is the detector-shaped-to-the-fix
        # failure this repository keeps catching itself on (F32, F64). So: find the pull_request
        # key under `on:`, then the first `types:` line belonging to it, and read THAT list.
        $inPullRequest = $false
        $typesLine     = $null
        foreach ($line in $lines) {
            if ($line -match '^\s*#') { continue }
            if ($line -match '^\s{2}pull_request:\s*$') { $inPullRequest = $true; continue }
            # Any other key at the same indentation ends the pull_request block.
            if ($inPullRequest -and $line -match '^\s{2}\S') { break }
            if ($inPullRequest -and $line -match '^\s+types:\s*\[(?<list>[^\]]*)\]\s*$') {
                $typesLine = $Matches['list']
                break
            }
        }

        $typesLine | Should -Not -BeNullOrEmpty -Because 'the pull_request trigger must declare an explicit types list for this check to mean anything'

        $types = @($typesLine -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

        # Anti-vacuity: prove the parse landed on the real list before trusting what it contains.
        # An expression that matched the workflow_run types would also be "not empty".
        $types | Should -Contain 'opened'     -Because 'the parse must have found the pull_request types, not some other list'
        $types | Should -Contain 'synchronize' -Because 'same'

        $types | Should -Contain 'ready_for_review' -Because 'without it, a draft marked ready has no event left that reaches automerge -- F65'
    }
}
