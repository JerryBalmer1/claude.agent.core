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

    The WIRING is tested first: that the workflow exists, that it watches both long-lived
    branches, and that it is never a required check. The versions of the gate tests in the repo
    this was copied from pinned live commit shas as fixtures, and a clean copy does not have those
    objects -- in a tree without them the assertions went green off git's own failure instead of
    off the guard. FINDINGS F78. The gates are now tested against synthetic repositories built in
    TestDrive (BACKLOG B11, for PushGuard), each asserting the guard's own output line, never
    only its exit code.

    The merge rule is D012 (F93): a merge commit's own message is exempt, because GitHub writes it
    when Jerry clicks; every non-merge commit the merge brings in must carry the trailer.
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

Describe 'the push guard judges a merge by the commits it brings in (D012, F93)' {
    BeforeAll {
        $script:Guard = Join-Path $script:RepoRoot 'scripts/ci/Test-PushGuard.ps1'
        $script:Id = @('-c', 'user.name=Jerry Balmer', '-c', 'user.email=jerry@example.invalid', '-c', 'init.defaultBranch=develop', '-c', 'core.autocrlf=false')

        # One synthetic repository: develop with a compliant root, and a feature branch per case.
        $script:Repo = Join-Path $TestDrive 'repo'
        $null = New-Item -ItemType Directory -Path $script:Repo
        function script:G { $null = & git -C $script:Repo @script:Id @args 2>&1 }
        function script:Commit([string]$Name, [string]$Message) {
            [System.IO.File]::WriteAllText((Join-Path $script:Repo "$Name.txt"), "$Name`n")
            G add -- "$Name.txt"
            G commit -q -m $Message
            (& git -C $script:Repo rev-parse HEAD).Trim()
        }
        # The message GitHub's merge button writes: no trailer.
        function script:HumanMerge([string]$Branch) {
            G switch -q develop
            G merge -q --no-ff $Branch -m "Merge pull request #1 from JerryBalmer1/$Branch"
            (& git -C $script:Repo rev-parse HEAD).Trim()
        }
        function script:Judge([string]$Sha) {
            $out = & pwsh -NoProfile -File $script:Guard -Sha $Sha -Repository $script:Repo *>&1 | Out-String
            [pscustomobject]@{ Exit = $LASTEXITCODE; Out = $out }
        }

        G init -q
        $script:Root = Commit 'root' "scaffold: root`n`nwho: claude"

        G switch -q -c feature/good
        $null = Commit 'a' "feat: a`n`nwho: claude"
        $null = Commit 'b' "fix: b`n`nwho: claude"
        $script:GoodMerge = HumanMerge 'feature/good'

        G switch -q -c feature/bad
        $null = Commit 'c' "feat: c`n`nwho: claude"
        $script:BadSha = Commit 'd' 'fix: d, no trailer'
        $script:BadMerge = HumanMerge 'feature/bad'

        G switch -q develop
        $script:Direct = Commit 'e' "fix: e, pushed straight to develop`n`nwho: claude"

        # A merge whose second parent is already an ancestor of its first: it brings in nothing.
        $tree = (& git -C $script:Repo rev-parse 'HEAD^{tree}').Trim()
        $script:EmptyMerge = (& git -C $script:Repo @script:Id commit-tree $tree -p $script:Direct -p $script:Root -m 'Merge pull request #3 from JerryBalmer1/feature/empty').Trim()
    }

    It 'passes a human-authored merge, no trailer on it, of commits that all carry one' {
        (& git -C $script:Repo log -1 --format='%(trailers:key=who,valueonly)' $script:GoodMerge).Trim() | Should -BeNullOrEmpty -Because 'the precondition: the merge commit itself has no trailer'
        $r = Judge $script:GoodMerge
        $r.Out | Should -Match 'OK    who: on all 2 non-merge commit\(s\) the merge brings in'
        $r.Out | Should -Match 'push-guard: PASS'
        $r.Exit | Should -Be 0
    }

    It 'fails the same merge over one commit without the trailer, and names it' {
        $r = Judge $script:BadMerge
        $r.Out | Should -Match ("1 of 2 commit\(s\) the merge brings in lack an allowed 'who:' trailer: {0}" -f $script:BadSha.Substring(0, 8))
        $r.Out | Should -Match 'push-guard: FAIL -- 1 of 2 gates failed'
        $r.Exit | Should -Be 1
    }

    It 'fails a one-parent commit even when it carries the trailer' {
        $r = Judge $script:Direct
        $r.Out | Should -Match 'FAIL  only 1 parent'
        $r.Exit | Should -Be 1
    }

    It 'fails a merge that brings in no non-merge commit' {
        $r = Judge $script:EmptyMerge
        $r.Out | Should -Match 'the merge brings in no non-merge commit'
        $r.Exit | Should -Be 1
    }
}
