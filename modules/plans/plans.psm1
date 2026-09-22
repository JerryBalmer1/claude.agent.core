#Requires -Version 7.4
<#
    plans -- the module wrapper around PlanValidator.ps1.

    PlanValidator.ps1 is a BYTE-IDENTICAL copy of claude.pwsh.image.builder's
    src/PlanValidator.ps1 at blob ff7b2baf02aec1765e3c6fdcf72490a5a06d5028, taken from that
    repo's develop at 5f71173 (asserted by tests/plans.Tests.ps1, which recomputes the blob id
    from the bytes on disk). This file dot-sources it. It does not edit it, and it adds no
    validation of its own.

    WHAT CHANGED IN PHASE 7. The previous copy was blob 8e5da768 -- an earlier validator that
    restated the plan rules in PowerShell and never opened the schema. This one reads
    schemas/plan.schema.json and derives its rules from it, which is the whole point of the
    bump: FINDINGS F5 recorded that the module could not honestly claim schema validation, F27
    that -SchemaPath was inert because the copied function had no such parameter, and F28 that
    the caller those findings were measured against lived on a branch this copy did not come
    from. All three are closed by taking the bytes that caller actually calls. F70 has the
    falsification table -- including the two rules that got LOOSER, which the run order did not
    predict and which are not defects in this wrapper.

    WHY THE COPY IS DOT-SOURCED IN A CHILD SCOPE.

    The copy defines Test-PlanStructure, and that is also the name this module exports, so the
    two would collide in module scope. `& { . <path>; ... }` runs the dot-source in a child
    scope and hands back the ScriptBlocks: the copy's definitions never occupy the module's
    function table, and the ScriptBlocks keep this module's session state, so invoking them
    later behaves exactly as dot-sourcing into module scope would have.

    The copy also sets `Set-StrictMode -Version Latest`. Measured: it does not leak out of that
    child scope into this module or into a caller.

    WHY Get-PlanSchemaPath IS RE-IMPLEMENTED HERE AND NOT RE-EXPORTED.

    The copy's own Get-PlanSchemaPath is

        Join-Path $PSScriptRoot '..' 'schemas' 'plan.schema.json'

    which is correct in image.builder, where the validator sits in src/ and the schema sits in
    schemas/ at the repository root. It is WRONG here, and measurably so: this module is
    self-contained, so `..` climbs out of it. Measured on 2026-09-22, the copy's function
    returns

        modules/schemas/plan.schema.json        <- does not exist

    while the schema this module ships is modules/plans/schemas/plan.schema.json. Re-exporting
    the copy's version would export a function that names a file that is not there. So the
    exported Get-PlanSchemaPath is this module's, it resolves against $PSScriptRoot with no
    parent hop, and tests/plans.Tests.ps1 asserts both halves: that the exported function finds
    the real schema, and that the copy's would not. The copy is still not edited.

    -SchemaPath IS NOW READ. It is no longer inert. The wrapper resolves the default and passes
    it through on every call, so the copy's own default -- which would be the broken path above
    -- is never the one that is evaluated. A plan the schema rejects now fails, and a schema
    path that does not exist now throws. Both are asserted by behaviour, not by parameter name.
#>

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$script:ValidatorPath     = Join-Path $PSScriptRoot 'PlanValidator.ps1'
$script:DefaultSchemaPath = Join-Path $PSScriptRoot 'schemas' 'plan.schema.json'

if (-not (Test-Path -LiteralPath $script:ValidatorPath -PathType Leaf)) {
    throw "plans: the copied validator is missing: $script:ValidatorPath"
}

$script:Copied = & {
    . $script:ValidatorPath
    [pscustomobject]@{
        Validate   = ${function:Test-PlanStructure}
        SchemaPath = ${function:Get-PlanSchemaPath}
    }
}

if ($null -eq $script:Copied.Validate) {
    # Measured, not assumed: run order 3.2 said to wrap "the entry function PlanValidator.ps1
    # actually defines -- measure, don't assume its name". It is Test-PlanStructure (F2). If a
    # later copy renames it, this throws at import rather than exporting an empty shell.
    throw "plans: $script:ValidatorPath does not define Test-PlanStructure"
}
if ($null -eq $script:Copied.SchemaPath) {
    # The copy is expected to carry Get-PlanSchemaPath from ff7b2baf onward. It is not called
    # for its answer (see the header), but its absence would mean the copy is an older blob
    # than the manifest claims, and that is worth failing the import over.
    throw "plans: $script:ValidatorPath does not define Get-PlanSchemaPath"
}

function Get-PlanSchemaPath {
    <#
    .SYNOPSIS
        The full path to the schema this module validates against.

    .DESCRIPTION
        modules/plans/schemas/plan.schema.json, resolved from $PSScriptRoot. This is THIS
        module's function, not the copied validator's: the copy resolves '..' out of its own
        directory, which is right in image.builder's layout and wrong in this one. See the
        block comment at the top of plans.psm1, and the It in tests/plans.Tests.ps1 that
        measures both answers side by side.

    .EXAMPLE
        Test-PlanStructure -Plan $p -SchemaPath (Get-PlanSchemaPath)
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return [System.IO.Path]::GetFullPath($script:DefaultSchemaPath)
}

function Test-PlanStructure {
    <#
    .SYNOPSIS
        Validate a plan against the module's plan schema. Returns $true, or throws naming the
        first thing wrong.

    .DESCRIPTION
        A thin pass-through to the copied validator. The checks are entirely the copy's, and
        from Phase 7 they are read out of schemas/plan.schema.json rather than restated in
        PowerShell: every property named in `required` must be present and non-null, a
        `"type": "string"` property must really be a string and non-blank, and a
        `"type": "array"` property must be an array satisfying `minItems` whose entries match
        `items.type` when one is given. A property the schema does not mention is ignored.

        IT IS NOT A FULL JSON SCHEMA VALIDATOR and does not call Test-Json. It reads the subset
        above and nothing else -- no `additionalProperties`, no nested object shapes, no
        `pattern`, no `enum`. Two consequences were measured in Phase 7 and are not defects
        here: a step with no `action` now PASSES, because the schema says nothing about the
        shape of a step, and a BLANK entry in `skills_to_build` now passes too, because the
        empty string is a string. The previous copy rejected both. FINDINGS F70.

    .PARAMETER Plan
        A hashtable or PSCustomObject. JSON text is not accepted; parsing is the caller's job.

    .PARAMETER SchemaPath
        The schema to validate against. Defaults to this module's own, and it IS READ: a plan
        the schema rejects fails, and a path that does not exist throws
        "plan schema missing: <path>". It is passed through explicitly on every call so that
        the copy's own default -- which resolves outside this module -- is never evaluated.

    .EXAMPLE
        Test-PlanStructure -Plan @{ id = 'x'; steps = @(@{ action = 'a' }); expected_output = 'y' }

    .EXAMPLE
        Get-Content plan.json -Raw | ConvertFrom-Json | Test-PlanStructure -Verbose
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [object]$Plan,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SchemaPath
    )

    process {
        $resolved = if ($PSBoundParameters.ContainsKey('SchemaPath')) { $SchemaPath } else { Get-PlanSchemaPath }
        Write-Verbose "[plans] validator: $script:ValidatorPath"
        Write-Verbose "[plans] schema path: $resolved -- read, not decorative"
        return (& $script:Copied.Validate -Plan $Plan -SchemaPath $resolved)
    }
}

Export-ModuleMember -Function 'Test-PlanStructure', 'Get-PlanSchemaPath'
