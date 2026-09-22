#Requires -Version 7.4

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# The snake lives in Python. This module is the leash.
$script:LedgerPythonDir = Join-Path -Path $PSScriptRoot -ChildPath 'python'
$script:LedgerCli       = Join-Path -Path $script:LedgerPythonDir -ChildPath 'cli.py'
$script:LedgerProtocol  = 1

# Receipts. Anchored to the module's own location so the default path is the same
# file no matter where pwsh was launched from. src/ledger -> repo root.
$script:LedgerRoot        = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..'))
$script:LedgerDefaultPath = Join-Path -Path $script:LedgerRoot -ChildPath '.ledger' -AdditionalChildPath 'ledger.jsonl'
$script:LedgerRecordVersion = 1
$script:LedgerGenesis     = '0' * 64
# The schema, in order. Reordering this is a breaking change to every hash ever written.
#
# Read this before touching either line. These arrays are the *validator's* view of the
# schema: ConvertFrom-LedgerLine uses them to decide whether a line carries exactly the v1
# field set, no more and no fewer. They are NOT what serializes a record.
# ConvertTo-LedgerCanonicalJson writes the seven payload keys out by hand, in literal order,
# because the bytes it produces are the bytes that get hashed and a hashtable's enumeration
# order is not a contract. So the order lives in two places on purpose, and the two must
# agree: change one without the other and the verifier will start accepting records the
# writer cannot produce, or rejecting records it just wrote.
#
# Adding a key here is not a schema extension, it is a break. Every 'self' already on disk
# was computed over exactly these seven fields in exactly this order; an eighth payload key
# changes the canonical bytes of every future record and none of the past ones, and the
# chain stops verifying at the seam. If v2 is ever needed it gets its own payload key set,
# its own canonicalizer, and a version marker - not an edit to this line.
$script:LedgerPayloadKeys = [string[]]@('ts', 'attempt', 'validator', 'mode', 'model', 'sha256', 'prev')
$script:LedgerRecordKeys  = [string[]]@($script:LedgerPayloadKeys + 'self')

# The observer is a sibling repo, not a dependency. It is imported lazily, only under
# -Policy, and never listed in RequiredModules: a machine without it still loads Ledger
# and still forces output. Ledger talks to Inspector; Inspector talks to the policy
# parser. Ledger never imports claude.build.policy.
$script:LedgerInspectorManifest = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $script:LedgerRoot -ChildPath '..' `
        -AdditionalChildPath 'claude.build.inspector', 'src', 'claude.build.inspector', 'claude.build.inspector.psd1'))

function Get-LedgerEventProp {
    <#
    .SYNOPSIS
        StrictMode-safe property read off a ConvertFrom-Json object.
    #>
    param(
        [Parameter(Mandatory)] $Event,
        [Parameter(Mandatory)] [string]$Name,
        $Default = $null
    )
    $prop = $Event.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $Default }
    return $prop.Value
}

function New-LedgerError {
    <#
    .SYNOPSIS
        Build an ErrorRecord. Every ledger failure is terminating; none are swallowed.
    #>
    param(
        [Parameter(Mandatory)] [string]$Message,
        [Parameter(Mandatory)] [string]$Id,
        [System.Management.Automation.ErrorCategory]$Category =
            [System.Management.Automation.ErrorCategory]::InvalidData,
        $Target = $null,
        [System.Exception]$InnerException = $null
    )
    $ex = if ($InnerException) {
        [System.Management.Automation.RuntimeException]::new($Message, $InnerException)
    } else {
        [System.Management.Automation.RuntimeException]::new($Message)
    }
    [System.Management.Automation.ErrorRecord]::new($ex, $Id, $Category, $Target)
}

function ConvertTo-LedgerJsonString {
    <#
    .SYNOPSIS
        RFC 8259 string escaping, done by hand.

    .DESCRIPTION
        Deliberately not ConvertTo-Json. The canonical bytes feed a hash chain, so
        they must be reproducible from any language and immune to serializer
        quirks (escaping policy, unicode handling, whitespace). Minimal escape set:
        quote, backslash, the five short forms, and \uXXXX below 0x20.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Value)

    $sb = [System.Text.StringBuilder]::new($Value.Length + 2)
    [void]$sb.Append('"')
    foreach ($ch in $Value.ToCharArray()) {
        switch ($ch) {
            '"'  { [void]$sb.Append('\"') }
            '\'  { [void]$sb.Append('\\') }
            "`b" { [void]$sb.Append('\b') }
            "`f" { [void]$sb.Append('\f') }
            "`n" { [void]$sb.Append('\n') }
            "`r" { [void]$sb.Append('\r') }
            "`t" { [void]$sb.Append('\t') }
            default {
                if ([int]$ch -lt 0x20) {
                    [void]$sb.AppendFormat(
                        [System.Globalization.CultureInfo]::InvariantCulture, '\u{0:x4}', [int]$ch)
                } else {
                    [void]$sb.Append($ch)
                }
            }
        }
    }
    [void]$sb.Append('"')
    return $sb.ToString()
}

function ConvertTo-LedgerCanonicalJson {
    <#
    .SYNOPSIS
        The exact bytes hashed into 'self'. Key order is the schema, not a hashtable's whim.
        No whitespace. The 'self' field is excluded by construction.
    #>
    param(
        [Parameter(Mandatory)] [string]$Ts,
        [Parameter(Mandatory)] [int]$Attempt,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Validator,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Mode,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Model,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Sha256,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Prev
    )
    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    return '{"ts":'      + (ConvertTo-LedgerJsonString $Ts)        +
           ',"attempt":' + $Attempt.ToString($inv)                 +
           ',"validator":' + (ConvertTo-LedgerJsonString $Validator) +
           ',"mode":'    + (ConvertTo-LedgerJsonString $Mode)      +
           ',"model":'   + (ConvertTo-LedgerJsonString $Model)     +
           ',"sha256":'  + (ConvertTo-LedgerJsonString $Sha256)    +
           ',"prev":'    + (ConvertTo-LedgerJsonString $Prev)      + '}'
}

function Get-LedgerSha256Hex {
    <#
    .SYNOPSIS
        Lowercase hex sha256 of a string's UTF-8 bytes. Same convention as the Python side.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($Text)
    $digest = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [System.Convert]::ToHexString($digest).ToLowerInvariant()
}

function Resolve-LedgerPath {
    <#
    .SYNOPSIS
        Absolute ledger path. Empty means the repo-root default; relative resolves
        against the caller's filesystem location, not the module's.
    #>
    param([AllowEmptyString()] [AllowNull()] [string]$LedgerPath)

    if ([string]::IsNullOrWhiteSpace($LedgerPath)) { return $script:LedgerDefaultPath }
    if ([System.IO.Path]::IsPathRooted($LedgerPath)) {
        return [System.IO.Path]::GetFullPath($LedgerPath)
    }
    $cwd = $ExecutionContext.SessionState.Path.CurrentFileSystemLocation.ProviderPath
    return [System.IO.Path]::GetFullPath((Join-Path -Path $cwd -ChildPath $LedgerPath))
}

function Test-LedgerHex64 {
    <#
    .SYNOPSIS
        64 lowercase hex characters and nothing else.

    .DESCRIPTION
        Anchored with \z, not $. In .NET, '$' also matches immediately before a trailing
        newline, so '^[0-9a-f]{64}$' accepts "aaa...a`n" - a hash with a newline welded to
        it would pass validation and then hash differently. \z is the absolute end of the
        string. -cmatch keeps it case-sensitive: uppercase hex is a different string and
        must not be waved through.
    #>
    param([AllowNull()] $Value)
    return ($Value -is [string]) -and ($Value -cmatch '^[0-9a-f]{64}\z')
}

function ConvertFrom-LedgerLine {
    <#
    .SYNOPSIS
        Parse one ledger line into a validated record, or throw.

    .DESCRIPTION
        Checks JSON well-formedness, that the key set is exactly the eight v1 fields
        (no more, no fewer, no duplicates), field shapes, and that 'self' equals the
        sha256 of this record's own canonical payload. Chain linkage is the caller's job.

        Uses System.Text.Json rather than ConvertFrom-Json on purpose. ConvertFrom-Json
        infers types and turns an ISO-8601 'ts' into a [datetime]; re-stringifying that
        would not reproduce the original bytes and every hash would fail. The verifier
        has to see exactly the characters that were hashed.
    #>
    param(
        [Parameter(Mandatory)] [string]$Line,
        [Parameter(Mandatory)] [int]$Number,
        [Parameter(Mandatory)] [string]$Path
    )

    $doc = $null
    try {
        $doc = [System.Text.Json.JsonDocument]::Parse($Line)
    }
    catch {
        throw (New-LedgerError -Message "line ${Number}: not valid JSON - $($_.Exception.Message)" `
            -Id 'LedgerCorruptLine' -Target $Path -InnerException $_.Exception)
    }

    try {
        $root = $doc.RootElement
        if ($root.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) {
            throw (New-LedgerError -Message "line ${Number}: expected a JSON object, got $($root.ValueKind)" `
                -Id 'LedgerCorruptLine' -Target $Path)
        }

        $actual = [System.Collections.Generic.List[string]]::new()
        foreach ($prop in $root.EnumerateObject()) { $actual.Add($prop.Name) }

        $missing = @($script:LedgerRecordKeys | Where-Object { $_ -notin $actual })
        $extra   = @($actual | Where-Object { $_ -notin $script:LedgerRecordKeys })
        if ($missing.Count -or $extra.Count -or $actual.Count -ne $script:LedgerRecordKeys.Count) {
            $detail = @()
            if ($missing.Count) { $detail += "missing: $($missing -join ', ')" }
            if ($extra.Count)   { $detail += "unexpected: $($extra -join ', ')" }
            if (-not $detail.Count) { $detail += "duplicate keys: $($actual.Count) for $($script:LedgerRecordKeys.Count) fields" }
            throw (New-LedgerError -Message "line ${Number}: field set is not v1 ($($detail -join '; '))" `
                -Id 'LedgerBadRecord' -Target $Path)
        }

        $value = @{}
        foreach ($field in @('ts', 'validator', 'mode', 'model', 'sha256', 'prev', 'self')) {
            $el = $root.GetProperty($field)
            if ($el.ValueKind -ne [System.Text.Json.JsonValueKind]::String) {
                throw (New-LedgerError -Message "line ${Number}: '$field' must be a JSON string, got $($el.ValueKind)" `
                    -Id 'LedgerBadRecord' -Target $Path)
            }
            $value[$field] = $el.GetString()
        }

        foreach ($field in @('sha256', 'prev', 'self')) {
            if (-not (Test-LedgerHex64 $value[$field])) {
                throw (New-LedgerError -Message "line ${Number}: '$field' is not 64 lowercase hex chars" `
                    -Id 'LedgerBadRecord' -Target $Path)
            }
        }
        if ([string]::IsNullOrWhiteSpace($value['ts'])) {
            throw (New-LedgerError -Message "line ${Number}: 'ts' must be a non-empty string" `
                -Id 'LedgerBadRecord' -Target $Path)
        }

        $attemptEl = $root.GetProperty('attempt')
        if ($attemptEl.ValueKind -ne [System.Text.Json.JsonValueKind]::Number) {
            throw (New-LedgerError -Message "line ${Number}: 'attempt' must be a JSON number, got $($attemptEl.ValueKind)" `
                -Id 'LedgerBadRecord' -Target $Path)
        }
        $attempt = 0
        if (-not $attemptEl.TryGetInt32([ref]$attempt)) {
            throw (New-LedgerError -Message "line ${Number}: 'attempt' must be a 32-bit integer" `
                -Id 'LedgerBadRecord' -Target $Path)
        }

        $canonical = ConvertTo-LedgerCanonicalJson -Ts $value['ts'] -Attempt $attempt `
            -Validator $value['validator'] -Mode $value['mode'] -Model $value['model'] `
            -Sha256 $value['sha256'] -Prev $value['prev']
        $computed = Get-LedgerSha256Hex -Text $canonical

        if ($computed -ne $value['self']) {
            throw (New-LedgerError -Message (
                "line ${Number}: record was tampered with. self says $($value['self']), " +
                "payload hashes to $computed") -Id 'LedgerBadSelf' -Target $Path)
        }

        return [pscustomobject]@{
            PSTypeName = 'Ledger.Entry'
            Line       = $Number
            Ts         = $value['ts']
            Attempt    = $attempt
            Validator  = $value['validator']
            Mode       = $value['mode']
            Model      = $value['model']
            Sha256     = $value['sha256']
            Prev       = $value['prev']
            Self       = $value['self']
        }
    }
    finally { $doc.Dispose() }
}

function Add-LedgerRecord {
    <#
    .SYNOPSIS
        Append exactly one receipt line. Append only: never rewrite, insert or sort.

    .DESCRIPTION
        Opens the file once with FileShare.None and holds it across both the
        tail read (to learn 'prev') and the write, so link-and-append is a single
        critical section. UTF-8 without BOM, LF terminator.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [int]$Attempt,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Validator,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Mode,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Model,
        [Parameter(Mandatory)] [AllowEmptyString()] [string]$Sha256
    )

    if (-not (Test-LedgerHex64 $Sha256)) {
        throw (New-LedgerError -Message "refusing to record a malformed output hash: '$Sha256'" `
            -Id 'LedgerBadRecord' -Target $Path)
    }

    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        Write-Verbose "[ledger] creating $dir"
        [void](New-Item -ItemType Directory -Path $dir -Force)
    }

    $utf8 = [System.Text.UTF8Encoding]::new($false)   # no BOM, ever
    $fs   = $null
    $try  = 0
    $maxTries = 10

    while ($true) {
        $try++
        try {
            $fs = [System.IO.FileStream]::new(
                $Path,
                [System.IO.FileMode]::OpenOrCreate,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None)
            break
        }
        catch [System.IO.IOException] {
            if ($try -ge $maxTries) { throw }
            Write-Debug "[ledger] ledger busy, retry $try/$maxTries"
            Start-Sleep -Milliseconds (25 * $try)
        }
    }

    try {
        $prev  = $script:LedgerGenesis
        $count = 0

        if ($fs.Length -gt 0) {
            $fs.Position = 0
            $reader = [System.IO.StreamReader]::new($fs, $utf8, $false, 4096, $true)
            try {
                $lastSelf = $null
                while ($null -ne ($line = $reader.ReadLine())) {
                    if ([string]::IsNullOrWhiteSpace($line)) { continue }
                    $count++
                    # Same strict parser as the verifier: no type inference anywhere
                    # near the bytes that feed the chain.
                    $doc = [System.Text.Json.JsonDocument]::Parse($line)
                    try { $lastSelf = $doc.RootElement.GetProperty('self').GetString() }
                    finally { $doc.Dispose() }
                }
                if (-not [string]::IsNullOrWhiteSpace($lastSelf)) { $prev = $lastSelf }
            }
            finally { $reader.Dispose() }

            # A hand-truncated tail must not get this record glued onto it.
            $fs.Position = $fs.Length - 1
            if ($fs.ReadByte() -ne 0x0A) {
                Write-Warning "[ledger] $Path did not end with a newline; terminating it before append"
                $fs.Position = $fs.Length
                $fs.Write([byte[]]@(0x0A), 0, 1)
            }
        }

        Write-Debug "[ledger] existing records: $count, prev=$prev"

        $ts = [DateTime]::UtcNow.ToString(
            'yyyy-MM-ddTHH:mm:ss.fffZ', [System.Globalization.CultureInfo]::InvariantCulture)
        $canonical = ConvertTo-LedgerCanonicalJson -Ts $ts -Attempt $Attempt -Validator $Validator `
            -Mode $Mode -Model $Model -Sha256 $Sha256 -Prev $prev
        $self = Get-LedgerSha256Hex -Text $canonical

        # Splice 'self' in as the final key: the payload minus its closing brace.
        $record = $canonical.Substring(0, $canonical.Length - 1) +
                  ',"self":' + (ConvertTo-LedgerJsonString $self) + '}'

        Write-Debug "[ledger] canonical: $canonical"
        Write-Debug "[ledger] record:    $record"

        $bytes = $utf8.GetBytes($record + "`n")   # LF. Always LF.
        $fs.Position = $fs.Length
        $fs.Write($bytes, 0, $bytes.Length)
        $fs.Flush($true)

        return [pscustomobject]@{
            PSTypeName = 'Ledger.Receipt'
            Path       = $Path
            Line       = $count + 1
            Ts         = $ts
            Prev       = $prev
            Self       = $self
            Record     = $record
        }
    }
    finally {
        if ($fs) { $fs.Dispose() }
    }
}

function Resolve-LedgerInspector {
    <#
    .SYNOPSIS
        Find the optional claude.build.inspector module. Returns the command and the
        manifest that supplied it, or $null.

    .DESCRIPTION
        First hit wins:
          1. an Invoke-ClaudeInspector already loaded in this session,
          2. the sibling manifest next to this repo.

        Nothing here throws. A missing Inspector is not an error: the caller carries on
        exactly as it does without -Policy. Ledger deliberately owns no fail-open path
        for a missing *policy* module - that belongs to Inspector and is already there.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $cmd = Get-Command -Name 'Invoke-ClaudeInspector' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($cmd) {
        $from = if ($cmd.Module -and $cmd.Module.Path) { $cmd.Module.Path } else { '(loaded)' }
        Write-Debug "[ledger] inspector already loaded from $from"
        return [pscustomobject]@{ Command = $cmd; ManifestPath = $from }
    }

    if (-not (Test-Path -LiteralPath $script:LedgerInspectorManifest -PathType Leaf)) {
        Write-Debug "[ledger] no inspector manifest at $script:LedgerInspectorManifest"
        return $null
    }

    try {
        Import-Module -Name $script:LedgerInspectorManifest -ErrorAction Stop -Verbose:$false
    }
    catch {
        Write-Debug "[ledger] inspector manifest failed to import: $($_.Exception.Message)"
        return $null
    }

    $cmd = Get-Command -Name 'Invoke-ClaudeInspector' -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $cmd) { return $null }
    return [pscustomobject]@{ Command = $cmd; ManifestPath = $script:LedgerInspectorManifest }
}

function Invoke-LedgerForce {
    <#
    .SYNOPSIS
        Force a model response through a validator, retrying until it passes or the cap is hit.

    .DESCRIPTION
        Spawns src/ledger/python/cli.py as a subprocess. Scalar knobs go on argv,
        the prompt goes over stdin as JSON. Python answers with NDJSON events which
        are mapped onto Write-Verbose / Write-Debug / Write-Warning / Write-Error.
        A non-zero Python exit becomes a terminating PowerShell error. Nothing is swallowed.

    .PARAMETER Mode
        dry-run uses a scripted mock transport: no API key, no network, no tokens.
        live calls the real API and requires ANTHROPIC_API_KEY.

    .PARAMETER Model
        The model name that goes on the snake's command line and into the receipt.

        The result event echoes a model back. If you named one here, the echo must match it
        exactly or the force raises LedgerResultMismatch. If you did not, no comparison is
        made and the receipt records this parameter's default - the value PowerShell actually
        asked for - and never the snake's echo. A receipt that named a model nobody requested
        would be a claim this module cannot stand behind.

        mode and validator are held to the same standard and have no exemption: an echo that
        differs from the invocation raises LedgerResultMismatch. Comparison is case-sensitive.
        attempts is not checked at all - see the note on it in the body.

    .PARAMETER Policy
        Off by default. Ask the sibling claude.build.inspector what this project's written
        law says before running the snake, and attach PolicyEvaluated, PolicyRuleCount,
        PolicySourceCount and PolicyHaltCount to the result. Exactly one inspect, before
        Python is spawned. A missing Inspector is not an error: the force behaves as if
        -Policy were absent. A missing policy module is Inspector's fail-open, not Ledger's.

        PolicySourceCount is how many law files Inspector actually read. Zero with
        PolicyEvaluated true means the project has no law left - deleted or blanked - and
        the force warns. It does not throw: -Halt fires on law that was broken, not on law
        that was never written.

    .PARAMETER Halt
        Requires -Policy; on its own it raises LedgerBadSettings. Passes -Halt through to
        Inspector so a halt-weight finding raises InspectorPolicyHalt. That error is not
        wrapped and not caught: it terminates the force before any model call and before
        any receipt is written.

    .PARAMETER PolicyPath
        Directory Inspector evaluates under -Policy. Defaults to this repo's root.
        Passing it without -Policy raises LedgerBadSettings.

    .EXAMPLE
        Invoke-LedgerForce -Prompt 'Write add(a, b).' -Validator has_function_def -Verbose

    .EXAMPLE
        # -PolicyPath is spelled out on purpose. Left off, -Policy inspects this repo's own
        # root, and this repo's settings.json allows Bash(...), which its own written law
        # forbids - so the bare example reports halt findings about the project you are
        # reading. Aim it at the project you actually mean.
        Invoke-LedgerForce -Prompt 'Write add(a, b).' -Policy -PolicyPath 'C:\projects\my-app' -Verbose

    .EXAMPLE
        # Same reason, and here it matters more: pointed at this repo, -Halt throws
        # InspectorPolicyHalt before the snake runs and the example looks broken.
        Invoke-LedgerForce -Prompt 'Write add(a, b).' -Policy -Halt -PolicyPath 'C:\projects\my-app'
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory, Position = 0)]
        [ValidateNotNullOrEmpty()]
        [string]$Prompt,

        # Keep in sync with validators.names() in validators.py
        [ValidateSet('contains', 'has_function_def', 'is_json', 'matches', 'non_empty')]
        [string]$Validator = 'has_function_def',

        [string]$ValidatorArg,

        [ValidateRange(1, 20)]
        [int]$MaxRetries = 5,

        [ValidateNotNullOrEmpty()]
        [string]$Model = 'claude-sonnet-4-5',

        [string]$System,

        [ValidateSet('dry-run', 'live')]
        [string]$Mode = 'dry-run',

        # Scripted responses for dry-run. The last one repeats once the script runs out.
        [string[]]$MockResponse,

        [ValidateRange(1, 200000)]
        [int]$MaxTokens = 4096,

        [ValidateRange(0, 60)]
        [double]$BaseDelay = 1.0,

        [ValidateNotNullOrEmpty()]
        [string]$PythonPath = 'python',

        # Receipt file. Default: .ledger/ledger.jsonl under the repo root.
        [string]$LedgerPath,

        # Accept the output without recording it. Use sparingly; the chain is the point.
        [switch]$SkipLedger,

        # Opt in to a single Inspector policy evaluation before the snake runs.
        [switch]$Policy,

        # Requires -Policy. Let a halt-weight finding terminate the force.
        [switch]$Halt,

        # What Inspector looks at under -Policy. Default: this repo's root.
        [string]$PolicyPath
    )

    # Parameter law first, before Python, before the key check, before anything is spawned.
    if ($Halt -and -not $Policy) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    '-Halt requires -Policy. Without -Policy nothing is evaluated, so there is nothing to halt on.'),
                'LedgerBadSettings',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                'Halt'))
    }
    if ($PSBoundParameters.ContainsKey('PolicyPath') -and -not $Policy) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.ArgumentException]::new(
                    '-PolicyPath requires -Policy. On its own it would be a silent no-op.'),
                'LedgerBadSettings',
                [System.Management.Automation.ErrorCategory]::InvalidArgument,
                'PolicyPath'))
    }

    # One inspect, never two, and it happens here: a halt must stop the force before a
    # model is called and before a receipt is written. InspectorPolicyHalt is deliberately
    # not caught and not wrapped - it keeps its own ErrorId all the way up.
    $policyEvaluated   = $false
    $policyRuleCount   = 0
    $policySourceCount = 0
    $policyHaltCount   = 0
    $policyTarget      = ''

    if ($Policy) {
        $policyTarget = if ([string]::IsNullOrWhiteSpace($PolicyPath)) {
            $script:LedgerRoot
        } else {
            $PolicyPath
        }
        Write-Verbose "[ledger] policy: inspecting $policyTarget"

        $inspector = Resolve-LedgerInspector
        if ($null -eq $inspector) {
            Write-Warning ("[ledger] policy: claude.build.inspector not found at " +
                "$script:LedgerInspectorManifest; continuing as if -Policy were absent")
        }
        else {
            Write-Verbose "[ledger] policy: inspector from $($inspector.ManifestPath)"
            $report = @(& $inspector.Command -Path $policyTarget -Policy -Halt:$Halt |
                Where-Object { $_.Scope -eq 'Project' }) | Select-Object -First 1

            if ($null -eq $report) {
                Write-Warning '[ledger] policy: inspector returned no Project report'
            }
            else {
                $policyEvaluated = [bool]$report.PolicyEvaluated
                $policyRuleCount = [int]$report.PolicyRuleCount
                $policyHaltCount = [int]$report.PolicyHaltCount
                # Read defensively. Inspector is resolved from disk at call time, so the one
                # next door may predate PolicySourceCount; under StrictMode a direct read of
                # a missing property is a terminating error, and a force must not die
                # because the observer is a version behind.
                $policySourceCount = [int](Get-LedgerEventProp $report 'PolicySourceCount' 0)
                Write-Verbose ('[ledger] policy: evaluated={0} sources={1} rules={2} halts={3}' -f
                    $policyEvaluated, $policySourceCount, $policyRuleCount, $policyHaltCount)
                if ($policyEvaluated -and $policySourceCount -eq 0) {
                    Write-Warning ("[ledger] policy: $policyTarget has no law sources; " +
                        'evaluated nothing, so -Halt cannot fire. This is not a clean project.')
                }
                foreach ($finding in @($report.Findings)) { Write-Debug "[inspector] $finding" }
            }
        }
    }

    $exe = Get-Command -Name $PythonPath -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if (-not $exe) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    "Python not found on PATH as '$PythonPath'. The snake starves."),
                'LedgerPythonMissing',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $PythonPath))
    }
    Write-Verbose "[ledger] python: $($exe.Source)"

    if (-not (Test-Path -LiteralPath $script:LedgerCli)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.IO.FileNotFoundException]::new(
                    "Snake CLI not found at $script:LedgerCli"),
                'LedgerCliMissing',
                [System.Management.Automation.ErrorCategory]::ObjectNotFound,
                $script:LedgerCli))
    }

    if ($Mode -eq 'live' -and [string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Security.Authentication.AuthenticationException]::new(
                    'ANTHROPIC_API_KEY is not set. Set it or use -Mode dry-run. No key will be invented.'),
                'LedgerMissingApiKey',
                [System.Management.Automation.ErrorCategory]::AuthenticationError,
                'ANTHROPIC_API_KEY'))
    }

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $pyArgs = @(
        $script:LedgerCli
        '--protocol',    $script:LedgerProtocol.ToString($inv)
        '--mode',        $Mode
        '--model',       $Model
        '--max-retries', $MaxRetries.ToString($inv)
        '--validator',   $Validator
        '--max-tokens',  $MaxTokens.ToString($inv)
        '--base-delay',  $BaseDelay.ToString($inv)
    )
    if ($PSBoundParameters.ContainsKey('ValidatorArg')) {
        $pyArgs += @('--validator-arg', $ValidatorArg)
    }

    $payload = [ordered]@{ prompt = $Prompt }
    if ($PSBoundParameters.ContainsKey('System'))       { $payload['system'] = $System }
    if ($PSBoundParameters.ContainsKey('MockResponse')) { $payload['mock']   = @{ responses = @($MockResponse) } }
    $json = $payload | ConvertTo-Json -Depth 6 -Compress

    Write-Verbose "[ledger] mode=$Mode validator=$Validator max-retries=$MaxRetries model=$Model"
    Write-Debug   "[ledger] argv: $($pyArgs -join ' ')"
    Write-Debug   "[ledger] stdin payload: $json"

    $state = [pscustomobject]@{
        Result = $null
        Errors = [System.Collections.Generic.List[string]]::new()
        Raw    = [System.Collections.Generic.List[string]]::new()
    }

    $savedPythonPath   = $env:PYTHONPATH
    $savedIoEncoding   = $env:PYTHONIOENCODING
    $savedUnbuffered   = $env:PYTHONUNBUFFERED
    $savedConsoleOut   = [Console]::OutputEncoding
    $OutputEncoding    = [System.Text.UTF8Encoding]::new($false)

    try {
        $env:PYTHONPATH = if ([string]::IsNullOrEmpty($savedPythonPath)) {
            $script:LedgerPythonDir
        } else {
            $script:LedgerPythonDir + [System.IO.Path]::PathSeparator + $savedPythonPath
        }
        $env:PYTHONIOENCODING = 'utf-8'
        $env:PYTHONUNBUFFERED = '1'
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        Write-Debug "[ledger] PYTHONPATH=$env:PYTHONPATH"

        $json | & $exe.Source @pyArgs 2>&1 | ForEach-Object {
            $line = if ($_ -is [System.Management.Automation.ErrorRecord]) { $_.ToString() } else { [string]$_ }
            if ([string]::IsNullOrWhiteSpace($line)) { return }

            $evt = $null
            try { $evt = $line | ConvertFrom-Json -ErrorAction Stop } catch { $evt = $null }
            if ($null -eq $evt -or $null -eq (Get-LedgerEventProp $evt 'type')) {
                $state.Raw.Add($line)
                Write-Verbose "[py-raw] $line"
                return
            }

            switch (Get-LedgerEventProp $evt 'type') {
                'log' {
                    $level = [string](Get-LedgerEventProp $evt 'level' 'verbose')
                    $msg   = [string](Get-LedgerEventProp $evt 'msg' '')
                    $data  = Get-LedgerEventProp $evt 'data'
                    $text  = "[snake] $msg"
                    if ($null -ne $data) { $text += ' ' + ($data | ConvertTo-Json -Depth 4 -Compress) }
                    switch ($level) {
                        'debug' { Write-Debug   $text }
                        'warn'  { Write-Warning $text }
                        'error' {
                            $state.Errors.Add($msg)
                            Write-Error -Message $text -ErrorAction Continue
                        }
                        default { Write-Verbose $text }
                    }
                }
                'attempt' {
                    Write-Verbose ("[snake] --- attempt {0}/{1} ---" -f
                        (Get-LedgerEventProp $evt 'n'), (Get-LedgerEventProp $evt 'of'))
                }
                'validation' {
                    $verdict = if (Get-LedgerEventProp $evt 'ok' $false) { 'VALID' } else { 'INVALID' }
                    Write-Verbose ("[snake] attempt {0}: {1} - {2}" -f
                        (Get-LedgerEventProp $evt 'attempt'), $verdict,
                        (Get-LedgerEventProp $evt 'reason' ''))
                }
                'result' {
                    $state.Result = $evt
                    Write-Debug "[ledger] result event received"
                }
                'error' {
                    $code = [string](Get-LedgerEventProp $evt 'code' 'SNAKE')
                    $msg  = [string](Get-LedgerEventProp $evt 'msg' '')
                    $state.Errors.Add("${code}: $msg")
                    Write-Error -Message "[snake] ${code}: $msg" -ErrorAction Continue
                }
                default {
                    Write-Debug "[ledger] unhandled event: $line"
                }
            }
        }
    }
    catch {
        $inner    = $_.Exception
        $exitCode = if ($inner.PSObject.Properties['ExitCode']) { $inner.ExitCode } else { $LASTEXITCODE }
        $detail   = if ($state.Errors.Count) { $state.Errors -join ' | ' } else { $inner.Message }
        if ($state.Raw.Count) { $detail += ' || raw: ' + ($state.Raw -join ' / ') }

        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Management.Automation.RuntimeException]::new(
                    "Snake failed with exit code ${exitCode}: $detail", $inner),
                'LedgerSnakeFailed',
                [System.Management.Automation.ErrorCategory]::OperationStopped,
                $script:LedgerCli))
    }
    finally {
        $env:PYTHONPATH           = $savedPythonPath
        $env:PYTHONIOENCODING     = $savedIoEncoding
        $env:PYTHONUNBUFFERED     = $savedUnbuffered
        [Console]::OutputEncoding = $savedConsoleOut
    }

    if ($null -eq $state.Result) {
        $PSCmdlet.ThrowTerminatingError(
            [System.Management.Automation.ErrorRecord]::new(
                [System.Management.Automation.RuntimeException]::new(
                    'Snake exited 0 but emitted no result event. Contract violated.'),
                'LedgerNoResult',
                [System.Management.Automation.ErrorCategory]::ProtocolError,
                $script:LedgerCli))
    }

    $r = $state.Result
    $result = [pscustomobject]@{
        PSTypeName = 'Ledger.ForceResult'
        Output     = [string](Get-LedgerEventProp $r 'output' '')
        Attempts   = [int](Get-LedgerEventProp $r 'attempts' 0)
        Sha256     = [string](Get-LedgerEventProp $r 'sha256' '')
        Validator  = [string](Get-LedgerEventProp $r 'validator' $Validator)
        Reason     = [string](Get-LedgerEventProp $r 'reason' '')
        Model      = [string](Get-LedgerEventProp $r 'model' $Model)
        Mode       = [string](Get-LedgerEventProp $r 'mode' $Mode)
        LedgerPath = $null
        LedgerSelf = $null
        # Additive, always present, and false/0 when -Policy was not passed. These do not
        # reach the receipt: the on-disk record is schema v1, exactly eight keys, and the
        # hash of every line already written depends on that set staying frozen.
        # PolicySourceCount is no exception - it is a ninth field here and never a ninth key there.
        PolicyEvaluated   = $policyEvaluated
        PolicyRuleCount   = $policyRuleCount
        PolicySourceCount = $policySourceCount
        PolicyHaltCount   = $policyHaltCount
        PolicyPath        = $policyTarget
    }

    # The result event echoes back the mode, validator and model the snake was told to use.
    # PowerShell asked for those values on the command line, so it does not accept a different
    # answer: an event that disagrees with its own invocation is a stale process, the wrong
    # process, or a stub, and none of the three may be described by a receipt. Identity of the
    # run is checked before integrity of the payload - there is no point rehashing output that
    # did not come from the run that was requested.
    #
    # Comparison is -cne, case-sensitive, for the same reason the chain's hex is: 'dry-run' and
    # 'Dry-Run' are different strings, and the record is a literal one.
    #
    # A field the event omits is not a mismatch. A snake that says nothing is not claiming
    # anything, and the invocation's own value stands.
    #
    # 'attempts' is deliberately NOT checked. PowerShell never saw the retry loop - it read one
    # summary line after the fact - so it cannot attest to a count it did not observe. The
    # receipt records the number the snake reported, and that is the limit of the claim.
    $echoChecks = [System.Collections.Generic.List[hashtable]]::new()
    $echoChecks.Add(@{ Field = 'mode';      Asked = $Mode;      Echoed = (Get-LedgerEventProp $r 'mode' $null) })
    $echoChecks.Add(@{ Field = 'validator'; Asked = $Validator; Echoed = (Get-LedgerEventProp $r 'validator' $null) })

    # -Model is the one field with an exemption, and it is deliberate. When the caller names a
    # model, that name is a requirement and an echo that differs is a mismatch. When the caller
    # does not, there is nothing to hold the snake to: the default below is what PowerShell put
    # on the command line, and the receipt records *that* - never the snake's echo. A stub, or a
    # transport that resolves an alias to some other id, does not get to name the model in a
    # record nobody asked it to name.
    $modelAsked = $PSBoundParameters.ContainsKey('Model')
    if ($modelAsked) {
        $echoChecks.Add(@{ Field = 'model'; Asked = $Model; Echoed = (Get-LedgerEventProp $r 'model' $null) })
    }

    foreach ($echo in $echoChecks) {
        if ($null -eq $echo.Echoed) { continue }
        if ([string]$echo.Echoed -cne [string]$echo.Asked) {
            $PSCmdlet.ThrowTerminatingError(
                (New-LedgerError -Message (
                    "The snake's result disagrees with its own invocation: $($echo.Field) was asked " +
                    "for as '$($echo.Asked)' and came back as '$($echo.Echoed)'. Refusing to record a " +
                    'receipt that describes a run nobody requested.') `
                    -Id 'LedgerResultMismatch' `
                    -Category ([System.Management.Automation.ErrorCategory]::InvalidResult) `
                    -Target $result))
        }
    }

    if (-not $modelAsked) { $result.Model = $Model }
    Write-Debug "[ledger] result echo agrees: mode=$($result.Mode) validator=$($result.Validator) model=$($result.Model)"

    # The snake reports a hash. PowerShell does not take its word for it: the receipt is a
    # claim about *this* text, so the writer hashes the text it actually holds and refuses
    # to sign anything it cannot reproduce. Python hashes text.encode("utf-8") in snake.py;
    # Get-LedgerSha256Hex hashes UTF8.GetBytes of the same string, so agreement is the
    # normal case and disagreement means the output and its hash parted company somewhere
    # between the validator and here - a truncated pipe, an encoding slip, a tampered event.
    #
    # This runs before -SkipLedger returns, not just before the append. A hash that does not
    # match its output is wrong whether or not anyone was going to write it down.
    #
    # -cne, not -ne. Get-LedgerSha256Hex returns lowercase hex and so does snake.py, so an
    # uppercase digest is a different string from one of them - and the chain is case-sensitive
    # all the way down: Test-LedgerHex64 matches with -cmatch and Get-LedgerVerify rejects
    # uppercase hex outright. A case-insensitive compare here would wave through a digest that
    # is honest about the bytes and wrong about the encoding, and hand it to a writer that must
    # then refuse it. Disagree at the gate, not at the file handle.
    $recomputed = Get-LedgerSha256Hex -Text $result.Output
    Write-Debug "[ledger] snake sha256: $($result.Sha256)"
    Write-Debug "[ledger] local sha256: $recomputed"

    if ($recomputed -cne $result.Sha256) {
        $PSCmdlet.ThrowTerminatingError(
            (New-LedgerError -Message (
                "The snake's hash does not match its own output. Reported $($result.Sha256), " +
                "the accepted text hashes to $recomputed. Refusing to record a receipt for " +
                'output this module cannot reproduce.') `
                -Id 'LedgerOutputHashMismatch' `
                -Category ([System.Management.Automation.ErrorCategory]::InvalidData) `
                -Target $result))
    }
    Write-Verbose "[ledger] output hash agrees with the snake ($($recomputed.Substring(0, 12))...)"

    if ($SkipLedger) {
        Write-Verbose '[ledger] -SkipLedger: output accepted, no receipt written'
        return $result
    }

    $target = Resolve-LedgerPath -LedgerPath $LedgerPath
    Write-Verbose "[ledger] appending receipt to $target"
    try {
        $receipt = Add-LedgerRecord -Path $target `
            -Attempt   $result.Attempts `
            -Validator $result.Validator `
            -Mode      $result.Mode `
            -Model     $result.Model `
            -Sha256    $result.Sha256
    }
    catch {
        # A receipt that silently fails to land defeats the whole point of the file.
        # The accepted output rides along on TargetObject so it is not lost.
        $PSCmdlet.ThrowTerminatingError(
            (New-LedgerError -Message (
                "Output was accepted but its receipt could not be appended to ${target}: " +
                $_.Exception.Message) `
                -Id 'LedgerAppendFailed' `
                -Category ([System.Management.Automation.ErrorCategory]::WriteError) `
                -Target $result -InnerException $_.Exception))
    }

    $result.LedgerPath = $receipt.Path
    $result.LedgerSelf = $receipt.Self
    Write-Verbose ("[ledger] receipt #{0}: prev={1}... self={2}..." -f
        $receipt.Line, $receipt.Prev.Substring(0, 12), $receipt.Self.Substring(0, 12))

    return $result
}

function Get-LedgerVerify {
    <#
    .SYNOPSIS
        Walk the receipt file and prove the hash chain is intact.

    .DESCRIPTION
        For every line: valid JSON, exactly the eight v1 fields, well-formed hashes,
        'self' equal to the sha256 of that record's canonical payload, and 'prev'
        equal to the previous line's 'self' (64 zeros on line 1). Any break is a
        terminating error, so a returned object always means Ok.

    .EXAMPLE
        Get-LedgerVerify -Verbose
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$LedgerPath
    )

    $target = Resolve-LedgerPath -LedgerPath $LedgerPath
    Write-Verbose "[ledger] verifying $target"

    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        $PSCmdlet.ThrowTerminatingError(
            (New-LedgerError -Message "No ledger at $target. Nothing to verify." `
                -Id 'LedgerFileMissing' `
                -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound) `
                -Target $target))
    }

    $expectedPrev = $script:LedgerGenesis
    $count   = 0
    $firstTs = $null
    $lastTs  = $null
    $lastSelf = $null
    $number  = 0

    $reader = [System.IO.StreamReader]::new(
        $target, [System.Text.UTF8Encoding]::new($false), $true)
    try {
        while ($null -ne ($line = $reader.ReadLine())) {
            $number++
            if ([string]::IsNullOrWhiteSpace($line)) {
                Write-Debug "[ledger] line ${number}: blank, skipped"
                continue
            }

            try {
                $entry = ConvertFrom-LedgerLine -Line $line -Number $number -Path $target
            }
            catch {
                # $_ in a catch is already an ErrorRecord; rethrow it as-is.
                $PSCmdlet.ThrowTerminatingError($_)
            }

            if ($entry.Prev -ne $expectedPrev) {
                $PSCmdlet.ThrowTerminatingError(
                    (New-LedgerError -Message (
                        "Chain broken at line ${number}: prev is $($entry.Prev) but the " +
                        "previous record's self is $expectedPrev") `
                        -Id 'LedgerBrokenChain' -Target $target))
            }

            $count++
            if ($null -eq $firstTs) { $firstTs = $entry.Ts }
            $lastTs       = $entry.Ts
            $lastSelf     = $entry.Self
            $expectedPrev = $entry.Self
            Write-Debug "[ledger] line ${number}: ok, self=$($entry.Self)"
        }
    }
    finally { $reader.Dispose() }

    Write-Verbose "[ledger] $count record(s) verified, chain intact"

    return [pscustomobject]@{
        PSTypeName = 'Ledger.VerifyResult'
        Path       = $target
        Count      = $count
        Ok         = $true
        FirstTs    = $firstTs
        LastTs     = $lastTs
        LastSelf   = $lastSelf
    }
}

function Get-LedgerEntry {
    <#
    .SYNOPSIS
        Read receipt lines as objects, oldest first.

    .DESCRIPTION
        Returns the last -Last records in file order. -Last 0 returns everything.
        Each line is validated on the way out, so a corrupt record throws rather
        than being handed back as data.

    .EXAMPLE
        Get-LedgerEntry -Last 2 | Format-Table Line, Ts, Attempt, Sha256
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Position = 0)]
        [string]$LedgerPath,

        [ValidateRange(0, 100000)]
        [int]$Last = 10
    )

    $target = Resolve-LedgerPath -LedgerPath $LedgerPath
    Write-Verbose "[ledger] reading $target (last $Last)"

    if (-not (Test-Path -LiteralPath $target -PathType Leaf)) {
        $PSCmdlet.ThrowTerminatingError(
            (New-LedgerError -Message "No ledger at $target. Nothing to read." `
                -Id 'LedgerFileMissing' `
                -Category ([System.Management.Automation.ErrorCategory]::ObjectNotFound) `
                -Target $target))
    }

    $lines   = [System.IO.File]::ReadAllLines($target, [System.Text.UTF8Encoding]::new($false))
    $records = [System.Collections.Generic.List[object]]::new()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ([string]::IsNullOrWhiteSpace($lines[$i])) { continue }
        $records.Add([pscustomobject]@{ Number = $i + 1; Text = $lines[$i] })
    }

    $selected = if ($Last -le 0) { $records } else { $records | Select-Object -Last $Last }

    foreach ($item in $selected) {
        try {
            ConvertFrom-LedgerLine -Line $item.Text -Number $item.Number -Path $target
        }
        catch {
            $PSCmdlet.ThrowTerminatingError($_)
        }
    }
}

function Get-LedgerStatus {
    <#
    .SYNOPSIS
        Report where the snake lives and whether it can run.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param()

    $exe = Get-Command -Name 'python' -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    Write-Verbose "[ledger] probing snake at $script:LedgerCli"

    [pscustomobject]@{
        PSTypeName    = 'Ledger.Status'
        Protocol      = $script:LedgerProtocol
        SnakeCli      = $script:LedgerCli
        SnakePresent  = Test-Path -LiteralPath $script:LedgerCli
        Python        = if ($exe) { $exe.Source } else { $null }
        ApiKeyPresent = -not [string]::IsNullOrWhiteSpace($env:ANTHROPIC_API_KEY)
        PSVersion     = $PSVersionTable.PSVersion.ToString()
    }
}

New-Alias -Name 'ledger-force' -Value 'Invoke-LedgerForce' -Force

Export-ModuleMember -Function 'Invoke-LedgerForce', 'Get-LedgerStatus',
    'Get-LedgerVerify', 'Get-LedgerEntry' -Alias 'ledger-force'
