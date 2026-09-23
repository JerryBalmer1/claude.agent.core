#Requires -Version 7.4
<#
    scripts/Invoke-Preflight.ps1 -- the open-pull-request overlap preflight.

    `gh` IS SHADOWED BY A GLOBAL FUNCTION, not injected. Command resolution puts functions ahead
    of applications, so the script's bare `gh` call finds this one, and the file under test is
    byte-for-byte the file that ships: there is no -GhCommand parameter, no test-only branch and
    no code path here that a real run does not take. This is the idiom tests/AutoMerge.Tests.ps1
    established and the reason it gives applies unchanged.

    THE SCRIPT IS INVOKED IN-PROCESS WITH `&`, WHICH IS WHAT MAKES THE EXIT CODES TESTABLE.
    Measured before this suite was written: a script run with `& ./x.ps1` that reaches `exit 2`
    stops at that point, leaves 2 in $LASTEXITCODE and returns control to the caller. `pwsh -File`
    would agree but would be a child process, where a global function cannot shadow anything; and
    `pwsh -Command` does NOT agree -- it reports the success of the command line rather than
    propagating the nested exit, turning 2 into 1. That last fact is recorded in the script's own
    help and in the forensic chain at seq 11, because for a script whose whole contract is its
    exit code it rewrites "I could not see" into "I found an overlap".

    WHAT IS WORTH TESTING HERE is not that the tool works but that its three answers stay
    distinct. 0 and 2 are the dangerous pair: "no overlap" and "no answer" look identical to
    anything that only asks whether the command succeeded.
#>

BeforeDiscovery {
    # THE -ForEach LIST LIVES HERE, IN BeforeDiscovery, NOT IN BeforeAll. docs/IDEAS.md records
    # why under "A test count that does not move is a signal": a -ForEach list built in BeforeAll
    # is empty at discovery time, so the Its expand to nothing, and zero cases report exactly the
    # same as passing cases. It happened twice -- the PR template work and the header work -- and
    # both times the only thing that exposed it was a suite total that failed to move.
    #
    # A GLOBAL, so the list survives from the discovery phase into the run phase and the guard It
    # below can assert its length. A discovery-scoped variable is not reliably visible at run time,
    # which would make the guard assert on $null and pass for the wrong reason.
    $global:PreflightGlobCases = @(
        @{ Label = 'a literal path';                  Pattern = 'docs/IDEAS.md' }
        @{ Label = 'a glob over one extension';       Pattern = 'docs/*.md' }
        @{ Label = 'a glob over a directory';         Pattern = 'docs/*' }
        @{ Label = 'a glob on the leading segment';   Pattern = '*/IDEAS.md' }
        @{ Label = 'a Windows-style separator';       Pattern = 'docs\IDEAS.md' }
    )
}

BeforeAll {
    $script:RepoRoot   = Split-Path $PSScriptRoot -Parent
    $script:ScriptPath = Join-Path $script:RepoRoot 'scripts/Invoke-Preflight.ps1'
    $script:ChainPath  = Join-Path $script:RepoRoot '.continuity/forensic.jsonl'
    $script:Repo       = 'JerryBalmer1/claude.agent.core'

    # How the shim should behave. A SWITCH read by one permanent function rather than redefining
    # function:global:gh per test: AutoMerge.Tests.ps1 records that save-and-restore of a global
    # function name worked when its file ran alone and failed inside the full suite, because it
    # depends on what else has touched the name.
    $global:PreflightGhMode = 'ok'

    # The open pull requests the shim will describe. 101 touches docs/, 102 touches only the
    # workflow -- 102 is the whole reason the tool reports overlap rather than existence.
    $global:PreflightPrs = @(
        [pscustomobject]@{ number = 101; title = 'docs: the ideas sweep'; headRefName = 'feature/ideas-sweep'; files = @('docs/IDEAS.md', 'docs/POSITION.md') }
        [pscustomobject]@{ number = 102; title = 'ci: pin the runner';    headRefName = 'feature/pin-runner';  files = @('.github/workflows/ci.yml') }
    )

    # A SIMPLE function -- no param(), no [CmdletBinding()] -- so PowerShell does no parameter
    # binding and every token, including `--json`, lands in $args as a plain string. An advanced
    # function would try to bind `--json` to a parameter named json and throw.
    function global:gh {
        if ($global:PreflightGhMode -eq 'throw')   { throw 'gh: HTTP 401 Bad credentials. The github.com token is invalid.' }
        if ($global:PreflightGhMode -eq 'empty')   { return '' }
        if ($global:PreflightGhMode -eq 'garbage') { return 'Welcome to gh! Run `gh auth login` to get started.' }
        if ($global:PreflightGhMode -eq 'shapeless') { return '[{"nope":1}]' }

        $tokens = @($args)

        if ($tokens -contains 'list') {
            $rows = @($global:PreflightPrs | ForEach-Object {
                [pscustomobject]@{ number = $_.number; title = $_.title; headRefName = $_.headRefName }
            })
            # PIPED into ConvertTo-Json, not -InputObject. `-InputObject $rows -AsArray` wraps an
            # array that is already an array, producing [[{...}]] -- and the script's shape guard
            # correctly refused it as "a record with no 'number'". That is the shim lying about
            # what gh returns, which is the one bug a mock can have that makes a correct script
            # look broken. Piping unrolls the array and -AsArray puts the brackets back, so 0, 1
            # and n records all serialise the way `gh pr list --json` really does.
            return ($rows | ConvertTo-Json -Depth 5 -AsArray)
        }

        if ($tokens -contains 'view') {
            $i = [array]::IndexOf($tokens, 'view')
            $n = [int]$tokens[$i + 1]
            $pr = $global:PreflightPrs | Where-Object { $_.number -eq $n } | Select-Object -First 1
            if (-not $pr) { throw "Preflight test shim: no fixture pull request numbered $n" }
            $payload = [pscustomobject]@{ files = @($pr.files | ForEach-Object { [pscustomobject]@{ path = $_ } }) }
            return (ConvertTo-Json -InputObject $payload -Depth 5)
        }

        throw "Preflight test shim: unexpected gh invocation: $($tokens -join ' ')"
    }

    # 6>$null swallows the script's Write-Host commentary so the suite output stays readable. It
    # cannot swallow the objects: Write-Host writes to the information stream and the findings are
    # written to the success stream, which is the separation being relied on.
    function script:Invoke-PreflightScript {
        param(
            [Parameter(Mandatory)] [string[]]$PathSpec,
            [switch]$UseConfigRepo
        )
        $global:LASTEXITCODE = 0
        $objects = if ($UseConfigRepo) {
            @(& $script:ScriptPath -Path $PathSpec 6>$null)
        }
        else {
            @(& $script:ScriptPath -Path $PathSpec -Repo $script:Repo 6>$null)
        }
        return [pscustomobject]@{ Exit = $LASTEXITCODE; Objects = $objects }
    }
}

AfterAll {
    Remove-Item -LiteralPath 'function:global:gh' -ErrorAction SilentlyContinue
    Remove-Variable -Name 'PreflightGhMode'   -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name 'PreflightPrs'      -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name 'PreflightGlobCases' -Scope Global -ErrorAction SilentlyContinue
}

Describe 'overlap is the signal, not the existence of an open pull request' {

    It 'reports nothing and exits 0 when the declared paths are disjoint from every open PR' {
        # Two pull requests are open throughout this It. A tool that answered "is anything open?"
        # would report both. The correct answer is silence.
        $r = Invoke-PreflightScript -PathSpec 'modules/ledger/ledger.psm1'

        $r.Exit    | Should -Be 0
        $r.Objects | Should -BeNullOrEmpty -Because 'a disjoint open pull request is not a finding'
    }

    It 'exits 1 and names the overlapping path when one path collides' {
        $r = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md'

        $r.Exit            | Should -Be 1
        $r.Objects.Count   | Should -Be 1 -Because 'only 101 touches docs/IDEAS.md; 102 is open and disjoint'
        $r.Objects[0].Paths | Should -Contain 'docs/IDEAS.md'
    }

    It 'carries the number, title and branch of the pull request it found' {
        $r = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md'

        $r.Objects[0].Number | Should -Be 101
        $r.Objects[0].Title  | Should -Be 'docs: the ideas sweep'
        $r.Objects[0].Branch | Should -Be 'feature/ideas-sweep'
    }

    It 'reports the intersection, not the whole file list of the pull request' {
        # 101 touches docs/IDEAS.md AND docs/POSITION.md. Declaring only the first must report
        # only the first, or the output stops being actionable the moment a PR is large.
        $r = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md'

        $r.Objects[0].Paths                    | Should -Not -Contain 'docs/POSITION.md'
        @($r.Objects[0].Paths).Count           | Should -Be 1
    }

    It 'finds every overlapping pull request when the declared set spans both' {
        $r = Invoke-PreflightScript -PathSpec @('docs/IDEAS.md', '.github/workflows/ci.yml')

        $r.Exit          | Should -Be 1
        $r.Objects.Count | Should -Be 2
        @($r.Objects.Number | Sort-Object) | Should -Be @(101, 102)
    }
}

Describe 'a glob finds what a literal path finds' {

    It '<Label> matches the same file' -ForEach $global:PreflightGlobCases {
        $r = Invoke-PreflightScript -PathSpec $Pattern

        $r.Exit | Should -Be 1 -Because "'$Pattern' names a file that pull request 101 touches"
        $r.Objects[0].Paths | Should -Contain 'docs/IDEAS.md'
    }

    It 'the -ForEach list expanded, so the cases above are real cases' {
        # THE GUARD, and it is a plain It on purpose: a -ForEach It whose list is empty does not
        # fail, it ceases to exist, and a suite of zero cases is reported exactly like a suite that
        # passed. This assertion cannot vanish with the list it is measuring, so a list that
        # silently expands to nothing turns this one red instead of turning the file green.
        @($global:PreflightGlobCases).Count | Should -Be 5 -Because 'five glob cases are declared in BeforeDiscovery'

        foreach ($c in $global:PreflightGlobCases) {
            $c.Keys | Should -Contain 'Pattern' -Because 'a case with no Pattern would expand into an It that tests nothing'
            $c.Keys | Should -Contain 'Label'
        }
    }
}

Describe 'cannot see is not the same answer as clear' {

    It 'exits 2 when gh fails' {
        try {
            $global:PreflightGhMode = 'throw'
            $r = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md'
            $r.Exit    | Should -Be 2
            $r.Objects | Should -BeNullOrEmpty
        }
        finally { $global:PreflightGhMode = 'ok' }
    }

    It 'exits 2 when gh returns nothing at all' {
        # An empty answer is not an empty list. Decoding it as one is how a preflight reports
        # "clear" on a repository it never managed to ask about.
        try {
            $global:PreflightGhMode = 'empty'
            (Invoke-PreflightScript -PathSpec 'docs/IDEAS.md').Exit | Should -Be 2
        }
        finally { $global:PreflightGhMode = 'ok' }
    }

    It 'exits 2 when gh answers with something that is not JSON' {
        try {
            $global:PreflightGhMode = 'garbage'
            (Invoke-PreflightScript -PathSpec 'docs/IDEAS.md').Exit | Should -Be 2
        }
        finally { $global:PreflightGhMode = 'ok' }
    }

    It 'exits 2 rather than 1 when the JSON is well-formed but the wrong shape' {
        # The sharp one. Set-StrictMode turns a missing property into a throw, and an uncaught
        # throw leaves pwsh's own exit 1 behind -- which this contract already spends on "overlap
        # found". Without the shape guard in the script a malformed answer is indistinguishable
        # from a real finding.
        try {
            $global:PreflightGhMode = 'shapeless'
            (Invoke-PreflightScript -PathSpec 'docs/IDEAS.md').Exit |
                Should -Be 2 -Because 'a record with no number is a cannot-see, not an overlap'
        }
        finally { $global:PreflightGhMode = 'ok' }
    }

    It 'says so on stderr, not only in the exit code' {
        # [Console]::Error is redirected rather than 2>, because the script writes there directly
        # to avoid Write-Error throwing under $ErrorActionPreference = 'Stop' and replacing the
        # promised 2 with pwsh's own code.
        $writer   = [System.IO.StringWriter]::new()
        $original = [Console]::Error
        try {
            $global:PreflightGhMode = 'throw'
            [Console]::SetError($writer)
            try { $null = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md' }
            finally { [Console]::SetError($original) }
        }
        finally { $global:PreflightGhMode = 'ok' }

        $said = $writer.ToString()
        $said | Should -Match 'CANNOT SEE'
        $said | Should -Match 'do not read this as'
    }

    It 'keeps all three answers distinct' {
        # The claim the whole script rests on, asserted as one comparison rather than inferred
        # from three separate Its passing. A regression that collapsed 2 into 0 would leave every
        # other test in this file green except the two that name 2 explicitly; this one states the
        # property itself.
        $clear   = Invoke-PreflightScript -PathSpec 'modules/ledger/ledger.psm1'
        $overlap = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md'

        $blind = $null
        try {
            $global:PreflightGhMode = 'throw'
            $blind = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md'
        }
        finally { $global:PreflightGhMode = 'ok' }

        @($clear.Exit, $overlap.Exit, $blind.Exit) | Should -Be @(0, 1, 2)
        (@($clear.Exit, $overlap.Exit, $blind.Exit) | Sort-Object -Unique).Count |
            Should -Be 3 -Because 'clear, overlap and blind must never be the same answer'
    }
}

Describe 'the falsification' {

    It 'exits non-zero on a fixture that is known to overlap' {
        # Deliberately weaker than "-Be 1". A script rewritten to always exit 0 -- the single most
        # likely way for this tool to become useless while every check stays green -- fails here
        # without this test needing to know which non-zero code is correct. The Its above pin the
        # exact value; this one pins the direction.
        $global:PreflightPrs = @(
            [pscustomobject]@{ number = 777; title = 'known overlap fixture'; headRefName = 'feature/known-overlap'; files = @('modules/policy/policy.psm1') }
        )
        try {
            $r = Invoke-PreflightScript -PathSpec 'modules/policy/policy.psm1'

            $r.Exit | Should -Not -Be 0 -Because 'the fixture was built to collide; a zero here means the tool cannot detect anything'
            $r.Objects[0].Number | Should -Be 777
        }
        finally {
            $global:PreflightPrs = @(
                [pscustomobject]@{ number = 101; title = 'docs: the ideas sweep'; headRefName = 'feature/ideas-sweep'; files = @('docs/IDEAS.md', 'docs/POSITION.md') }
                [pscustomobject]@{ number = 102; title = 'ci: pin the runner';    headRefName = 'feature/pin-runner';  files = @('.github/workflows/ci.yml') }
            )
        }
    }
}

Describe 'it observes and does not act' {

    It 'appends nothing to the forensic chain' {
        # The script's own claim about itself. A preflight that wrote a receipt every time anyone
        # thought about starting work would fill a chain that has to verify for ever with facts
        # about workstations.
        $before = (Get-FileHash -LiteralPath $script:ChainPath -Algorithm SHA256).Hash
        $null   = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md'
        $after  = (Get-FileHash -LiteralPath $script:ChainPath -Algorithm SHA256).Hash

        $after | Should -Be $before
    }

    It 'is not wired into CI, and required_checks stays at six' {
        # F17: the job keys in ci.yml are the required check names branch protection knows about.
        # This preflight is deliberately not one of them, and this assertion is what would notice
        # somebody deciding otherwise without a run order.
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20
        @($config.required_checks).Count | Should -Be 6

        $ci = Get-Content -LiteralPath (Join-Path $script:RepoRoot '.github/workflows/ci.yml') -Raw
        $ci | Should -Not -Match 'Invoke-Preflight' -Because 'a preflight is advice, not a gate'
    }
}

Describe 'the repository under test' {

    It 'defaults -Repo to config/repo.json rather than a literal in the script' {
        $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config/repo.json') -Raw | ConvertFrom-Json -Depth 20

        $r = Invoke-PreflightScript -PathSpec 'docs/IDEAS.md' -UseConfigRepo
        $r.Exit | Should -Be 1 -Because 'the default path must reach gh at all'

        $source = Get-Content -LiteralPath $script:ScriptPath -Raw
        $source | Should -Not -Match ([regex]::Escape($config.repo)) -Because 'the owner/name must be read from the config, not carried as a second copy'
    }

    It 'declares the version floor on line 1 like every other script here' {
        (Get-Content -LiteralPath $script:ScriptPath -TotalCount 1) | Should -Match '^#Requires -Version 7\.4\s*$'
    }
}
