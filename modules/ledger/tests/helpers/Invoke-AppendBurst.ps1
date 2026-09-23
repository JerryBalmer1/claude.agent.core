#Requires -Version 7.4
<#
.SYNOPSIS
    Append N receipts to one ledger from this process, as fast as it can. Run several of
    these at once against the same file to put the writer's lock under real contention.

.DESCRIPTION
    A separate FILE rather than a string the suite builds at run time, for two reasons.

    The first is that AGENTS.md bans heredocs, and a script assembled inside a test is a
    heredoc wearing a PowerShell hat -- it is not reviewable, it is not covered by
    `requires-header`, and a syntax error in it surfaces as a child exit code rather than
    as a parse failure anyone can see.

    The second is that the thing under test is a CROSS-PROCESS lock. Add-LedgerRecord opens
    the chain with FileShare.None and holds that one handle across both the tail read (to
    learn `prev`) and the append, so link-and-append is a single critical section. A
    same-process runspace would exercise .NET's share-mode bookkeeping; separate `pwsh`
    processes exercise the operating system's, which is the claim the module actually
    makes. Slower, and the only version of the test that means anything.

    Every record carries a sha256 derived from -Tag and the iteration number, so the
    caller can prove that every record it asked for arrived exactly once. A writer that
    loses an append under contention, or writes one twice, shows up as a missing or
    duplicated hash rather than as a count that happens to add up.

    Exit 0 when every append landed. Non-zero, with the failure on stderr, otherwise.

.EXAMPLE
    pwsh -NoProfile -File Invoke-AppendBurst.ps1 -ManifestPath ../../ledger.psd1 `
        -LedgerPath /tmp/burst.jsonl -Count 5 -Tag a
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string]$ManifestPath,
    [Parameter(Mandatory)] [string]$LedgerPath,
    [Parameter(Mandatory)] [ValidateRange(1, 1000)] [int]$Count,
    [Parameter(Mandatory)] [string]$Tag
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

Import-Module -Name $ManifestPath -Force -ErrorAction Stop
$mod = Get-Module -Name 'ledger'
if ($null -eq $mod) { throw "Invoke-AppendBurst: the ledger module did not load from $ManifestPath" }

# Add-LedgerRecord was private when this helper was written; it is exported now, for the
# sentinel in claude.agent.images rather than for this suite. The append path is still reached
# through Invoke-LedgerForce in normal use, and this still calls the writer in the module's own
# scope, which is how the suite tests it without spawning Python once per record. Calling it as
# a public command here would test the export rather than the cross-process lock.
$append = {
    param([string]$Path, [int]$Attempt, [string]$Sha)
    Add-LedgerRecord -Path $Path -Attempt $Attempt -Validator 'burst' `
        -Mode 'dry-run' -Model 'burst' -Sha256 $Sha
}

for ($i = 1; $i -le $Count; $i++) {
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes("$Tag-$i")
    $sha    = [System.Convert]::ToHexString(
        [System.Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    $null = & $mod $append $LedgerPath $i $sha
}

Write-Host "burst '$Tag': $Count record(s) appended"
exit 0
