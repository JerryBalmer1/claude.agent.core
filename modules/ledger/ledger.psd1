@{
    RootModule        = 'ledger.psm1'
    ModuleVersion     = '0.2.0'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Jerry + Grok'
    CompanyName       = 'Chaos Engineering'
    Description       = 'Forces Claude to comply. The snake wrapper.'
    PowerShellVersion = '7.4'
    FunctionsToExport = @('Invoke-LedgerForce', 'Get-LedgerStatus', 'Get-LedgerVerify', 'Get-LedgerEntry')
    CmdletsToExport   = @()
    VariablesToExport = '*'
    AliasesToExport   = @('ledger-force')
    # Python 3.10+ required for the snake engine
    # Install: pip install -r requirements.txt
}
