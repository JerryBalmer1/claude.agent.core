#Requires -Version 7.4
<#
    scripts/Measure-Baseline.ps1 is retired (DECISIONS D011). The claim is that every call
    refuses, names its reason, and does nothing else. Run in a child pwsh, from a throwaway
    working directory, so "nothing else" can be measured as "nothing appeared".
#>

BeforeAll {
    $script:Script = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts' 'Measure-Baseline.ps1'
    $script:Pwsh = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName

    function script:Invoke-Retired {
        param([string[]]$ScriptArgs = @())
        $work = Join-Path ([System.IO.Path]::GetTempPath()) ('measure-baseline-' + [guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $work -Force
        try {
            $PSNativeCommandUseErrorActionPreference = $false
            Push-Location -LiteralPath $work
            try { $out = (& $script:Pwsh -NoProfile -NonInteractive -File $script:Script @ScriptArgs 2>&1 | Out-String) }
            finally { Pop-Location }
            [pscustomobject]@{
                Exit    = $LASTEXITCODE
                Output  = $out
                Created = @(Get-ChildItem -LiteralPath $work -Recurse -Force)
                Json    = Join-Path $work 'baseline.json'
            }
        }
        finally { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

Describe 'Measure-Baseline.ps1 is retired (D011)' {
    It 'refuses with no arguments: non-zero exit, reason=retired, no prompt' {
        $r = Invoke-Retired
        $r.Exit | Should -Not -Be 0
        $r.Output | Should -Match 'reason=retired'
        $r.Output | Should -Not -Match 'missing mandatory'
    }

    It 'refuses with the full historical argument set, and writes nothing' {
        $r = Invoke-Retired -ScriptArgs @('-ImageBuilderPath', 'x', '-LedgerRepoPath', 'y', '-PolicyRepoPath', 'z',
            '-Json', 'baseline.json', '-Markdown', 'BASELINE.md')
        $r.Exit | Should -Not -Be 0
        $r.Output | Should -Match 'reason=retired'
        $r.Output | Should -Match 'D011'
        $r.Created | Should -BeNullOrEmpty -Because 'a retired script creates no file, not even the -Json it was given'
    }
}
