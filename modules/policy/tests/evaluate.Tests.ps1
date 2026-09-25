#Requires -Version 7.4
<#
    Test-PolicyAction: one tool call judged against PolicyRule objects (F96, D013).

    The law is this module's own docs/do-not.md, the file policy.Tests.ps1 already uses as a
    fixture. It compiles to halt-weight path.src and path.tests (verb write), import.ledger and
    three import.claude-build-* rules (verb import), and law rules with verb none.

    Separate from policy.Tests.ps1 on purpose: that file is the ten ported checks, one It each,
    and holds its count to the port.
#>

BeforeAll {
    $script:ModuleRoot = Split-Path $PSScriptRoot -Parent
    Import-Module (Join-Path $script:ModuleRoot 'policy.psd1') -Force
    $script:Rules = @(Get-PolicyRules -Path $script:ModuleRoot)

    function script:Judge([string]$Tool, $In) {
        Test-PolicyAction -Rule $script:Rules -Root $script:ModuleRoot -ToolName $Tool -ToolInput $In
    }
}

Describe 'Test-PolicyAction' -Tag 'policy' {

    It 'the law under test carries the rules these cases rely on' {
        # The precondition. If do-not.md stopped compiling to these, every deny below would be
        # an allow for a reason that has nothing to do with the evaluator.
        $ids = @($script:Rules | ForEach-Object Id)
        foreach ($id in 'path.src', 'path.tests', 'import.ledger', 'import.claude-build-fuzzer') { $ids | Should -Contain $id }
        @($script:Rules | Where-Object Verb -eq 'none').Count | Should -BeGreaterThan 0
    }

    It 'denies <Name>' -ForEach @(
        @{ Name = 'a Write to src/';                         Tool = 'Write';        In = @{ file_path = 'src/x.ps1'; content = 'x' };                 Rule = 'path.src' }
        @{ Name = 'a Write to src itself';                   Tool = 'Write';        In = @{ file_path = 'src'; content = 'x' };                       Rule = 'path.src' }
        @{ Name = 'an Edit to tests/ by absolute path';      Tool = 'Edit';         In = @{ file_path = '<root>/tests/a.ps1'; new_string = 'y' };     Rule = 'path.tests' }
        @{ Name = 'a NotebookEdit under src/';               Tool = 'NotebookEdit'; In = @{ notebook_path = 'src/n.ipynb'; new_source = 'x' };        Rule = 'path.src' }
        @{ Name = 'a Bash import through a module path';     Tool = 'Bash';         In = @{ command = 'pwsh -c Import-Module ./modules/ledger/ledger.psd1' }; Rule = 'import.ledger' }
        @{ Name = 'a PowerShell import by dotted name';      Tool = 'PowerShell';   In = @{ command = 'Import-Module claude.build.ledger' };          Rule = 'import.claude-build-ledger' }
        @{ Name = 'an import written into a .ps1 file';      Tool = 'Write';        In = @{ file_path = 'tools/a.ps1'; content = "`$x = 1`nImport-Module Ledger" }; Rule = 'import.ledger' }
        @{ Name = 'a MultiEdit that adds a python import';   Tool = 'MultiEdit';    In = @{ file_path = 'x.py'; edits = @(@{ old_string = 'a'; new_string = 'from claude.build.fuzzer import x' }) }; Rule = 'import.claude-build-fuzzer' }
    ) {
        if ($In.Contains('file_path')) { $In.file_path = $In.file_path.Replace('<root>', $script:ModuleRoot) }
        $d = Judge $Tool $In
        $d.Decision | Should -BeExactly 'deny'
        @($d.Matched) | Should -Be @($Rule)
        $d.HaltCount | Should -Be 1
        $d.RuleCount | Should -Be $script:Rules.Count
    }

    It 'allows <Name>' -ForEach @(
        @{ Name = 'a Write no rule names';                      Tool = 'Write'; In = @{ file_path = 'README.md'; content = 'x' } }
        @{ Name = 'a markdown file that states the import law'; Tool = 'Write'; In = @{ file_path = 'docs/do-not.md'; content = '- Do not import Ledger.' } }
        @{ Name = 'a Read of src/';                             Tool = 'Read';  In = @{ file_path = 'src/x.ps1' } }
        @{ Name = 'a Bash command that only reads src/';        Tool = 'Bash';  In = @{ command = 'git log -- src/' } }
        @{ Name = 'a path that only starts with src';           Tool = 'Write'; In = @{ file_path = 'srcx/y.ps1'; content = 'y' } }
        @{ Name = 'a path that climbs out of the root';         Tool = 'Write'; In = @{ file_path = '../src/x.ps1'; content = 'y' } }
        @{ Name = 'an absolute path outside the root';          Tool = 'Write'; In = @{ file_path = '<outside>'; content = 'y' } }
        @{ Name = 'a tool with no input';                       Tool = 'Write'; In = $null }
    ) {
        if ($In -and $In.Contains('file_path') -and $In.file_path -eq '<outside>') { $In.file_path = Join-Path ([System.IO.Path]::GetTempPath()) 'elsewhere/src/x.ps1' }
        $d = Judge $Tool $In
        $d.Decision | Should -BeExactly 'allow'
        @($d.Matched).Count | Should -Be 0
        $d.HaltCount | Should -Be 0
    }

    It 'allows everything when no rule has a verb an action can match' {
        $lawOnly = @($script:Rules | Where-Object Verb -eq 'none')
        $d = Test-PolicyAction -Rule $lawOnly -Root $script:ModuleRoot -ToolName 'Write' -ToolInput @{ file_path = 'src/x.ps1'; content = 'x' }
        $d.Decision | Should -BeExactly 'allow'
        $d.RuleCount | Should -Be $lawOnly.Count
    }

    It 'lists a matched rule that is not halt-weight, and still allows' {
        $warn = $script:Rules | Where-Object Id -eq 'path.src' | Select-Object -First 1 | ForEach-Object { $_.PSObject.Copy() }
        $warn.Weight = 'warn'
        $d = Test-PolicyAction -Rule @($warn) -Root $script:ModuleRoot -ToolName 'Write' -ToolInput @{ file_path = 'src/x.ps1'; content = 'x' }
        $d.Decision | Should -BeExactly 'allow'
        @($d.Matched) | Should -Be @('path.src')
        $d.HaltCount | Should -Be 0
    }

    It 'judges a relative root from the session location, not the process directory' {
        Push-Location $script:ModuleRoot
        try { (Test-PolicyAction -Rule $script:Rules -Root '.' -ToolName 'Write' -ToolInput @{ file_path = (Join-Path $script:ModuleRoot 'src/x.ps1') }).Decision | Should -BeExactly 'deny' }
        finally { Pop-Location }
    }
}
