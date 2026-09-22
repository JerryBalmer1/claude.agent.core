@{
    RootModule        = 'plans.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = '2815856d-3e00-443d-8cc5-29eddb1fec38'
    Author            = 'JerryBalmer1'
    Copyright         = '(c) 2026 JerryBalmer1. All rights reserved.'
    Description       = 'Schema-reading validator for plan objects. Two exported functions. Test-PlanStructure validates a plan against schemas/plan.schema.json and throws naming the first fault: every property in the schema''s required list must be present and non-null, a string property must be a non-blank string, and an array property must be an array meeting minItems whose entries match items.type. Get-PlanSchemaPath returns the schema it reads. It implements that subset of JSON Schema and no more -- no additionalProperties, no nested object shapes, no pattern, no enum -- so it says nothing about the shape of a step, and it does not run plans.'
    PowerShellVersion = '7.4'

    FunctionsToExport = @('Get-PlanSchemaPath', 'Test-PlanStructure')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('Claude', 'ClaudeCode', 'Plans', 'Validator', 'Contract')
            LicenseUri = ''
            ProjectUri = ''
        }
    }
}
