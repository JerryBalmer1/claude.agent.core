#Requires -Version 7.4
<#
    The push tripwire.

    On the free tier a private repository gets no branch protection - that is measured, not
    assumed, and docs/PROTECTION.md records the three HTTP 403s.
    So nothing here can REFUSE a direct push to main or develop. What it can do is notice.

    A commit that arrives on a long-lived branch through the flow is a merge commit with two
    parents, carrying a `who:` trailer written by the automerge workflow. A commit that arrives
    any other way is, by construction, missing at least one of those. The tripwire asserts both
    and goes red when either is absent, which leaves a permanent, dated, public record on the
    commit that did it.

    This is a smoke alarm, not a lock. It is worth having anyway: the failure mode it exists for
    is an agent pushing straight to main and reporting success, which had already happened once
    in the legacy repo before this one was copied out of it. Nobody noticed for a day.

    What is tested here is the WIRING only: that the workflow exists, that it watches both
    long-lived branches, and that it is never a required check. The two gates themselves are
    NOT tested. The versions of those tests in the repo this was copied from pinned live commit
    shas as fixtures, and a clean copy does not have those objects -- in a tree without them the
    assertions went green off git's own failure instead of off the guard, which is the exact
    failure mode this file exists to prevent. FINDINGS F78. BACKLOG B11 rebuilds them against
    synthetic repositories built by the test.
#>

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:Workflow = Join-Path $script:RepoRoot '.github/workflows/push-guard.yml'
}

Describe 'the push guard workflow is wired to the branches it guards' {

    It 'exists' {
        $script:Workflow | Should -Exist
    }

    It 'triggers on push to both long-lived branches, read from config' {
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20
        $yaml   = Get-Content -LiteralPath $script:Workflow -Raw

        $yaml | Should -Match '(?m)^on:'
        $yaml | Should -Match '(?m)^\s+push:'
        foreach ($b in @($config.branches.main, $config.branches.develop)) {
            $yaml | Should -Match ([regex]::Escape($b)) -Because "a branch nobody watches is a branch anyone can push to"
        }
    }

    It 'is not listed in required_checks, because a push check never reports on a pull request' {
        # If this name were in required_checks, automerge would wait forever for a check that
        # only fires on push events. The tripwire must not be able to deadlock the flow.
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20
        @($config.required_checks) | Should -Not -Contain 'push-guard'
    }
}
