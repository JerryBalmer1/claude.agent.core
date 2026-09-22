#Requires -Version 7.4
<#
    claude.build.policy

    Compiles markdown law into PolicyRule objects.

    One exported function, Get-PolicyRules. It reads AGENTS.md, docs/do-not.md,
    and CLAUDE.md, applies a frozen line heuristic, and emits one PSCustomObject
    per extracted rule.

    v0 is a line heuristic. It is not an LLM and not a markdown AST. It does not
    enforce anything, does not import a sibling module, does not touch the
    network, does not write a receipt, and does not write a file.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# The three files a directory walk reads, in this order. Order is load-bearing:
# rules are deduplicated by Id and the first one wins. No recursion; .git/ and
# src/ are never opened.
$script:SourceFiles = @('AGENTS.md', 'docs/do-not.md', 'CLAUDE.md')

# Pattern 1. A bullet carrying one of these is a law. Matched case-insensitively,
# so a plain-language "- do not import Ledger" in docs/do-not.md is caught too.
$script:LawTokens = @('Do not', "Don't", 'Never', 'MUST', 'must not', 'SHALL NOT')

# Pattern 3. The four repo names are matched whole; a bare Ledger (the module
# name, which is not a repo name) is matched only where it is not the tail of
# claude.build.ledger.
$script:SiblingNames = @(
    'claude.build.ledger',
    'claude.build.fuzzer',
    'claude.build.inspector',
    'claude.build.policy'
)

# Pattern 4. A path token alone is not a rule; the line has to forbid something.
$script:Prohibitions = @('do not edit', 'do not touch', 'do not commit')

$script:ErrorIdTokenPattern = [regex]::new('^[A-Z][A-Za-z]+(NotFound|Bad[A-Z][A-Za-z]+|[A-Z][a-z]+Error)$')
$script:PascalTokenPattern  = [regex]::new('^[A-Z][a-z]+[A-Z][A-Za-z]*$')
$script:WordPattern         = [regex]::new('[A-Za-z][A-Za-z0-9]*')
$script:BareLedgerPattern   = [regex]::new('(?<!claude\.build\.)ledger', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$script:PathTokenPattern    = [regex]::new('(?<![A-Za-z0-9._/-])(?:src|tests|docs|\.ledger|\.claude)/[A-Za-z0-9._/-]*')

# Kind -> Scope. The prompt fixes the allowed values, not the mapping; this one
# is frozen for v0 so a Hash stays stable across runs.
$script:ScopeByKind = @{
    law     = 'repo'
    module  = 'module'
    errorid = 'module'
    path    = 'repo'
}

function Stop-Policy {
    <#
    .SYNOPSIS
        Throws a terminating error with a stable ErrorId through the caller's cmdlet.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory)]
        [ValidateSet('PolicyPathNotFound', 'PolicyBadSource')]
        [string]$ErrorId,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter()]
        [AllowNull()]
        [object]$Target
    )

    $exception = switch ($ErrorId) {
        'PolicyPathNotFound' { [System.IO.FileNotFoundException]::new($Message) }
        'PolicyBadSource'    { [System.FormatException]::new($Message) }
    }

    $category = switch ($ErrorId) {
        'PolicyPathNotFound' { [System.Management.Automation.ErrorCategory]::ObjectNotFound }
        'PolicyBadSource'    { [System.Management.Automation.ErrorCategory]::InvalidData }
    }

    $record = [System.Management.Automation.ErrorRecord]::new($exception, $ErrorId, $category, $Target)
    $Cmdlet.ThrowTerminatingError($record)
}

function Get-PolicySha256Hex {
    <#
    .SYNOPSIS
        SHA-256 of a string's UTF-8 bytes, lowercase hex, no dashes.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Text
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }

    return [System.Convert]::ToHexString($digest).ToLowerInvariant()
}

function Read-PolicyText {
    <#
    .SYNOPSIS
        Reads a file as strict UTF-8 or throws PolicyBadSource.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.PSCmdlet]$Cmdlet,

        [Parameter(Mandatory)]
        [string]$FullPath,

        [Parameter(Mandatory)]
        [string]$Display
    )

    try {
        $bytes = [System.IO.File]::ReadAllBytes($FullPath)
    }
    catch {
        Stop-Policy -Cmdlet $Cmdlet -ErrorId 'PolicyBadSource' -Message "cannot read '$Display': $($_.Exception.Message)" -Target $Display
    }

    # throwOnInvalidBytes: a file that is not UTF-8 text is PolicyBadSource, not
    # a silent run of replacement characters.
    $encoding = [System.Text.UTF8Encoding]::new($false, $true)
    try {
        $text = $encoding.GetString($bytes)
    }
    catch {
        Stop-Policy -Cmdlet $Cmdlet -ErrorId 'PolicyBadSource' -Message "'$Display' is not valid UTF-8 text" -Target $Display
    }

    if ($text.Contains([char]0)) {
        Stop-Policy -Cmdlet $Cmdlet -ErrorId 'PolicyBadSource' -Message "'$Display' contains NUL bytes; not a text source" -Target $Display
    }

    return $text.TrimStart([char]0xFEFF)
}

function New-PolicyRule {
    <#
    .SYNOPSIS
        Builds one PolicyRule. Exactly eight properties, PascalCase, no nesting.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Id,

        [Parameter(Mandatory)]
        [ValidateSet('module', 'path', 'claim', 'verb', 'errorid', 'receipt', 'law')]
        [string]$Kind,

        [Parameter(Mandatory)]
        [string]$Source,

        [Parameter(Mandatory)]
        [string]$Basis,

        [Parameter(Mandatory)]
        [ValidateSet('halt', 'warn', 'log')]
        [string]$Weight,

        [Parameter(Mandatory)]
        [ValidateSet('import', 'write', 'claim', 'execute', 'publish', 'none')]
        [string]$Verb
    )

    $scope = if ($script:ScopeByKind.ContainsKey($Kind)) { $script:ScopeByKind[$Kind] } else { 'repo' }

    # Content hash of the rule. Not a ledger self, not a chain link, linked to
    # nothing. Source is deliberately outside the hash: the same law moving down
    # a file is still the same rule.
    $parts = @($Id, $Kind, $Basis, $Weight, $Verb)
    $hash = Get-PolicySha256Hex -Text ($parts -join '|')

    return [PSCustomObject]@{
        PSTypeName = 'claude.build.policy.PolicyRule'
        Id         = $Id
        Kind       = $Kind
        Scope      = $scope
        Source     = $Source
        Basis      = $Basis
        Weight     = $Weight
        Verb       = $Verb
        Hash       = $hash
    }
}

function Get-PolicyRuleFromLine {
    <#
    .SYNOPSIS
        Applies the four v0 patterns to one line. A line may emit several rules.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line,

        [Parameter(Mandatory)]
        [string]$Source
    )

    $trimmed = $Line.Trim()
    if ($trimmed.Length -eq 0) { return }

    $ci = [System.StringComparison]::OrdinalIgnoreCase

    # ---------------------------------------------------------------- 1. law
    if ($trimmed.StartsWith('- ')) {
        $isLaw = $false
        foreach ($token in $script:LawTokens) {
            if ($trimmed.Contains($token, $ci)) { $isLaw = $true; break }
        }

        if ($isLaw) {
            $id = if ($trimmed.Contains('import', $ci) -and $trimmed.Contains('ledger', $ci)) {
                'law.no-reverse-import'
            }
            else {
                'law.' + (Get-PolicySha256Hex -Text $trimmed).Substring(0, 6)
            }

            New-PolicyRule -Id $id -Kind 'law' -Source $Source -Basis $trimmed -Weight 'halt' -Verb 'none'
        }
    }

    # ------------------------------------------------------------- 2. errorid
    $mentionsErrorId = $trimmed.Contains('ErrorId', [System.StringComparison]::Ordinal)
    $seenTokens = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)

    foreach ($match in $script:WordPattern.Matches($trimmed)) {
        $token = $match.Value
        if (-not $seenTokens.Add($token)) { continue }
        if ($token -ceq 'ErrorId' -or $token -ceq 'ErrorIds') { continue }

        $isErrorId = $script:ErrorIdTokenPattern.IsMatch($token)
        if (-not $isErrorId -and $mentionsErrorId) {
            $isErrorId = $script:PascalTokenPattern.IsMatch($token)
        }

        if ($isErrorId) {
            New-PolicyRule -Id ('errorid.' + $token.ToLowerInvariant()) -Kind 'errorid' -Source $Source -Basis $token -Weight 'log' -Verb 'none'
        }
    }

    # -------------------------------------------------------------- 3. import
    if ($trimmed.Contains('import', $ci)) {
        $named = [System.Collections.Generic.List[string]]::new()
        foreach ($sibling in $script:SiblingNames) {
            if ($trimmed.Contains($sibling, $ci)) { $named.Add($sibling) }
        }
        if ($script:BareLedgerPattern.IsMatch($trimmed)) { $named.Add('Ledger') }

        foreach ($name in $named) {
            $slug = $name.ToLowerInvariant().Replace('.', '-')
            New-PolicyRule -Id ('import.' + $slug) -Kind 'module' -Source $Source -Basis $trimmed -Weight 'halt' -Verb 'import'
        }
    }

    # ---------------------------------------------------------------- 4. path
    $isProhibition = $false
    foreach ($phrase in $script:Prohibitions) {
        if ($trimmed.Contains($phrase, $ci)) { $isProhibition = $true; break }
    }

    if ($isProhibition) {
        $seenPaths = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($match in $script:PathTokenPattern.Matches($trimmed)) {
            $token = $match.Value.TrimEnd('/', '.', ',')
            if ($token.Length -eq 0) { continue }
            if (-not $seenPaths.Add($token)) { continue }

            $slug = $token.TrimStart('.').Replace('/', '.')
            New-PolicyRule -Id ('path.' + $slug) -Kind 'path' -Source $Source -Basis $token -Weight 'halt' -Verb 'write'
        }
    }
}

function Get-PolicyRules {
    <#
    .SYNOPSIS
        Compiles markdown law into PolicyRule objects.

    .DESCRIPTION
        Reads one markdown file, or AGENTS.md / docs/do-not.md / CLAUDE.md at a
        directory root, and emits one PolicyRule per extracted rule.

        A named file that is not present is skipped, not an error. Rules are
        deduplicated by Id across the whole call; the first one wins. An empty
        source emits nothing and does not throw.

        This function reads. It does not enforce, write, or call out.

    .PARAMETER Path
        A markdown file, or a directory root to walk.

    .INPUTS
        System.String. A path, or anything with a FullName property.

    .OUTPUTS
        PSCustomObject with PSTypeName claude.build.policy.PolicyRule and exactly
        eight properties: Id, Kind, Scope, Source, Basis, Weight, Verb, Hash.

    .EXAMPLE
        Get-PolicyRules -Path . | Format-Table Id, Kind, Weight, Source

    .EXAMPLE
        Get-PolicyRules -Path ..\claude.build.ledger\AGENTS.md -Verbose

    .NOTES
        Two ErrorIds: PolicyPathNotFound, PolicyBadSource.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline, ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('FullName')]
        [string]$Path
    )

    process {
        $full = $PSCmdlet.GetUnresolvedProviderPathFromPSPath($Path)
        Write-Verbose "Resolved '$Path' to '$full'"

        $isLeaf      = Test-Path -LiteralPath $full -PathType Leaf
        $isContainer = Test-Path -LiteralPath $full -PathType Container

        if (-not $isLeaf -and -not $isContainer) {
            Stop-Policy -Cmdlet $PSCmdlet -ErrorId 'PolicyPathNotFound' -Message "policy source path not found: $full" -Target $Path
        }

        $targets = [System.Collections.Generic.List[object]]::new()

        if ($isLeaf) {
            $targets.Add([PSCustomObject]@{
                    FullPath = $full
                    Display  = [System.IO.Path]::GetFileName($full)
                })
        }
        else {
            foreach ($relative in $script:SourceFiles) {
                $candidate = Join-Path -Path $full -ChildPath $relative
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    $targets.Add([PSCustomObject]@{
                            FullPath = $candidate
                            Display  = $relative
                        })
                }
                else {
                    Write-Verbose "  skipped '$relative' (not present)"
                }
            }
        }

        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        $emitted = 0

        foreach ($target in $targets) {
            $text = Read-PolicyText -Cmdlet $PSCmdlet -FullPath $target.FullPath -Display $target.Display
            $lines = @($text -split "\r?\n")
            Write-Verbose "  $($target.Display): $($lines.Count) line(s)"

            for ($index = 0; $index -lt $lines.Count; $index++) {
                $source = '{0}:{1}' -f $target.Display, ($index + 1)
                $lineRules = @(Get-PolicyRuleFromLine -Line $lines[$index] -Source $source)

                foreach ($rule in $lineRules) {
                    if (-not $seen.Add($rule.Id)) {
                        Write-Debug "    dropped duplicate Id '$($rule.Id)' at $source"
                        continue
                    }

                    Write-Debug "    $($rule.Kind) '$($rule.Id)' at $source"
                    $emitted++
                    Write-Output $rule
                }
            }
        }

        Write-Verbose "$emitted rule(s) emitted from '$full'"
    }
}

Export-ModuleMember -Function 'Get-PolicyRules'
