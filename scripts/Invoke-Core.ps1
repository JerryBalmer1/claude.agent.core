#Requires -Version 7.4
<#
.SYNOPSIS
    Core's four operations as JSON: one request on stdin, one response on stdout, exit 0 or 1.

.DESCRIPTION
    A process boundary for callers that are not PowerShell: an MCP server, a hook, another
    language. The request is one JSON object (schemas/core-request.schema.json) whose `op` is one of

        ledger.append    -> Add-LedgerRecord    path, attempt, validator, mode, model, sha256
        ledger.verify    -> Get-LedgerVerify    path
        policy.evaluate  -> Get-PolicyRules     path: the project whose written law is parsed
        plan.validate    -> Test-PlanStructure  plan: the plan object itself

    and the response is one JSON object (schemas/core-response.schema.json):

        {"ok":true, "op":"...", "result":{...}}                     exit 0
        {"ok":false,"op":"...", "error":{"code":"...","message":"..."}}  exit 1

    NOTHING ELSE GOES TO STDOUT. The modules' own host, verbose, warning and information output
    is discarded while an op runs. The response is written once, with [Console]::Out, after the op
    has finished. A caller parses stdout as exactly one document and does not have to filter it.

    error.code is the module's own ErrorId (LedgerBadSelf, LedgerFileMissing, PolicyPathNotFound,
    ...) when the module raised one. It is bad-request when the request was not a request, and
    sig-not-implemented when the request carries `sig`. The request schema is open so that field can
    be added later, but no signature is verified here, so accepting one would claim a check that
    did not happen.

    policy.evaluate returns the rules and how many are halt-weight. claude.build.policy parses and
    does not enforce, and this op does not pretend otherwise.

    The MCP server that would wrap this is not here.

.EXAMPLE
    '{"op":"ledger.verify","path":"out/chain.jsonl"}' | pwsh -NoProfile -File scripts/Invoke-Core.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

$RepoRoot = Split-Path $PSScriptRoot -Parent
$op = $null

function Send-Response {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Body)
    [Console]::Out.Write((ConvertTo-Json -InputObject $Body -Depth 20 -Compress))
    [Console]::Out.Flush()
    exit $(if ($Body.ok) { 0 } else { 1 })
}

function Send-Error {
    param([Parameter(Mandatory)][string]$Code, [Parameter(Mandatory)][AllowEmptyString()][string]$Message)
    Send-Response ([ordered]@{ ok = $false; op = $op; error = [ordered]@{ code = $Code; message = $Message } })
}

function Get-Field {
    # A required field of the request. Missing or null is a bad request, named.
    param([Parameter(Mandatory)]$Request, [Parameter(Mandatory)][string]$Name)
    if ($Request.PSObject.Properties.Name -notcontains $Name -or $null -eq $Request.$Name) {
        Send-Error 'bad-request' "$op needs '$Name'"
    }
    return $Request.$Name
}

# ---------------------------------------------------------------- the request
$raw = [Console]::In.ReadToEnd()
if ([string]::IsNullOrWhiteSpace($raw) -or -not $raw.TrimStart().StartsWith('{')) {
    Send-Error 'bad-request' 'stdin must be one JSON object'
}
$request = $null
try { $request = $raw | ConvertFrom-Json -Depth 64 }
catch { Send-Error 'bad-request' "stdin is not valid JSON: $($_.Exception.Message)" }

$names = @($request.PSObject.Properties.Name)
if ($names -contains 'op') { $op = [string]$request.op }
if ($names -contains 'sig') { Send-Error 'sig-not-implemented' 'a signed request is not supported yet; nothing here verifies sig' }
if (@('ledger.append', 'ledger.verify', 'policy.evaluate', 'plan.validate') -cnotcontains $op) {
    Send-Error 'bad-request' "unknown op '$op'"
}

# ---------------------------------------------------------------- the op
$module = @{ 'ledger.append' = 'ledger'; 'ledger.verify' = 'ledger'; 'policy.evaluate' = 'policy'; 'plan.validate' = 'plans' }[$op]
Import-Module -Name (Join-Path $RepoRoot 'modules' $module "$module.psd1") -Force

$result = $null
try {
    # Streams 3-6 are discarded: warnings, verbose, debug and host/information output would all
    # reach stdout from pwsh -File, and stdout carries exactly one document.
    $result = & {
        switch ($op) {
            'ledger.append' {
                $r = Add-LedgerRecord -Path (Get-Field $request 'path') -Attempt ([int](Get-Field $request 'attempt')) `
                    -Validator (Get-Field $request 'validator') -Mode (Get-Field $request 'mode') `
                    -Model (Get-Field $request 'model') -Sha256 (Get-Field $request 'sha256')
                [ordered]@{ path = $r.Path; line = $r.Line; ts = $r.Ts; prev = $r.Prev; self = $r.Self }
            }
            'ledger.verify' {
                $v = Get-LedgerVerify -LedgerPath (Get-Field $request 'path')
                [ordered]@{ path = $v.Path; count = $v.Count; verified = [bool]$v.Ok; firstTs = $v.FirstTs; lastTs = $v.LastTs; lastSelf = $v.LastSelf }
            }
            'policy.evaluate' {
                $rules = @(Get-PolicyRules -Path (Get-Field $request 'path'))
                [ordered]@{
                    ruleCount = $rules.Count
                    haltCount = @($rules | Where-Object Weight -eq 'halt').Count
                    rules     = @($rules | ForEach-Object {
                        [ordered]@{ id = $_.Id; kind = $_.Kind; scope = $_.Scope; source = $_.Source; basis = $_.Basis; weight = $_.Weight; verb = $_.Verb; hash = $_.Hash }
                    })
                }
            }
            'plan.validate' {
                $null = Test-PlanStructure -Plan (Get-Field $request 'plan')
                [ordered]@{ valid = $true; schema = [System.IO.Path]::GetRelativePath($RepoRoot, (Get-PlanSchemaPath)).Replace('\', '/') }
            }
        }
    } 3>$null 4>$null 5>$null 6>$null
}
catch {
    # A module that raised an ErrorRecord gave it an id; that id is the code. A bare `throw 'text'`
    # has no id - PowerShell uses the message as FullyQualifiedErrorId - and plans' validator
    # throws that way, one sentence per fault, so its faults are PlanInvalid.
    $id = ([string]$_.FullyQualifiedErrorId -split ',')[0]
    $code = if ($id -and $id -cne $_.Exception.Message) { $id }
            elseif ($op -eq 'plan.validate') { 'PlanInvalid' }
            else { 'op-failed' }
    Send-Error $code $_.Exception.Message
}

if ($op -eq 'ledger.verify' -and -not $result.verified) {
    Send-Error 'LedgerNotVerified' "Get-LedgerVerify returned Ok=false for $($result.path)"
}
Send-Response ([ordered]@{ ok = $true; op = $op; result = $result })
