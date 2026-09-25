@{
    RootModule        = 'evaluate.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'c1724298-272c-47d5-acc6-df9004e3161e'
    Author            = 'JerryBalmer1'
    Copyright         = '(c) 2026 JerryBalmer1. All rights reserved.'
    Description       = 'Compiles markdown law into PolicyRule objects, and judges one tool call against them. Get-PolicyRules reads AGENTS.md, docs/do-not.md, and CLAUDE.md and emits one content-hashed rule per extracted line; Test-PolicyAction returns allow or deny for a tool call. No OPA, no network, no receipts, nothing written.'
    PowerShellVersion = '7.4'

    NestedModules     = @('policy.psm1')
    FunctionsToExport = @('Get-PolicyRules', 'Test-PolicyAction')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData       = @{
        PSData = @{
            Tags       = @('Claude', 'ClaudeCode', 'Policy', 'Rules', 'Markdown', 'Parser')
            LicenseUri = ''
            ProjectUri = ''
        }
    }
}
