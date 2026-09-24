#Requires -Version 7.4
<#
    modules/ledger/python -- the compute engine, and the boundary it is allowed to live on.

    Substrate is a PowerShell repository. Python is here by a single written permission:
    config/repo.json -> runtimes.python.allowed_under, granted by the substrate-cutover run
    order because the snake's retry loop is Python and rewriting it was explicitly out of
    scope. CI enforces the boundary (scripts/ci/Test-Runtimes.ps1, a step of the
    requires-header check); this suite tests the engine itself.

    NO pip install ANYWHERE IN THIS FILE, and that is an assertion rather than an omission.
    The dry-run path never constructs a client, so it needs no SDK; snake.py imports
    anthropic inside the live transport and nowhere else. If that import ever moved to the
    top of the module, every dry-run in this repository would start requiring a package it
    does not use, and the It below is what notices.
#>

Describe 'ledger python engine' -Tag 'ledger' {

    BeforeAll {
        $script:ModuleRoot = Split-Path $PSScriptRoot -Parent
        $script:PythonDir  = Join-Path $script:ModuleRoot 'python'
        $script:Cli        = Join-Path $script:PythonDir 'cli.py'
        $script:Manifest   = Join-Path $script:ModuleRoot 'ledger.psd1'
        $script:TempRoot   = [System.IO.Path]::GetTempPath()
        $script:TempDirs   = [System.Collections.Generic.List[string]]::new()

        Import-Module -Name $script:Manifest -Force -ErrorAction Stop

        function New-TempDir {
            $d = Join-Path $script:TempRoot ('ledger-python-' + [guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $d -Force
            $script:TempDirs.Add($d)
            return $d
        }

        function Invoke-Native {
            # A native call whose exit code is DATA. The repo sets
            # $PSNativeCommandUseErrorActionPreference = $true, which is correct everywhere
            # except in a test whose job is to watch something fail on purpose. Setting the
            # preference inside the function makes a local copy; the caller's value stands.
            param([Parameter(Mandatory)][string]$Exe, [string[]]$Arguments = @(), [string]$StdIn)
            $PSNativeCommandUseErrorActionPreference = $false
            $ErrorActionPreference = 'Continue'
            $out = if ($PSBoundParameters.ContainsKey('StdIn')) {
                $StdIn | & $Exe @Arguments 2>&1
            } else {
                & $Exe @Arguments 2>&1
            }
            return [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out | Out-String) }
        }

        # The interpreter, resolved the way the module resolves it, with the one fallback that
        # matters: 'python' is what Invoke-LedgerForce defaults to and what actions/setup-python
        # provides, but a bare Linux box has only 'python3'. Measured, then reported, so a
        # failure below says which interpreter it was talking to.
        $script:PythonExe = $null
        foreach ($candidate in 'python', 'python3') {
            $cmd = Get-Command -Name $candidate -CommandType Application -ErrorAction SilentlyContinue |
                   Select-Object -First 1
            if ($cmd) { $script:PythonExe = $cmd.Source; break }
        }
        $script:PythonVersion = if ($script:PythonExe) {
            (Invoke-Native -Exe $script:PythonExe -Arguments @('--version')).Output.Trim()
        } else { '(absent)' }
        Write-Host "python engine suite: interpreter '$script:PythonExe' -- $script:PythonVersion"
    }

    Context 'the interpreter' {

        It 'a python interpreter is on PATH' {
            # Not skipped when absent. The pester job installs one (actions/setup-python, pinned
            # by sha) precisely so that this is a real requirement; a Skip here would turn the
            # whole engine suite green on a runner that cannot run the engine.
            $script:PythonExe | Should -Not -BeNullOrEmpty
        }

        It 'and it is at least the version config/repo.json declares' {
            $repoRoot = Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent
            $config = Get-Content -LiteralPath (Join-Path $repoRoot 'config/repo.json') -Raw |
                      ConvertFrom-Json -Depth 20
            $floor = [version]$config.runtimes.python.version
            $m = [regex]::Match($script:PythonVersion, '(\d+)\.(\d+)(?:\.(\d+))?')
            $m.Success | Should -BeTrue -Because "'$script:PythonVersion' must state a version"
            $have = [version]("{0}.{1}" -f $m.Groups[1].Value, $m.Groups[2].Value)
            $have | Should -BeGreaterOrEqual ([version]("{0}.{1}" -f $floor.Major, $floor.Minor))
        }

        It 'every .py file in this repository sits under the one allowed prefix' {
            $repoRoot = Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent
            $config = Get-Content -LiteralPath (Join-Path $repoRoot 'config/repo.json') -Raw |
                      ConvertFrom-Json -Depth 20
            $allowed = @($config.runtimes.python.allowed_under)
            $found = @(Get-ChildItem -LiteralPath $repoRoot -Recurse -File -Filter '*.py' |
                ForEach-Object { [System.IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } |
                Where-Object { $_ -notmatch '(^|/)\.git/' })
            $found | Should -Not -BeNullOrEmpty -Because 'the engine landed in this phase'
            foreach ($rel in $found) {
                @($allowed | Where-Object { $rel.StartsWith($_, [System.StringComparison]::Ordinal) }) |
                    Should -Not -BeNullOrEmpty -Because "$rel must be under one of: $($allowed -join ', ')"
            }
        }
    }

    Context 'the CLI' {

        It 'cli.py --help exits 0' {
            (Invoke-Native -Exe $script:PythonExe -Arguments @($script:Cli, '--help')).Code |
                Should -Be 0
        }

        It 'cli.py refuses a protocol it does not speak, with a usage exit code' {
            # The contract runs both ways: the snake must reject a PowerShell that has drifted,
            # not do its best with it. Every other required argument is supplied, so the refusal
            # can only be about the protocol -- measured, after a first version of this It passed
            # its exit-code assertion for the entirely different reason that argparse was still
            # complaining about missing arguments.
            $r = Invoke-Native -Exe $script:PythonExe -StdIn '{"prompt":"x"}' -Arguments @(
                $script:Cli, '--protocol', '99', '--mode', 'dry-run', '--model', 'none',
                '--max-retries', '1', '--validator', 'non_empty')
            $r.Code | Should -Be 3
            $r.Output | Should -Match 'protocol 99 not supported'
        }

        It 'all four engine modules compile' {
            # compile(), not py_compile: py_compile's job is to WRITE a .pyc, which would put a
            # __pycache__ inside a directory this repository asserts is byte-identical to the
            # copy. Same guarantee, no artifact.
            $probe = 'import sys;p=sys.argv[1];compile(open(p,encoding="utf-8").read(),p,"exec")'
            foreach ($f in 'cli.py', 'snake.py', 'validators.py', '__init__.py') {
                (Invoke-Native -Exe $script:PythonExe `
                    -Arguments @('-c', $probe, (Join-Path $script:PythonDir $f))).Code |
                    Should -Be 0 -Because "$f must at least parse"
            }
        }
    }

    Context 'the dry-run path needs no SDK, and that is measured rather than hoped' {

        It 'the anthropic SDK is genuinely not installed' {
            # The premise of every row in this Context. If the SDK were present, "dry-run works"
            # would prove nothing about whether dry-run needs it.
            (Invoke-Native -Exe $script:PythonExe -Arguments @('-c', 'import anthropic')).Code |
                Should -Not -Be 0
        }

        It 'and requirements.txt, which is never installed here, is what would install it' {
            $req = Get-Content -LiteralPath (Join-Path $script:PythonDir 'requirements.txt') -Raw
            $req | Should -Match 'anthropic'
        }

        It 'snake.py imports anthropic lazily, inside the live path only' {
            # Proved structurally with Python's own parser rather than by reading the file: a
            # top-level `import anthropic` would break every dry-run in this repository, and a
            # regex over the source cannot tell a top-level import from an indented one as
            # reliably as the AST that the interpreter itself builds.
            $probe = 'import ast,sys;' +
                     't=ast.parse(open(sys.argv[1],encoding="utf-8").read());' +
                     'top=[n for n in t.body if isinstance(n,(ast.Import,ast.ImportFrom))];' +
                     'names=[a.name for n in top if isinstance(n,ast.Import) for a in n.names]+' +
                     '[n.module or "" for n in top if isinstance(n,ast.ImportFrom)];' +
                     'inner=[n for n in ast.walk(t) if isinstance(n,ast.ImportFrom) and (n.module or "").startswith("anthropic")];' +
                     'print("TOP="+(",".join(names)));print("INNER="+str(len(inner)))'
            $r = Invoke-Native -Exe $script:PythonExe -Arguments @('-c', $probe, (Join-Path $script:PythonDir 'snake.py'))
            $r.Code | Should -Be 0
            $r.Output | Should -Not -Match 'TOP=[^\r\n]*anthropic'
            $r.Output | Should -Match 'INNER=[1-9]'
        }

        It 'a full dry-run force runs the retry loop, appends one receipt, and never touches the network' {
            # End to end: PowerShell spawns the snake, the snake fails its first scripted
            # response against the validator, feeds the failure back, and the second attempt
            # passes. Two attempts is the proof that the loop is a loop.
            $p = Join-Path (New-TempDir) 'dryrun.jsonl'
            $r = Invoke-LedgerForce -Prompt 'Write a Python function add(a, b) that returns a + b.' `
                -Validator 'has_function_def' -Mode 'dry-run' -LedgerPath $p
            $r.Mode | Should -BeExactly 'dry-run'
            $r.Attempts | Should -Be 2
            $r.Sha256 | Should -Match '^[0-9a-f]{64}$'
            $r.Output | Should -Match 'def add'
            $v = Get-LedgerVerify -LedgerPath $p
            $v.Ok | Should -BeTrue
            $v.Count | Should -Be 1
            $v.LastSelf | Should -Match '^[0-9a-f]{64}$'
        }

        It 'the receipt records the hash of the output that was actually returned' {
            $p = Join-Path (New-TempDir) 'rehash.jsonl'
            $r = Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator 'has_function_def' `
                -Mode 'dry-run' -LedgerPath $p
            $expected = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes($r.Output))).ToLowerInvariant()
            $r.Sha256 | Should -BeExactly $expected
            (Get-LedgerEntry -LedgerPath $p -Last 1).Sha256 | Should -BeExactly $expected
        }
    }

    Context 'the failure path -- a non-zero Python exit is a terminating PowerShell error' {

        It 'an exhausted retry cap throws LedgerSnakeFailed and returns nothing' {
            # This is tests/sandbox/fail_path.ps1's whole claim, as one It. The sandbox original
            # is kept beside this file as provenance; it cannot run here, because it imports
            # ../../src/ledger/Ledger.psd1 from the source repository's layout.
            #
            # "Nothing is swallowed": the snake's MAX_RETRIES event reaches the error stream BEFORE
            # the terminating error. It is collected and asserted here, not left to leak into the
            # run, where scripts/Measure-Modules.ps1 counts it as an exception.
            $p = Join-Path (New-TempDir) 'failpath.jsonl'
            $streamed = [System.Collections.Generic.List[object]]::new()
            $err = {
                Invoke-LedgerForce -Prompt 'Write a Python function add(a, b).' `
                    -Validator 'has_function_def' -MaxRetries 3 -Mode 'dry-run' -LedgerPath $p `
                    -MockResponse 'I would rather write you a poem about addition than any code.' 2>&1 |
                    ForEach-Object { $streamed.Add($_) }
            } | Should -Throw -PassThru
            $err.FullyQualifiedErrorId | Should -Match '^LedgerSnakeFailed'
            $err.CategoryInfo.Category | Should -Be 'OperationStopped'
            @($streamed | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } |
                ForEach-Object { $_.ToString() }) | Should -Match '^\[snake\] MAX_RETRIES: '
            $p | Should -Not -Exist -Because 'a run that never satisfied the validator has nothing to sign'
        }

        It 'a missing interpreter is refused before anything is spawned' {
            $p = Join-Path (New-TempDir) 'nopython.jsonl'
            $err = {
                Invoke-LedgerForce -Prompt 'x' -Mode 'dry-run' -LedgerPath $p `
                    -PythonPath 'definitely-not-an-interpreter-a1b2c3'
            } | Should -Throw -PassThru
            $err.FullyQualifiedErrorId | Should -Match '^LedgerPythonMissing'
        }

        It 'live mode with no API key throws before the snake is spawned, and writes no receipt' {
            $p = Join-Path (New-TempDir) 'nokey.jsonl'
            $saved = $env:ANTHROPIC_API_KEY
            try {
                $env:ANTHROPIC_API_KEY = ''
                $err = {
                    Invoke-LedgerForce -Prompt 'x' -Validator 'non_empty' -Mode 'live' -LedgerPath $p
                } | Should -Throw -PassThru
                $err.FullyQualifiedErrorId | Should -Match '^LedgerMissingApiKey'
            }
            finally { $env:ANTHROPIC_API_KEY = $saved }
            $p | Should -Not -Exist
        }
    }

    Context 'the suite left no footprint' {

        It 'no live ledger was created at the module default path' {
            $repoRoot = Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent
            Join-Path $repoRoot '.ledger' | Should -Not -Exist
        }

        It 'running the engine left the engine directory clean' {
            # Spawning cli.py makes CPython write a __pycache__ beside the engine. That is
            # unavoidable and harmless, but it is only harmless because .gitignore says so --
            # substrate had no Python entries at all before this phase, because it had no
            # Python. This asserts the outcome that actually matters: after a real force, git
            # sees nothing new or changed under the copied engine.
            #
            # Scoped to modules/ledger/python rather than to modules/ledger, and deliberately:
            # widening it would make the check report the working state of whatever else is
            # being edited in the same session, which is a fact about the author, not the
            # engine.
            $repoRoot = Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent
            Push-Location $repoRoot
            try { $dirty = @(git status --porcelain -- 'modules/ledger/python') }
            finally { Pop-Location }
            $dirty | Should -BeNullOrEmpty
        }

        It 'and the bytecode that does appear is ignored by name, not by luck' {
            $repoRoot = Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent
            $ignore = Get-Content -LiteralPath (Join-Path $repoRoot '.gitignore') -Raw
            $ignore | Should -Match '(?m)^__pycache__/'
            $ignore | Should -Match '(?m)^\*\.pyc'
        }

        It 'and every temp fixture it created is gone' {
            $script:TempDirs.Count | Should -BeGreaterThan 2
            foreach ($d in $script:TempDirs) {
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            }
            foreach ($d in $script:TempDirs) { $d | Should -Not -Exist }
        }
    }
}
