#Requires -Version 7.4
<#
    scripts/Invoke-Core.ps1: one JSON request on stdin, one JSON response on stdout, exit 0 or 1,
    and nothing else on stdout.

    Every op is driven the way a non-PowerShell caller would drive it: a child pwsh, the request
    written to its stdin, stdout and the exit code read back. Nothing here imports a module to ask
    it directly. Every response is validated against schemas/core-response.schema.json, and every
    stdout is required to be exactly one JSON document.
#>

BeforeAll {
    $script:RepoRoot = Split-Path $PSScriptRoot -Parent
    $script:Script   = Join-Path $script:RepoRoot 'scripts/Invoke-Core.ps1'
    $script:Request  = Join-Path $script:RepoRoot 'schemas/core-request.schema.json'
    $script:Response = Join-Path $script:RepoRoot 'schemas/core-response.schema.json'
    $script:Pwsh     = (Get-Process -Id $PID).Path
    $script:Temp     = Join-Path ([System.IO.Path]::GetTempPath()) ('invoke-core-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $script:Temp

    # stdin in, stdout and exit code out. stderr is kept only for the failure message.
    function script:Invoke-Core {
        param([Parameter(Mandatory)][AllowEmptyString()][string]$Stdin)
        $psi = [System.Diagnostics.ProcessStartInfo]::new($script:Pwsh)
        foreach ($a in '-NoProfile', '-NonInteractive', '-File', $script:Script) { $psi.ArgumentList.Add($a) }
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $p = [System.Diagnostics.Process]::Start($psi)
        $p.StandardInput.Write($Stdin)
        $p.StandardInput.Close()
        $out = $p.StandardOutput.ReadToEndAsync()
        $err = $p.StandardError.ReadToEndAsync()
        if (-not $p.WaitForExit(120000)) { $p.Kill(); throw 'Invoke-Core.ps1 did not exit in 120 s' }
        [pscustomobject]@{ ExitCode = $p.ExitCode; StdOut = $out.Result; StdErr = $err.Result }
    }

    # The one shape every response has. Returns the parsed body.
    function script:Assert-Response {
        param([Parameter(Mandatory)]$R, [Parameter(Mandatory)][bool]$Ok)
        $R.StdOut | Should -Match '^\{.*\}$' -Because "stdout is exactly one JSON object; stderr: $($R.StdErr)"
        Test-Json -Json $R.StdOut -SchemaFile $script:Response | Should -BeTrue
        $body = $R.StdOut | ConvertFrom-Json
        $body.ok | Should -Be $Ok
        $R.ExitCode | Should -Be $(if ($Ok) { 0 } else { 1 })
        return $body
    }

    function script:ConvertTo-Request([hashtable]$H) { ConvertTo-Json -InputObject $H -Compress -Depth 10 }
}

AfterAll { Remove-Item -LiteralPath $script:Temp -Recurse -Force -ErrorAction SilentlyContinue }

Describe 'Invoke-Core.ps1: every op, through stdin and stdout only' {
    It 'ledger.append then ledger.verify: one record, and the chain verifies' {
        $chain = Join-Path $script:Temp 'append.jsonl'
        $a = Assert-Response -Ok $true -R (Invoke-Core (ConvertTo-Request @{
            op = 'ledger.append'; path = $chain; attempt = 1; validator = 'sentinel'; mode = 'Enforce'; model = 'test/Read/allow'; sha256 = ('ab' * 32) }))
        $a.op | Should -BeExactly 'ledger.append'
        $a.result.line | Should -Be 1
        $a.result.self | Should -Match '^[0-9a-f]{64}$'

        $v = Assert-Response -Ok $true -R (Invoke-Core (ConvertTo-Request @{ op = 'ledger.verify'; path = $chain }))
        $v.result.count | Should -Be 1
        $v.result.verified | Should -BeTrue
        $v.result.lastSelf | Should -BeExactly $a.result.self
    }

    It 'ledger.verify on a tampered chain is ok=false with the ledger''s own ErrorId' {
        $chain = Join-Path $script:Temp 'tamper.jsonl'
        foreach ($n in 1, 2) {
            $null = Assert-Response -Ok $true -R (Invoke-Core (ConvertTo-Request @{
                op = 'ledger.append'; path = $chain; attempt = 1; validator = 'v'; mode = 'm'; model = "x$n"; sha256 = ('cd' * 32) }))
        }
        [System.IO.File]::WriteAllText($chain, [System.IO.File]::ReadAllText($chain).Replace('"x1"', '"x9"'))
        $b = Assert-Response -Ok $false -R (Invoke-Core (ConvertTo-Request @{ op = 'ledger.verify'; path = $chain }))
        $b.error.code | Should -BeExactly 'LedgerBadSelf'
    }

    It 'ledger.verify on no chain is LedgerFileMissing' {
        $b = Assert-Response -Ok $false -R (Invoke-Core (ConvertTo-Request @{ op = 'ledger.verify'; path = (Join-Path $script:Temp 'none.jsonl') }))
        $b.error.code | Should -BeExactly 'LedgerFileMissing'
    }

    # modules/policy's own docs/do-not.md is the law here: it compiles to halt-weight path.src and
    # path.tests (verb write) and import.* (verb import) rules. This repository's AGENTS.md compiles
    # to one law rule with verb none, which nothing can match, so it would allow everything (D013).
    It 'policy.evaluate denies <Name>' -ForEach @(
        @{ Name = 'a Write under a halt-weight path';       Tool = 'Write'; In = @{ file_path = 'src/x.ps1'; content = 'x' };          Rule = 'path.src' }
        @{ Name = 'an Edit under a halt-weight path';       Tool = 'Edit';  In = @{ file_path = 'tests/a.Tests.ps1'; old_string = 'a'; new_string = 'b' }; Rule = 'path.tests' }
        @{ Name = 'a shell import of a halt-weight module'; Tool = 'Bash';  In = @{ command = 'pwsh -c "Import-Module claude.build.ledger"' }; Rule = 'import.claude-build-ledger' }
    ) {
        $b = Assert-Response -Ok $true -R (Invoke-Core (ConvertTo-Request @{
            op = 'policy.evaluate'; path = (Join-Path $script:RepoRoot 'modules/policy'); tool_name = $Tool; tool_input = $In }))
        $b.result.decision | Should -BeExactly 'deny'
        @($b.result.matched) | Should -Be @($Rule)
        $b.result.haltCount | Should -Be 1
        $b.result.ruleCount | Should -BeGreaterThan 1
    }

    It 'policy.evaluate allows <Name>, and says nothing matched' -ForEach @(
        @{ Name = 'a Write no rule names';                     Tool = 'Write'; In = @{ file_path = 'README.md'; content = 'Do not import Ledger.' } }
        @{ Name = 'a Read of a halt-weight path';              Tool = 'Read';  In = @{ file_path = 'src/x.ps1' } }
        @{ Name = 'a Write outside the project root';          Tool = 'Write'; In = @{ file_path = '../src/x.ps1'; content = 'x' } }
    ) {
        $b = Assert-Response -Ok $true -R (Invoke-Core (ConvertTo-Request @{
            op = 'policy.evaluate'; path = (Join-Path $script:RepoRoot 'modules/policy'); tool_name = $Tool; tool_input = $In }))
        $b.result.decision | Should -BeExactly 'allow'
        @($b.result.matched).Count | Should -Be 0
        $b.result.haltCount | Should -Be 0
    }

    It 'policy.evaluate on a path that is not there carries policy''s ErrorId' {
        $b = Assert-Response -Ok $false -R (Invoke-Core (ConvertTo-Request @{
            op = 'policy.evaluate'; path = (Join-Path $script:Temp 'nowhere'); tool_name = 'Write'; tool_input = @{ file_path = 'x' } }))
        $b.error.code | Should -Match '^Policy'
    }

    It 'policy.evaluate refuses <Name> as bad-request' -ForEach @(
        @{ Name = 'no tool_input';        Stdin = '{"op":"policy.evaluate","path":".","tool_name":"Write"}' }
        @{ Name = 'no tool_name';         Stdin = '{"op":"policy.evaluate","path":".","tool_input":{}}' }
        @{ Name = 'a string tool_input';  Stdin = '{"op":"policy.evaluate","path":".","tool_name":"Write","tool_input":"src/x"}' }
        @{ Name = 'an empty tool_name';   Stdin = '{"op":"policy.evaluate","path":".","tool_name":"","tool_input":{}}' }
    ) {
        (Assert-Response -Ok $false -R (Invoke-Core $Stdin)).error.code | Should -BeExactly 'bad-request'
    }

    It 'plan.validate: a valid plan is valid, and an invalid one is PlanInvalid naming the fault' {
        $ok = Assert-Response -Ok $true -R (Invoke-Core (ConvertTo-Request @{ op = 'plan.validate'; plan = @{ id = 'p'; steps = @('a'); expected_output = 'x' } }))
        $ok.result.valid | Should -BeTrue
        $bad = Assert-Response -Ok $false -R (Invoke-Core (ConvertTo-Request @{ op = 'plan.validate'; plan = @{ id = 'p' } }))
        $bad.error.code | Should -BeExactly 'PlanInvalid'
        $bad.error.message | Should -Match "'steps'"
    }

    It 'refuses <Name> as <Code>' -ForEach @(
        @{ Name = 'text that is not JSON';  Stdin = 'not json';                                 Code = 'bad-request' }
        @{ Name = 'empty stdin';            Stdin = '';                                         Code = 'bad-request' }
        @{ Name = 'a JSON array';           Stdin = '[{"op":"ledger.verify","path":"x"}]';      Code = 'bad-request' }
        @{ Name = 'an unknown op';          Stdin = '{"op":"ledger.delete","path":"x"}';        Code = 'bad-request' }
        @{ Name = 'a missing field';        Stdin = '{"op":"ledger.verify"}';                   Code = 'bad-request' }
        @{ Name = 'a request carrying sig'; Stdin = '{"op":"ledger.verify","path":"x","sig":"s"}'; Code = 'sig-not-implemented' }
    ) {
        (Assert-Response -Ok $false -R (Invoke-Core $Stdin)).error.code | Should -BeExactly $Code
    }
}

Describe 'The request and response schemas' {
    It 'the request schema accepts <_>' -ForEach @(
        '{"op":"ledger.append","path":"c.jsonl","attempt":1,"validator":"v","mode":"m","model":"x","sha256":"abababababababababababababababababababababababababababababababab"}'
        '{"op":"ledger.verify","path":"c.jsonl"}'
        '{"op":"policy.evaluate","path":".","tool_name":"Write","tool_input":{"file_path":"src/x.ps1"}}'
        '{"op":"plan.validate","plan":{"id":"p"}}'
    ) {
        Test-Json -Json $_ -SchemaFile $script:Request | Should -BeTrue
    }

    It 'the request schema rejects <_>' -ForEach @(
        '{"op":"ledger.delete"}'
        '{"op":"ledger.verify"}'
        '{"op":"policy.evaluate","path":"."}'
        '{"op":"policy.evaluate","path":".","tool_name":"Write","tool_input":"src/x.ps1"}'
        '{"op":"ledger.append","path":"c","attempt":1,"validator":"v","mode":"m","model":"x","sha256":"not-hex"}'
        '{"path":"c.jsonl"}'
    ) {
        Test-Json -Json $_ -SchemaFile $script:Request -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'is open for a future sig field: the schema admits it, and Invoke-Core.ps1 refuses it until it is implemented' {
        Test-Json -Json '{"op":"ledger.verify","path":"c.jsonl","sig":"reserved"}' -SchemaFile $script:Request | Should -BeTrue
        (Get-Content -LiteralPath $script:Request -Raw | ConvertFrom-Json).PSObject.Properties.Name | Should -Not -Contain 'additionalProperties'
    }

    It 'the response schema holds a policy.evaluate result to decision, matched, haltCount and ruleCount' {
        Test-Json -Json '{"ok":true,"op":"policy.evaluate","result":{"decision":"deny","matched":["path.src"],"haltCount":1,"ruleCount":14}}' -SchemaFile $script:Response | Should -BeTrue
        Test-Json -Json '{"ok":true,"op":"policy.evaluate","result":{"decision":"maybe","matched":[],"haltCount":0,"ruleCount":1}}' -SchemaFile $script:Response -ErrorAction SilentlyContinue | Should -BeFalse
        # The shape before D013: rules and a count, and no verdict.
        Test-Json -Json '{"ok":true,"op":"policy.evaluate","result":{"ruleCount":1,"haltCount":1,"rules":[]}}' -SchemaFile $script:Response -ErrorAction SilentlyContinue | Should -BeFalse
    }

    It 'the response schema forbids a result and an error together' {
        Test-Json -Json '{"ok":true,"op":"x","result":{},"error":{"code":"c","message":"m"}}' -SchemaFile $script:Response -ErrorAction SilentlyContinue | Should -BeFalse
        Test-Json -Json '{"ok":false,"op":"x"}' -SchemaFile $script:Response -ErrorAction SilentlyContinue | Should -BeFalse
    }
}
