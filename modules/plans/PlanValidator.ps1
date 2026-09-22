#Requires -Version 7.4

<#
    PlanValidator.ps1 — the plan contract, enforced.

    tests/plan.failfirst.ps1 called Test-PlanStructure when no such function
    existed anywhere in the repo, and build/tasks/Plan.build.ps1 then treated
    the resulting "command not found" as proof that the fail-first discipline
    was working. It was not proof of anything: a test that calls a function
    that does not exist fails identically whether the contract is right,
    wrong, or absent. This is the implementation, so the tests can fail for
    reasons about plans.

    The rules are read from schemas/plan.schema.json rather than restated
    here. Two copies of a contract is one copy of a contract plus a bug.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PlanSchemaPath {
    [CmdletBinding()]
    [OutputType([string])]
    param()
    return [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..' 'schemas' 'plan.schema.json'))
}

function Test-PlanStructure {
    <#
    .SYNOPSIS
        Validate a plan against schemas/plan.schema.json. Throws on invalid.

    .DESCRIPTION
        Returns $true for a valid plan and throws a terminating error naming
        the first thing wrong for an invalid one. It throws rather than
        returning $false because a plan that does not validate must not be
        capable of being ignored by a caller who forgot to check a boolean.

    .PARAMETER Plan
        A hashtable or PSCustomObject. JSON text is not accepted: parsing is
        the caller's business and a parse failure is not a contract failure.

    .EXAMPLE
        Test-PlanStructure -Plan @{ id = 'x'; steps = @('a'); expected_output = 'y' }

    .EXAMPLE
        Get-Content plan.json -Raw | ConvertFrom-Json | Test-PlanStructure -Verbose
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [ValidateNotNull()]
        $Plan,

        [Parameter()]
        [ValidateNotNullOrEmpty()]
        [string]$SchemaPath = (Get-PlanSchemaPath)
    )

    process {
        if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
            throw "plan schema missing: $SchemaPath"
        }

        Write-Verbose "[plan] validating against $SchemaPath"
        $schema = Get-Content -LiteralPath $SchemaPath -Raw -Encoding utf8 | ConvertFrom-Json -Depth 100

        # Flatten both shapes into one lookup, so a plan read from JSON and a
        # plan built as a hashtable in a test are held to the same contract.
        #
        # This is a hashtable and not a `$get = { ... }` scriptblock on purpose.
        # `return $Plan[$Name]` from a scriptblock puts the value on the
        # pipeline, which ENUMERATES it: a one-element array comes back as its
        # single element, so skills_to_build = @('one') would arrive here as a
        # string and be rejected for not being an array. Assigning into a
        # hashtable does not enumerate.
        $names = if ($Plan -is [System.Collections.IDictionary]) {
            [string[]]@($Plan.Keys)
        }
        else {
            [string[]]@($Plan.PSObject.Properties.Name)
        }

        # Branch with statements, not with `$values[$n] = if (...) { ... }`.
        # An `if` used as an expression yields its value through the pipeline,
        # which enumerates it just as a scriptblock's return does: @('one')
        # arrives as 'one' and @() arrives as $null. Only the plain assignment
        # inside each branch preserves the array.
        $values = @{}
        foreach ($n in $names) {
            if ($Plan -is [System.Collections.IDictionary]) {
                $values[$n] = $Plan[$n]
            }
            else {
                $values[$n] = $Plan.$n
            }
        }

        foreach ($required in @($schema.required)) {
            if ($names -notcontains $required) {
                throw "plan is missing required property '$required'"
            }
            if ($null -eq $values[$required]) {
                throw "plan property '$required' is null"
            }
        }

        foreach ($name in $names) {
            if ($schema.properties.PSObject.Properties.Name -notcontains $name) {
                Write-Verbose "[plan] '$name' is not in the schema; ignored"
                continue
            }
            $rule = $schema.properties.$name
            $value = $values[$name]
            if ($null -eq $value) { continue }

            switch ($rule.type) {
                'string' {
                    if ($value -isnot [string]) {
                        throw "plan property '$name' must be a string, got $($value.GetType().Name)"
                    }
                    if ([string]::IsNullOrWhiteSpace($value)) {
                        throw "plan property '$name' must not be empty"
                    }
                }
                'array' {
                    # A single item from JSON arrives unwrapped, so wrap before
                    # counting rather than rejecting a one-step plan.
                    $items = @($value)
                    if ($value -is [string]) {
                        throw "plan property '$name' must be an array, got a string"
                    }
                    $min = if ($rule.PSObject.Properties.Name -contains 'minItems') { [int]$rule.minItems } else { 0 }
                    if ($items.Count -lt $min) {
                        throw "plan property '$name' needs at least $min item(s), got $($items.Count)"
                    }
                    if ($rule.PSObject.Properties.Name -contains 'items' -and
                        $rule.items.PSObject.Properties.Name -contains 'type' -and
                        $rule.items.type -eq 'string') {
                        foreach ($item in $items) {
                            if ($item -isnot [string]) {
                                throw "plan property '$name' must contain only strings"
                            }
                        }
                    }
                }
                default {
                    Write-Verbose "[plan] no type rule for '$name'"
                }
            }
        }

        Write-Verbose '[plan] valid'
        return $true
    }
}
