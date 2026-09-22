#Requires -Version 7.4
<#
.SYNOPSIS
    Compiles this module's own law and prints one line per rule.

.DESCRIPTION
    Imports the module from ../policy.psd1 and runs Get-PolicyRules against the
    module root, which walks AGENTS.md, docs/do-not.md, and CLAUDE.md for
    whichever of them are there. Nothing is written. Nothing is enforced.

    FIXED IN PHASE 7, FINDINGS F24. As copied from claude.build.policy this
    script reached for ../src/claude.build.policy/claude.build.policy.psd1 --
    a path that never existed in substrate, so the example could not be run at
    all. Two things had moved: the src/<repo-name>/ nesting is gone, and the
    manifest was renamed to policy.psd1 in Phase 5 (F47). The import is now one
    hop up from this file, which is where the manifest actually is.

.EXAMPLE
    pwsh -NoProfile -File examples/parse-here.ps1

.EXAMPLE
    pwsh -NoProfile -File examples/parse-here.ps1 -Verbose
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$repoRoot = Split-Path -Parent $PSScriptRoot
$manifest = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath 'policy.psd1'

Write-Verbose "Importing $manifest"
Import-Module -Name $manifest -Force

Write-Verbose "Parsing $repoRoot"
$rules = @(Get-PolicyRules -Path $repoRoot)

foreach ($rule in $rules) {
    Write-Output ('Id={0} Kind={1} Weight={2} Source={3}' -f $rule.Id, $rule.Kind, $rule.Weight, $rule.Source)
}

Write-Output "$($rules.Count) rule(s)"

exit 0
