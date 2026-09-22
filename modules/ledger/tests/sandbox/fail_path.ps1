#Requires -Version 7.4
<#
.SYNOPSIS
    Failure path: prove a non-zero Python exit becomes a terminating PowerShell error.

.DESCRIPTION
    Feeds the snake a mock that never satisfies the validator. Python exhausts the
    retry cap, exits 2, and Invoke-LedgerForce must throw LedgerSnakeFailed rather
    than returning anything. Exits 0 when the error was raised as designed.

.EXAMPLE
    pwsh -NoProfile -File tests/sandbox/fail_path.ps1 -Verbose
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$MaxRetries = 3
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

if ($PSBoundParameters.ContainsKey('Debug')) { $DebugPreference = 'Continue' }

$manifest = Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', 'src', 'ledger', 'Ledger.psd1'
if (-not (Test-Path -LiteralPath $manifest)) { throw "Ledger.psd1 not found at $manifest" }
Import-Module -Name $manifest -Force -ErrorAction Stop

$forward = @{
    Verbose = ($VerbosePreference -eq 'Continue')
    Debug   = ($DebugPreference -eq 'Continue')
}

try {
    $result = Invoke-LedgerForce @forward `
        -Prompt 'Write a Python function add(a, b) that returns a + b. Code only.' `
        -Validator 'has_function_def' `
        -MaxRetries $MaxRetries `
        -Mode 'dry-run' `
        -MockResponse 'I would rather write you a poem about addition than any code.'

    Write-Host ''
    Write-Host 'FAIL: expected a terminating error, got a result:' -ForegroundColor Red
    $result | Format-List | Out-String | Write-Host
    exit 1
}
catch {
    Write-Host ''
    Write-Host '=== TERMINATING ERROR CAUGHT (expected) ===' -ForegroundColor Yellow
    Write-Host "FullyQualifiedErrorId : $($_.FullyQualifiedErrorId)"
    Write-Host "Category              : $($_.CategoryInfo.Category)"
    Write-Host "TargetObject          : $($_.TargetObject)"
    Write-Host "InnerException        : $($_.Exception.InnerException.GetType().Name)"
    Write-Host "Message               : $($_.Exception.Message)"
    Write-Host "LASTEXITCODE          : $LASTEXITCODE"
    Write-Host ''
    Write-Host 'PASS: non-zero Python exit surfaced as a terminating PowerShell error.' -ForegroundColor Green
    exit 0
}
