@{
    RootModule        = 'policy.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'c1724298-272c-47d5-acc6-df9004e3161e'
    Author            = 'JerryBalmer1'
    Copyright         = '(c) 2026 JerryBalmer1. All rights reserved.'
    Description       = 'Compiles markdown law into PolicyRule objects. One exported function reads AGENTS.md, docs/do-not.md, and CLAUDE.md and emits one content-hashed rule per extracted line. No OPA, no enforcement, no network, no receipts, nothing written.'
    PowerShellVersion = '7.4'

    FunctionsToExport = @('Get-PolicyRules')
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
