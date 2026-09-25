#Requires -Version 7.4
<#
    Judges one tool call against PolicyRule objects: allow or deny (F96, D013).

    policy.psm1 compiles markdown law into rules and is still the byte-identical copy
    (scripts/verify.ps1 pins its blob), so the judgement lives here and the parser is not touched.
    This file is the manifest's RootModule and policy.psm1 its NestedModule, the other way round
    would not work: policy.psm1 calls Export-ModuleMember for Get-PolicyRules alone, and a root that
    does that exports nothing a nested module brings. This file calls no Export-ModuleMember, so
    the manifest's FunctionsToExport is the one list of what is public, and the two helpers below
    are not on it.

    A rule can match only through its Verb, because the Verb is the only part of a rule that says
    what kind of action it forbids:

      write   A path rule (path.<slug>, Basis a repo-relative path). Matches a structured write
              tool - Write, Edit, MultiEdit, NotebookEdit - whose file_path or notebook_path is
              that path or under it, relative to the project root. A path outside the root is not
              the project's to judge.
      import  A module rule (import.<slug>). Matches when a line of CODE the action carries names
              the module on the same line as an import keyword. Code is a shell tool's command
              (Bash, PowerShell), or what a write tool puts into a .ps1/.psm1/.psd1/.py file. A
              markdown file that says "do not import Ledger" is the law, not an import.
      none    Law and errorid rules. Nothing an action carries can be matched against a sentence,
              so they never match. They are counted in RuleCount and nowhere else.

    Deny when any matched rule is halt-weight. No match is allow; D013 records that choice. What
    this does not see is a shell command that writes a file: `Set-Content src/x` is text, and
    v0 does not parse shell. D013 names it.

    Nothing here writes, imports a sibling module or touches the network.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$script:WriteTools     = @('Write', 'Edit', 'MultiEdit', 'NotebookEdit')
$script:ShellTools     = @('Bash', 'PowerShell')
$script:CodeExtensions = @('.ps1', '.psm1', '.psd1', '.py')
$script:ImportKeyword  = [regex]::new('\b(Import-Module|ipmo|using\s+module|import|require)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)

function Get-ToolField {
    # One field of tool_input, from a dictionary or a parsed JSON object; $null when absent.
    param([AllowNull()]$ToolInput, [Parameter(Mandatory)][string]$Name)
    if ($null -eq $ToolInput) { return $null }
    if ($ToolInput -is [System.Collections.IDictionary]) {
        if ($ToolInput.Contains($Name)) { return $ToolInput[$Name] }
        return $null
    }
    $p = $ToolInput.PSObject.Properties[$Name]
    if ($p) { return $p.Value }
    return $null
}

function ConvertTo-ProjectPath {
    # A written path as a forward-slash path relative to the root, or $null when it is outside.
    param([Parameter(Mandatory)][string]$Root, [Parameter(Mandatory)][string]$Path)
    $full = if ([System.IO.Path]::IsPathRooted($Path)) { [System.IO.Path]::GetFullPath($Path) }
            else { [System.IO.Path]::GetFullPath((Join-Path $Root $Path)) }
    $rel = [System.IO.Path]::GetRelativePath($Root, $full).Replace('\', '/')
    if ($rel -eq '..' -or $rel.StartsWith('../') -or [System.IO.Path]::IsPathRooted($rel)) { return $null }
    return $rel
}

function Test-PolicyAction {
    <#
    .SYNOPSIS
        Judges one tool call against PolicyRule objects and returns allow or deny.

    .DESCRIPTION
        Returns Decision (allow|deny), Matched (the matched rule ids, in rule order), HaltCount
        (how many matched rules are halt-weight) and RuleCount (how many rules were judged).
        Deny when HaltCount is above zero. See the module header for what each Verb matches.

    .PARAMETER Rule
        PolicyRule objects, as Get-PolicyRules emits them. An empty set allows everything.

    .PARAMETER Root
        The project root the rules were read from. Written paths are judged relative to it.

    .EXAMPLE
        Test-PolicyAction -Rule (Get-PolicyRules -Path .) -Root . -ToolName Write -ToolInput @{ file_path = 'src/x.ps1'; content = '' }
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Rule,
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ToolName,
        [AllowNull()]$ToolInput
    )

    # Through the provider: GetFullPath alone resolves a relative root against the process's
    # directory, which is not the session's location.
    $rootFull = [System.IO.Path]::GetFullPath($PSCmdlet.GetUnresolvedProviderPathFromPSPath($Root))
    $ci = [System.StringComparison]::OrdinalIgnoreCase

    $written = [System.Collections.Generic.List[string]]::new()
    $code = [System.Collections.Generic.List[string]]::new()

    if ($script:WriteTools -contains $ToolName) {
        $isCode = $false
        foreach ($field in 'file_path', 'notebook_path') {
            $p = Get-ToolField $ToolInput $field
            if ($p -isnot [string] -or $p.Length -eq 0) { continue }
            if ($script:CodeExtensions -contains [System.IO.Path]::GetExtension($p).ToLowerInvariant()) { $isCode = $true }
            $rel = ConvertTo-ProjectPath -Root $rootFull -Path $p
            if ($null -ne $rel) { $written.Add($rel) }
        }
        if ($isCode) {
            foreach ($field in 'content', 'new_string', 'new_source') {
                $t = Get-ToolField $ToolInput $field
                if ($t -is [string]) { $code.Add($t) }
            }
            foreach ($e in @(Get-ToolField $ToolInput 'edits')) {
                $t = Get-ToolField $e 'new_string'
                if ($t -is [string]) { $code.Add($t) }
            }
        }
    }
    elseif ($script:ShellTools -contains $ToolName) {
        $t = Get-ToolField $ToolInput 'command'
        if ($t -is [string]) { $code.Add($t) }
    }

    $importLines = @(foreach ($t in $code) { $t -split '\r?\n' | Where-Object { $script:ImportKeyword.IsMatch($_) } })

    $matched = @(foreach ($r in $Rule) {
        switch ($r.Verb) {
            'write' {
                $basis = $r.Basis.Replace('\', '/').Trim('/')
                if ($r.Kind -ne 'path' -or $basis.Length -eq 0) { break }
                foreach ($w in $written) {
                    if ($w.Equals($basis, $ci) -or $w.StartsWith("$basis/", $ci)) { $r; break }
                }
            }
            'import' {
                if (-not $r.Id.StartsWith('import.')) { break }
                # The slug is the module name lowercased with dots as dashes; either spelling matches.
                $slug = $r.Id.Substring('import.'.Length)
                $name = [regex]::new('(?<![A-Za-z0-9_.-])' + ([regex]::Escape($slug) -replace '\\?-', '[.-]') + '(?![A-Za-z0-9_-])',
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                foreach ($l in $importLines) {
                    if ($name.IsMatch($l)) { $r; break }
                }
            }
        }
    })

    $halt = @($matched | Where-Object { $_.Weight -eq 'halt' }).Count
    [PSCustomObject]@{
        PSTypeName = 'claude.agent.core.PolicyDecision'
        Decision   = if ($halt -gt 0) { 'deny' } else { 'allow' }
        Matched    = [string[]]@($matched | ForEach-Object { $_.Id })
        HaltCount  = $halt
        RuleCount  = $Rule.Count
    }
}

