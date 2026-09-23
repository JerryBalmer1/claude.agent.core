#Requires -Version 7.4
<#
    modules/ledger -- the receipt chain, the module surface around it, and the proof that
    the copy is the copy.

    WHAT THIS SUITE IS FOR. The module is a BYTE-IDENTICAL copy of
    claude.build.ledger@d57938d's src/ledger/Ledger.psm1. "Unchanged in behaviour" is
    therefore not an argument to be made in a README, it is an arithmetic fact about the
    file, and the first Context proves it from the bytes on disk rather than from the
    commit message that claims it. Everything after that tests the chain itself, because
    a hash chain nobody has tried to break is a decoration.

    TEMP PATHS. [System.IO.Path]::GetTempPath(), never $env:TEMP. FINDINGS F26: $env:TEMP
    is unset on ubuntu-latest, and the port that ignored that passed 72/72 on a Windows
    workstation and went red on the only gate that counts.

    THE LIVE LEDGER IS NEVER TOUCHED. Every append in this file goes to a fixture under
    the temp root with an explicit -LedgerPath. The module's default path resolves to
    <repo>/.ledger/ledger.jsonl, and substrate has no such file; the last Context proves
    this suite did not create one.
#>

BeforeDiscovery {
    $script:TestsRoot  = $PSScriptRoot
    $script:ModuleRoot = Split-Path $PSScriptRoot -Parent

    # Blob shas from the scaffold commit, which measured each one three ways: the source
    # repo AT the copy sha, the source working tree, and this tree. Recomputing them here
    # from the bytes on disk is the fourth. A file that drifts by one byte cannot keep its
    # sha, so an edit shows up as a named failure instead of as a behaviour change nobody
    # attributed.
    #
    # The table is a data FILE, loaded in both Pester phases from one place. Discovery-time
    # variables do not survive into the run phase, and a second copy of eleven hashes pasted
    # into BeforeAll is a second place to forget.
    $script:BlobData = Import-PowerShellDataFile -LiteralPath (
        Join-Path $PSScriptRoot 'fixtures' 'copied-blobs.psd1')
    $script:CopiedBlobs = $script:BlobData.Files

    # Measured, not assumed: every tamper below was run against a real four-record chain
    # and the FullyQualifiedErrorId it produced was read off the ErrorRecord. Asserting the
    # id, not the message, is what stops a rephrased error from silently reclassifying a
    # break -- and what stops "it threw" from standing in for "it threw for this reason".
    $script:Tampers = @(
        @{ Name = 'one edited payload byte';        Mutation = 'payload-byte';   ErrorId = 'LedgerBadSelf' }
        @{ Name = 'a record deleted from the middle'; Mutation = 'record-deleted'; ErrorId = 'LedgerBrokenChain' }
        @{ Name = 'two records swapped';            Mutation = 'records-swapped'; ErrorId = 'LedgerBrokenChain' }
        @{ Name = 'a ninth key';                    Mutation = 'ninth-key';      ErrorId = 'LedgerBadRecord' }
        @{ Name = 'a removed key';                  Mutation = 'key-removed';    ErrorId = 'LedgerBadRecord' }
        @{ Name = 'an uppercase self';              Mutation = 'upper-hex-self'; ErrorId = 'LedgerBadRecord' }
        @{ Name = 'attempt sent as a JSON string';  Mutation = 'attempt-string'; ErrorId = 'LedgerBadRecord' }
        @{ Name = 'a line that is not JSON';        Mutation = 'not-json';       ErrorId = 'LedgerCorruptLine' }
        @{ Name = 'a line that is a JSON array';    Mutation = 'json-array';     ErrorId = 'LedgerCorruptLine' }
    )
}

Describe 'ledger' -Tag 'ledger' {

    BeforeAll {
        $script:ModuleRoot   = Split-Path $PSScriptRoot -Parent
        $script:RepoRoot     = Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent
        $script:ManifestPath = Join-Path $script:ModuleRoot 'ledger.psd1'
        $script:Psm1Path     = Join-Path $script:ModuleRoot 'ledger.psm1'
        $script:BurstScript  = Join-Path $PSScriptRoot 'helpers' 'Invoke-AppendBurst.ps1'

        # The temp root, resolved ONCE and the cross-platform way. See the file header.
        $script:TempRoot  = [System.IO.Path]::GetTempPath()
        $script:TempDirs  = [System.Collections.Generic.List[string]]::new()

        $script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        $script:Genesis   = '0' * 64

        Import-Module -Name $script:ManifestPath -Force -ErrorAction Stop
        $script:Mod = Get-Module -Name 'ledger'

        $script:BlobData = Import-PowerShellDataFile -LiteralPath (
            Join-Path $PSScriptRoot 'fixtures' 'copied-blobs.psd1')
        $script:CopiedBlobs = $script:BlobData.Files

        function New-TempDir {
            $d = Join-Path $script:TempRoot ('ledger-pester-' + [guid]::NewGuid().ToString('N'))
            $null = New-Item -ItemType Directory -Path $d -Force
            $script:TempDirs.Add($d)
            return $d
        }

        function Get-GitBlobSha {
            <#
                git's blob id, computed from the bytes: sha1("blob <length>\0" + content).
                Done by hand rather than by shelling out to git, so the assertion holds in an
                exported tree with no .git directory and cannot be satisfied by an index that
                disagrees with the file.
            #>
            param([Parameter(Mandatory)][string]$Path)
            $bytes  = [System.IO.File]::ReadAllBytes($Path)
            $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
            $all    = [byte[]]::new($header.Length + $bytes.Length)
            [System.Buffer]::BlockCopy($header, 0, $all, 0, $header.Length)
            [System.Buffer]::BlockCopy($bytes, 0, $all, $header.Length, $bytes.Length)
            return [System.Convert]::ToHexString(
                [System.Security.Cryptography.SHA1]::HashData($all)).ToLowerInvariant()
        }

        function Get-GitBlobShaOfBytes {
            param([Parameter(Mandatory)][byte[]]$Bytes)
            $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($Bytes.Length)`0")
            $all    = [byte[]]::new($header.Length + $Bytes.Length)
            [System.Buffer]::BlockCopy($header, 0, $all, 0, $header.Length)
            [System.Buffer]::BlockCopy($Bytes, 0, $all, $header.Length, $Bytes.Length)
            return [System.Convert]::ToHexString(
                [System.Security.Cryptography.SHA1]::HashData($all)).ToLowerInvariant()
        }

        function Add-Receipt {
            # Add-LedgerRecord was private when this helper was written, and it is called in
            # the module's own scope for that reason. It is exported now -- for the sentinel,
            # not for this suite -- and the module-scope call is left alone deliberately: the
            # fixture chains below were built through this path and changing how they are
            # written would change what the read-back Contexts are measuring.
            param(
                [Parameter(Mandatory)][string]$Path,
                [Parameter(Mandatory)][int]$Attempt,
                [Parameter(Mandatory)][string]$Sha256,
                [string]$Model = 'pester'
            )
            & $script:Mod {
                param($p, $a, $s, $m)
                Add-LedgerRecord -Path $p -Attempt $a -Validator 'non_empty' `
                    -Mode 'dry-run' -Model $m -Sha256 $s
            } $Path $Attempt $Sha256 $Model
        }

        function New-Chain {
            # A fixture chain of -Count records, each with a distinct, well-formed sha256.
            param([string]$Dir, [int]$Count = 4)
            $p = Join-Path $Dir 'chain.jsonl'
            for ($i = 1; $i -le $Count; $i++) {
                $null = Add-Receipt -Path $p -Attempt $i -Sha256 (('{0:x2}' -f $i) * 32)
            }
            return $p
        }

        function New-Tampered {
            <#
                Write a mutated COPY of $Source and return its path. One mutation per call,
                named, so a failure says which break went undetected rather than "the chain
                is fine".
            #>
            param([string]$Source, [string]$Dir, [string]$Mutation)
            $lines = @([System.IO.File]::ReadAllLines($Source))
            switch ($Mutation) {
                'payload-byte'    { $lines[1] = $lines[1] -replace '"model":"pester"', '"model":"pestet"' }
                'record-deleted'  { $lines = @($lines[0]) + @($lines[2..($lines.Count - 1)]) }
                'records-swapped' { $t = $lines[1]; $lines[1] = $lines[2]; $lines[2] = $t }
                'ninth-key'       { $lines[1] = $lines[1] -replace '\}$', ',"note":"harmless"}' }
                'key-removed'     { $lines[1] = $lines[1] -replace ',"model":"pester"', '' }
                'upper-hex-self'  {
                    $m = [regex]::Match($lines[1], '"self":"([0-9a-f]{64})"')
                    $lines[1] = $lines[1] -replace '"self":"[0-9a-f]{64}"',
                        ('"self":"' + $m.Groups[1].Value.ToUpperInvariant() + '"')
                }
                'attempt-string'  { $lines[1] = $lines[1] -replace '"attempt":2', '"attempt":"2"' }
                'not-json'        { $lines[1] = 'this line is not json' }
                'json-array'      { $lines[1] = '["an","array"]' }
                default           { throw "New-Tampered: unknown mutation '$Mutation'" }
            }
            $f = Join-Path $Dir ("tampered-$Mutation-" + [guid]::NewGuid().ToString('N') + '.jsonl')
            [System.IO.File]::WriteAllLines($f, $lines, $script:Utf8NoBom)
            return $f
        }

        function Get-ForbiddenJsonCmdletHit {
            <#
                THE PREDICATE, DEFINED ONCE. FINDINGS F32: the first version of this check in
                the plans module was a text grep, and it went red on the block comment that
                explained why the cmdlet is not used. A check that a WORD is absent from a
                file punishes writing the reasoning down and can be satisfied by writing
                around it.

                So: parse. A hit is a CommandAst whose command name is one of the banned
                cmdlets, or the name appearing in any token that is not a comment and not a
                string. Comments and docstrings are free to discuss them -- ledger.psm1's own
                header says "Deliberately not ConvertTo-Json", which is the sentence that
                makes the ban legible and must not be what breaks it.

                Used by the real check AND by its planted-defect twin, so neither can be
                right about a different rule than the other.
            #>
            param(
                [string]$Path,
                [string]$Text,
                [string[]]$InFunction,
                [string[]]$Banned = @('ConvertTo-Json', 'ConvertFrom-Json', 'Test-Json')
            )
            $tokens = $null
            $errors = $null
            $ast = if ($Path) {
                [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)
            } else {
                [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$tokens, [ref]$errors)
            }

            # -InFunction narrows the search to named functions and reports which of them were
            # actually found, so a typo in the list cannot quietly scope the check to nothing.
            $roots = @($ast)
            $matched = @()
            if ($InFunction) {
                $defs = @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
                    Where-Object { $InFunction -contains $_.Name })
                $roots = $defs
                $matched = @($defs | ForEach-Object { $_.Name } | Sort-Object -Unique)
            }

            $calls = @(foreach ($r in $roots) {
                $r.FindAll({ $args[0] -is [System.Management.Automation.Language.CommandAst] }, $true) |
                    ForEach-Object {
                        $n = $_.GetCommandName()
                        if ($n -and ($Banned -contains $n)) {
                            [pscustomobject]@{ Name = $n; Line = $_.Extent.StartLineNumber }
                        }
                    }
            })

            $scopeTokens = if ($InFunction) {
                $spans = @($roots | ForEach-Object { , @($_.Extent.StartOffset, $_.Extent.EndOffset) })
                @($tokens | Where-Object {
                    $tk = $_
                    @($spans | Where-Object { $tk.Extent.StartOffset -ge $_[0] -and $tk.Extent.EndOffset -le $_[1] }).Count -gt 0 })
            } else { @($tokens) }

            $bareTokens = @($scopeTokens |
                Where-Object {
                    $_.Kind -ne [System.Management.Automation.Language.TokenKind]::Comment -and
                    $_.Kind -ne [System.Management.Automation.Language.TokenKind]::StringLiteral -and
                    $_.Kind -ne [System.Management.Automation.Language.TokenKind]::StringExpandable
                } |
                Where-Object { $t = $_.Text; @($Banned | Where-Object { $t -like "*$_*" }).Count -gt 0 } |
                ForEach-Object { $_.Text })

            return [pscustomobject]@{
                Calls           = $calls
                CallNames       = @($calls | ForEach-Object { $_.Name })
                BareTokens      = $bareTokens
                MatchedFunction = $matched
                ParseErrors     = @($errors)
                Any             = ((@($calls).Count + @($bareTokens).Count) -gt 0)
            }
        }

        function Get-LedgerErrorId {
            <#
                Every FullyQualifiedErrorId the module can raise, collected from the AST rather
                than from a grep or from the docstrings. Two paths, because the module uses two:

                  ViaFactory  New-LedgerError -Id '<literal>'
                  ViaCtor     [System.Management.Automation.ErrorRecord]::new($ex, '<literal>', ...)

                Non-literal second arguments are counted, not dropped. There is exactly one --
                New-LedgerError's own call, where the id is the parameter -- and a second one
                appearing would mean an id this collector cannot see, which is worth a failure.
            #>
            param([Parameter(Mandatory)][string]$Path)
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tokens, [ref]$errors)

            $viaFactory = @($ast.FindAll({
                    $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                    $args[0].GetCommandName() -eq 'New-LedgerError' }, $true) |
                ForEach-Object {
                    $e = $_.CommandElements
                    for ($i = 0; $i -lt $e.Count - 1; $i++) {
                        if ($e[$i] -is [System.Management.Automation.Language.CommandParameterAst] -and
                            $e[$i].ParameterName -eq 'Id') { $e[$i + 1].Value }
                    }
                })

            $ctors = @($ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $args[0].Member.Value -eq 'new' -and
                $args[0].Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
                $args[0].Expression.TypeName.FullName -match 'ErrorRecord$' }, $true))

            $viaCtor = [System.Collections.Generic.List[string]]::new()
            $nonLiteral = 0
            foreach ($c in $ctors) {
                $a = $c.Arguments
                if ($a -and $a.Count -ge 2 -and
                    $a[1] -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                    $viaCtor.Add($a[1].Value)
                }
                else { $nonLiteral++ }
            }

            return [pscustomobject]@{
                ViaFactory      = @($viaFactory | Sort-Object -Unique)
                ViaCtor         = @($viaCtor | Sort-Object -Unique)
                NonLiteralCtors = $nonLiteral
                All             = @(@($viaFactory) + @($viaCtor) | Sort-Object -Unique)
                ParseErrors     = @($errors)
            }
        }

        function Get-TreeSnapshot {
            <#
                Path -> sha256, for every file under a root. Used to prove the suite wrote
                nothing where it should not have.

                __pycache__ is excluded, and the exclusion is not a convenience. Spawning
                cli.py makes CPython write bytecode beside the engine; python.Tests.ps1 owns
                that fact and asserts the outcome that matters (git sees nothing new, because
                .gitignore names it). Leaving it in here would make this It fail for a reason
                that has nothing to do with whether the module was edited, which is the only
                thing it is asking.
            #>
            param([string]$Root)
            $map = [ordered]@{}
            $files = Get-ChildItem -LiteralPath $Root -Recurse -File |
                Where-Object { $_.FullName -notmatch '__pycache__' -and $_.Extension -ne '.pyc' } |
                Sort-Object FullName
            foreach ($f in $files) {
                $map[$f.FullName] = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash
            }
            return $map
        }

        $script:BeforeSnapshot = Get-TreeSnapshot -Root $script:ModuleRoot

        # One shared fixture chain for the read-only Contexts.
        $script:WorkDir   = New-TempDir
        $script:ChainPath = New-Chain -Dir $script:WorkDir -Count 4
        $script:ChainLines = @([System.IO.File]::ReadAllLines($script:ChainPath))
    }

    # ================================================================== provenance

    Context 'provenance -- the copy is the copy' {

        It 'the copied file <Path> still hashes to the blob sha the scaffold commit recorded' -ForEach $script:CopiedBlobs {
            $full = Join-Path $script:ModuleRoot $Path
            $full | Should -Exist
            Get-GitBlobSha -Path $full | Should -BeExactly $Sha
        }

        It 'no copied file carries a CR byte, so the shas above are not an accident of checkout' {
            # If a checkout ever produced CRLF, every row above would fail with an opaque hash
            # mismatch. This says the cause out loud instead.
            @($script:CopiedBlobs).Count | Should -Be 9 -Because 'the table must not be empty'
            $offenders = foreach ($c in $script:CopiedBlobs) {
                $bytes = [System.IO.File]::ReadAllBytes((Join-Path $script:ModuleRoot $c.Path))
                if ($bytes -contains 13) { $c.Path }
            }
            @($offenders) | Should -BeNullOrEmpty
        }

        It 'the falsification control: one appended byte moves the blob sha' {
            # Without this, every row above could be passing because the hash function
            # returns a constant. It does not.
            #
            # The control was ledger.psm1 until that row was retired -- core's ledger module
            # diverges from upstream on purpose now, so it cannot be pinned. It moved to
            # tests/sandbox/fail_path.ps1, the row least likely to move next: a carried sandbox
            # script whose single claim was ported into python.Tests.ps1, so nothing maintains
            # it, and it names no export surface, no version and no dependency. The control
            # asserts both halves -- the pinned file matches, and one more byte does not.
            $control = 'tests/sandbox/fail_path.ps1'
            $pinned  = @($script:CopiedBlobs | Where-Object { $_.Path -eq $control }).Sha
            $pinned | Should -Not -BeNullOrEmpty -Because 'the control must be a row that is still pinned'
            $full   = Join-Path $script:ModuleRoot $control
            $bytes  = [System.IO.File]::ReadAllBytes($full)
            Get-GitBlobSha -Path $full | Should -BeExactly $pinned
            Get-GitBlobShaOfBytes -Bytes ($bytes + [byte]0x20) | Should -Not -BeExactly $pinned
        }

        It 'LedgerReceipt.ps1 was not copied, here or anywhere under modules/' {
            # FINDINGS F29: image.builder's LedgerReceipt.ps1 is a SECOND hash chain -- eight
            # different keys, ConvertTo-Json on both the write and the verify path, prev
            # hashed twice, and no lock across the tail read. It is a boot-time hook rail and
            # its destination is claude.agent.images. Named here so that picking it up later
            # has to argue with a red test.
            @(Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'modules') -Recurse -File -Filter 'LedgerReceipt.ps1') |
                Should -BeNullOrEmpty
        }

        It 'the two suites that are not substrate were not copied either' {
            # fuzzer_import.ps1 imports claude.build.fuzzer by sibling path -- claude.agent.tools.
            # hook_pre_tool.ps1 tests the PreToolUse hook -- claude.agent.images.
            $modules = Join-Path $script:RepoRoot 'modules'
            foreach ($name in 'fuzzer_import.ps1', 'hook_pre_tool.ps1', 'no_sabotage.ps1', 'continuity.ps1') {
                @(Get-ChildItem -LiteralPath $modules -Recurse -File -Filter $name) |
                    Should -BeNullOrEmpty -Because "$name has no subject in this repository"
            }
        }
    }

    # ================================================================== module surface

    Context "the module surface -- the source module's four, plus the writer core exported" {

        It 'imports from the manifest under the bare name ledger' {
            $script:Mod | Should -Not -BeNullOrEmpty
            $script:Mod.Name | Should -BeExactly 'ledger'
            $script:Mod.Version.ToString() | Should -BeExactly '0.2.0'
        }

        It "exports exactly five functions: the source module's four, plus Add-LedgerRecord" {
            @($script:Mod.ExportedFunctions.Keys | Sort-Object) |
                Should -Be @('Add-LedgerRecord', 'Get-LedgerEntry', 'Get-LedgerStatus',
                             'Get-LedgerVerify', 'Invoke-LedgerForce')
        }

        It 'exports exactly one alias, bound to Invoke-LedgerForce' {
            @($script:Mod.ExportedAliases.Keys) | Should -Be @('ledger-force')
            $script:Mod.ExportedAliases['ledger-force'].Definition | Should -BeExactly 'Invoke-LedgerForce'
        }

        It 'exports the writer, and still not the canonicalizer or error factory' {
            # This It read "does not export the private writer, canonicalizer or error factory"
            # until the writer went public, with Add-LedgerRecord first in the list below. It is
            # rewritten rather than deleted so the change of surface is legible here and not only
            # in the log: claude.agent.images hooks/sentinel.ps1 was reaching the writer through
            # module session state, which is BLOCKER-1, and a public name is the fix. The other
            # four are unchanged -- widening the surface by one is not widening it by five.
            $script:Mod.ExportedFunctions.Keys | Should -Contain 'Add-LedgerRecord'
            $script:Mod.ExportedFunctions['Add-LedgerRecord'].CommandType | Should -Be 'Function'
            foreach ($n in 'ConvertTo-LedgerCanonicalJson', 'New-LedgerError',
                           'ConvertFrom-LedgerLine', 'Get-LedgerSha256Hex') {
                $script:Mod.ExportedFunctions.Keys | Should -Not -Contain $n
            }
        }

        It 'the manifest names the module file that is actually there' {
            $data = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
            Join-Path $script:ModuleRoot $data.RootModule | Should -Exist
        }

        It "the manifest's FunctionsToExport equals the psm1's Export-ModuleMember list" {
            # A name in FunctionsToExport with no function behind it exports nothing -- the two
            # lists intersect. FINDINGS F33 recorded that as the one planted defect that did
            # not go red in the plans suite. It goes red here.
            $data = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Psm1Path, [ref]$tokens, [ref]$errors)
            $emm = @($ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.CommandAst] -and
                $args[0].GetCommandName() -eq 'Export-ModuleMember' }, $true))
            $emm.Count | Should -Be 1
            # FindAll, not a scan of CommandElements: `-Function 'a','b','c'` parses the list as
            # one ArrayLiteralAst, so the names are children of an element, not elements.
            $named = @($emm[0].FindAll({
                    $args[0] -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                ForEach-Object { $_.Value } |
                Where-Object { $_ -match '^\w+-Ledger' })
            $named | Should -Not -BeNullOrEmpty
            @($named | Sort-Object) | Should -Be @($data.FunctionsToExport | Sort-Object)
        }

        It 'declares the PowerShell floor the repository declares' {
            $data   = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
            $config = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'config/repo.json') -Raw |
                      ConvertFrom-Json -Depth 20
            $data.PowerShellVersion | Should -BeExactly '7.4'
            $data.PowerShellVersion | Should -BeExactly $config.runtimes.powershell
        }

        It 'Get-LedgerStatus reports the snake that is actually on disk' {
            $s = Get-LedgerStatus
            $s.Protocol | Should -Be 1
            $s.SnakePresent | Should -BeTrue
            $s.SnakeCli | Should -BeExactly (Join-Path $script:ModuleRoot 'python' 'cli.py')
        }
    }

    # ================================================================== the error surface

    Context 'the error surface -- LedgerError stayed inside the module, and is pinned' {

        It 'New-LedgerError is defined in ledger.psm1, not in a nested module or a sibling file' {
            # The decision, asserted rather than described. There is no LedgerError.ps1 to
            # absorb: the error surface is one private ErrorRecord factory plus a vocabulary
            # of ids, both inside the psm1. FINDINGS F35.
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Psm1Path, [ref]$tokens, [ref]$errors)
            @($ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $args[0].Name -eq 'New-LedgerError' }, $true)).Count | Should -Be 1

            $data = Import-PowerShellDataFile -LiteralPath $script:ManifestPath
            $data.Keys | Should -Not -Contain 'NestedModules'
            @(Get-ChildItem -LiteralPath $script:ModuleRoot -File -Filter '*.ps1') |
                Should -BeNullOrEmpty -Because 'the module is one manifest and one psm1'
        }

        It 'both error-construction paths are still the two this suite knows about' {
            # Measured, and the reason this It exists separately from the one below. The module
            # builds ErrorRecords TWO ways: nine sites go through New-LedgerError, seven call
            # [ErrorRecord]::new directly. A collector that saw only the first would report a
            # clean eight-id vocabulary and be wrong about six ids, so the collector's own
            # coverage is asserted before its result is trusted.
            $ids = Get-LedgerErrorId -Path $script:Psm1Path
            @($ids.ViaFactory).Count  | Should -BeGreaterThan 0
            @($ids.ViaCtor).Count     | Should -BeGreaterThan 0
            # Exactly one non-literal: the $Id parameter inside New-LedgerError itself, which
            # is the factory and not a site that names an id.
            $ids.NonLiteralCtors | Should -Be 1
        }

        It 'every error id raised by the module is in the pinned vocabulary' {
            $ids = Get-LedgerErrorId -Path $script:Psm1Path
            # InspectorPolicyHalt is deliberately absent: it is raised by claude.build.inspector
            # and travels up through Invoke-LedgerForce UNWRAPPED. Nothing here constructs it,
            # and a version of this list that included it would be describing a different module.
            $ids.All | Should -Be @(
                'LedgerAppendFailed', 'LedgerBadRecord', 'LedgerBadSelf', 'LedgerBadSettings',
                'LedgerBrokenChain', 'LedgerCliMissing', 'LedgerCorruptLine', 'LedgerFileMissing',
                'LedgerMissingApiKey', 'LedgerNoResult', 'LedgerOutputHashMismatch',
                'LedgerPythonMissing', 'LedgerResultMismatch', 'LedgerSnakeFailed')
        }

        It 'a missing ledger is a terminating LedgerFileMissing, not an empty result' {
            $absent = Join-Path (New-TempDir) 'not-here.jsonl'
            $err = { Get-LedgerVerify -LedgerPath $absent } | Should -Throw -PassThru
            $err.FullyQualifiedErrorId | Should -Match '^LedgerFileMissing'
            $err.CategoryInfo.Category | Should -Be 'ObjectNotFound'
        }

        It 'the writer refuses to sign a malformed output hash' {
            $p = Join-Path (New-TempDir) 'refused.jsonl'
            $err = { Add-Receipt -Path $p -Attempt 1 -Sha256 'not-a-hash' } | Should -Throw -PassThru
            $err.FullyQualifiedErrorId | Should -Match 'LedgerBadRecord'
            $p | Should -Not -Exist -Because 'a refused record must not leave a file behind'
        }
    }

    # ==================================================================== the lying snake

    Context 'the lying snake -- LedgerResultMismatch, on both platforms' {

        # FINDINGS.md F44 TEST 10 and F51. LedgerResultMismatch was the one id in the pinned
        # vocabulary with nothing behind it: proving it needs a snake that lies about the run it
        # performed, and the original's stub is a Windows .cmd that cannot run on ubuntu-latest.
        #
        # The stub is chosen on $IsWindows, as the run order asked -- but the non-Windows half is
        # `lie`, EXTENSIONLESS, and not the `lie.ps1` the run order specified. That is measured,
        # and the first version of this Context got it wrong in the other direction: it asserted
        # that no PowerShell-interpreted stub could exist at all, on the strength of a Windows-only
        # refusal. The runner said otherwise, which is F26's lesson arriving from the far side --
        # a claim about "the platform" that was only ever measured on one. F67 records both the
        # error and the correction.
        #
        # The two constraints that actually shape the fixture, each asserted below:
        #   1. `pwsh -File` rejects a non-.ps1 path ON WINDOWS ONLY. So Windows needs the .cmd.
        #   2. A .ps1 is an ExternalScript on EVERY platform, and Invoke-LedgerForce resolves
        #      -PythonPath with Get-Command -CommandType Application. So `lie.ps1` could never be
        #      found, and the non-Windows stub carries its shebang without an extension.

        BeforeAll {
            $script:LyingSnakeDir = Join-Path $PSScriptRoot 'fixtures' 'lying-snake'
            $script:LyingSnakeCmd = Join-Path $script:LyingSnakeDir 'lie.cmd'
            $script:LyingSnakeNix = Join-Path $script:LyingSnakeDir 'lie'
            $script:LyingSnake    = if ($IsWindows) { $script:LyingSnakeCmd } else { $script:LyingSnakeNix }
            $script:LyingPayload  = Join-Path $script:LyingSnakeDir 'result-mismatch.ndjson'
        }

        It 'the fixture is one result event that lies about the mode, and its output hash is honest' {
            # The lie has to be exactly one thing. A payload whose hash was also wrong would
            # still throw, and the It below would pass while proving the wrong guard.
            $script:LyingPayload | Should -Exist
            $lines = @([System.IO.File]::ReadAllLines($script:LyingPayload) |
                       Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            $lines.Count | Should -Be 1 -Because 'one event, so the module cannot be reading some other line'

            $evt = $lines[0] | ConvertFrom-Json
            $evt.type      | Should -BeExactly 'result'
            $evt.mode      | Should -BeExactly 'live' -Because 'the force below asks for dry-run; this is the lie'
            $evt.validator | Should -BeExactly 'non_empty' -Because 'the validator echo must AGREE, or it is a different mismatch'
            $evt.model     | Should -BeExactly 'stub-model'

            $hash = [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes($evt.output))
            [System.Convert]::ToHexString($hash).ToLowerInvariant() |
                Should -BeExactly $evt.sha256 -Because 'identity is checked before integrity; the payload must survive on merit'

            # Both stubs ship, whichever platform is running. The one for the other platform is
            # the half this run cannot execute, and it must still be in the tree.
            $script:LyingSnakeCmd | Should -Exist
            $script:LyingSnakeNix | Should -Exist
        }

        It 'the stub itself writes the payload verbatim on one line and exits 0' {
            # The layer BELOW the force, isolated on purpose. The first non-Windows stub exited 0
            # and emitted nothing, which reaches the module as LedgerNoResult -- an error that
            # says "the snake said nothing" and cannot distinguish a broken stub from a broken
            # module. This It fails with the actual exit code and the actual stdout, so the next
            # person does not have to guess which half moved.
            #
            # Invoked with the argv shape the module uses (a leading script path, then CLI flags)
            # and with the same stdin, because a stub that only works when called bare is not the
            # stub the module will be calling.
            $PSNativeCommandUseErrorActionPreference = $false
            $ErrorActionPreference = 'Continue'

            $out = ('{"prompt":"write add(a, b)"}' |
                & $script:LyingSnake 'ledger.python.cli' '--protocol' '1' '--mode' 'dry-run' 2>&1 |
                ForEach-Object { [string]$_ })
            $code = $LASTEXITCODE

            $code | Should -Be 0 -Because "the stub must exit 0; it wrote: $($out -join ' / ')"

            $payloadLine = @([System.IO.File]::ReadAllLines($script:LyingPayload) |
                             Where-Object { -not [string]::IsNullOrWhiteSpace($_) })[0]
            $emitted = @($out | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

            $emitted.Count | Should -Be 1 -Because "the event must arrive as ONE line or the module cannot parse it; got $($emitted.Count): $($emitted -join ' // ')"
            $emitted[0]    | Should -BeExactly $payloadLine -Because 'verbatim, with no output formatter in the way'
        }

        It 'a snake that lies about the run it performed raises LedgerResultMismatch' {
            # Runs on BOTH platforms. lie.cmd on Windows, the extensionless shebang stub
            # everywhere else. No -Skip: the whole point of F44 TEST 10 is that ubuntu-latest is
            # the only gate, so a version of this that skipped there would prove nothing where it
            # counts.
            $ledger = Join-Path (New-TempDir) 'never-written.jsonl'

            $err = {
                Invoke-LedgerForce -Prompt 'write add(a, b)' -Mode 'dry-run' -Validator 'non_empty' `
                    -Model 'stub-model' -PythonPath $script:LyingSnake -LedgerPath $ledger
            } | Should -Throw -PassThru

            $err.FullyQualifiedErrorId | Should -Match '^LedgerResultMismatch'
            $err.Exception.Message | Should -Match "mode was asked for as 'dry-run' and came back as 'live'"
            $ledger | Should -Not -Exist -Because 'a run the module refuses to describe must leave no receipt'
        }

        It 'the stub the module will actually resolve is an Application, and it is the right one for this platform' {
            # Anti-vacuity for the It above. If Get-Command could not resolve the stub, the force
            # would raise LedgerPythonMissing -- and `Should -Throw` plus a -Match on the id would
            # still catch that, but only because the id happens to differ. This asserts the
            # mechanism directly instead of trusting that.
            $resolved = Get-Command -Name $script:LyingSnake -CommandType Application -ErrorAction SilentlyContinue
            $resolved | Should -Not -BeNullOrEmpty -Because 'ledger.psm1 resolves -PythonPath as an Application, and only an Application will do'

            if ($IsWindows) {
                [System.IO.Path]::GetExtension($script:LyingSnake) | Should -BeExactly '.cmd'
            }
            else {
                [System.IO.Path]::GetExtension($script:LyingSnake) | Should -BeExactly '' -Because 'a .ps1 would be an ExternalScript and never resolve'
                ([System.IO.File]::GetUnixFileMode($script:LyingSnake) -band [System.IO.UnixFileMode]::UserExecute) |
                    Should -Be ([System.IO.UnixFileMode]::UserExecute) -Because 'the execute bit is carried in the tree by git update-index --chmod=+x'
            }
        }
        It 'lie is tracked as 100755, so the execute bit survives a copy that carries only bytes' {
            # The mode is a property of the TREE, not of the file on disk, and Windows has no
            # execute bit to observe -- so the platform assertion above goes green on Windows
            # whatever the index says. This one reads the index, so it is the same assertion on
            # every runner, which is the whole point of adding it.
            #
            # FINDINGS F79: the birth commit copied this file's bytes and not its mode, Windows
            # could not see the difference, and ubuntu CI reported it as three reds in this
            # Context that each looked like a different bug.
            $repoRoot = Split-Path (Split-Path $script:ModuleRoot -Parent) -Parent
            Push-Location $repoRoot
            try {
                $entry = (& git ls-files -s -- 'modules/ledger/tests/fixtures/lying-snake/lie' | Out-String).Trim()
            }
            finally { Pop-Location }

            $entry | Should -Not -BeNullOrEmpty -Because 'the stub has to be tracked, not merely present on disk'
            $entry | Should -Match '^100755 ' -Because 'a stub this module resolves as an Application has to be executable in the tree'
        }

        It 'pwsh -File rejects a path without a .ps1 extension ON WINDOWS ONLY, which is why there are two stubs' {
            # The measurement the first version of this Context got wrong. A shebang hands the
            # interpreter the script path as an argument, so `#!/usr/bin/env pwsh` on an
            # extensionless file resolves to `pwsh /path/to/lie`. On Windows that is refused with
            # exit 64; on Linux and macOS it runs. One stub mechanism cannot serve both, and THAT
            # is why the fixture has a .cmd as well -- not because no shebang stub can exist.
            $extensionless = Join-Path (New-TempDir) 'lie'
            [System.IO.File]::WriteAllText(
                $extensionless, "#!/usr/bin/env pwsh`nWrite-Output 'ran'`n", $script:Utf8NoBom)

            # The exit code is DATA here, as it is in python.Tests.ps1's Invoke-Native.
            $PSNativeCommandUseErrorActionPreference = $false
            $ErrorActionPreference = 'Continue'
            $out  = (& pwsh -NoProfile -File $extensionless 2>&1 | Out-String)
            $code = $LASTEXITCODE

            if ($IsWindows) {
                $code | Should -Be 64 -Because 'Windows enforces the .ps1 extension on -File'
                $out  | Should -Match "does not have a '\.ps1' extension"
            }
            else {
                $code | Should -Be 0 -Because 'this is what makes the extensionless shebang stub possible here'
                $out  | Should -Match 'ran'
            }
        }

        It 'and it still cannot be the run order''s lie.ps1: that is an ExternalScript on every platform' {
            # The constraint that survived the correction, and the reason the non-Windows stub is
            # extensionless rather than the `lie.ps1` step 6.6 Option A specified. Unlike the It
            # above, this one is true on Windows AND Linux.
            $ps1 = Join-Path (New-TempDir) 'lie.ps1'
            [System.IO.File]::WriteAllText(
                $ps1, "#!/usr/bin/env pwsh`nWrite-Output 'ran'`n", $script:Utf8NoBom)

            if (-not $IsWindows) {
                # The execute bit is the thing that would make this an Application if the
                # extension allowed it, so setting it is what stops this It being vacuous on the
                # only platform it is about. .NET 8, not chmod: no shell is invoked.
                [System.IO.File]::SetUnixFileMode($ps1, [System.IO.UnixFileMode]::UserRead -bor
                    [System.IO.UnixFileMode]::UserWrite  -bor [System.IO.UnixFileMode]::UserExecute -bor
                    [System.IO.UnixFileMode]::GroupRead  -bor [System.IO.UnixFileMode]::GroupExecute -bor
                    [System.IO.UnixFileMode]::OtherRead  -bor [System.IO.UnixFileMode]::OtherExecute)
                ([System.IO.File]::GetUnixFileMode($ps1) -band [System.IO.UnixFileMode]::UserExecute) |
                    Should -Be ([System.IO.UnixFileMode]::UserExecute) -Because 'the file really is executable'
            }

            (Get-Command -Name $ps1 -ErrorAction SilentlyContinue).CommandType |
                Should -Be 'ExternalScript'
            Get-Command -Name $ps1 -CommandType Application -ErrorAction SilentlyContinue |
                Should -BeNullOrEmpty -Because 'a .ps1 is never an Application, execute bit or not'
        }

        It 'and that matters because THIS module resolves -PythonPath as an Application' {
            # Anti-vacuity. The two Its above are facts about PowerShell, not about ledger.psm1.
            # They only bear on F44 TEST 10 while the module still looks its interpreter up the
            # way it does today. Parsed, not grepped -- FINDINGS F32 is the reason.
            $tokens = $null; $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                $script:Psm1Path, [ref]$tokens, [ref]$errors)
            @($errors) | Should -BeNullOrEmpty -Because 'ledger.psm1 must parse'

            $argumentFor = {
                param($elements, $name)
                for ($i = 0; $i -lt $elements.Count; $i++) {
                    $e = $elements[$i]
                    if ($e -is [System.Management.Automation.Language.CommandParameterAst] -and
                        $e.ParameterName -eq $name) {
                        if ($null -ne $e.Argument) { return $e.Argument }
                        if ($i + 1 -lt $elements.Count) { return $elements[$i + 1] }
                    }
                }
                return $null
            }

            $resolvers = @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -eq 'Get-Command'
                }, $true) | Where-Object {
                    $type = & $argumentFor $_.CommandElements 'CommandType'
                    $name = & $argumentFor $_.CommandElements 'Name'
                    ($null -ne $type) -and ($type.Extent.Text -eq 'Application') -and
                    ($name -is [System.Management.Automation.Language.VariableExpressionAst]) -and
                    ($name.VariablePath.UserPath -eq 'PythonPath')
                })

            @($resolvers).Count | Should -Be 1 -Because 'Invoke-LedgerForce resolves -PythonPath with Get-Command -CommandType Application'
        }
    }

    # ================================================================== append / verify

    Context 'the chain -- append and verify round-trip' {

        It 'four appends produce four records and the chain verifies' {
            $v = Get-LedgerVerify -LedgerPath $script:ChainPath
            $v.Ok | Should -BeTrue
            $v.Count | Should -Be 4
            $v.Path | Should -BeExactly $script:ChainPath
        }

        It 'record 1 links to genesis and record N links to record N-1' {
            $selves = @()
            for ($i = 0; $i -lt $script:ChainLines.Count; $i++) {
                $doc = [System.Text.Json.JsonDocument]::Parse($script:ChainLines[$i])
                try {
                    $prev = $doc.RootElement.GetProperty('prev').GetString()
                    $self = $doc.RootElement.GetProperty('self').GetString()
                }
                finally { $doc.Dispose() }
                $expected = if ($i -eq 0) { $script:Genesis } else { $selves[$i - 1] }
                $prev | Should -BeExactly $expected -Because "record $($i + 1) must link to the one before it"
                $selves += $self
            }
            $selves[-1] | Should -BeExactly (Get-LedgerVerify -LedgerPath $script:ChainPath).LastSelf
        }

        It 'every record is exactly the eight v1 keys, in schema order' {
            foreach ($line in $script:ChainLines) {
                $doc = [System.Text.Json.JsonDocument]::Parse($line)
                try { $keys = @($doc.RootElement.EnumerateObject() | ForEach-Object { $_.Name }) }
                finally { $doc.Dispose() }
                $keys | Should -Be @('ts', 'attempt', 'validator', 'mode', 'model', 'sha256', 'prev', 'self')
            }
        }

        It "self is the sha256 of the record's own canonical payload, recomputed from the line" {
            # Independent of the module: strip the self field back off the line and hash what
            # is left. If the writer and the verifier ever agree with each other and with
            # nothing else, this is the check that notices.
            foreach ($line in $script:ChainLines) {
                $m = [regex]::Match($line, '^(?<payload>\{.*),"self":"(?<self>[0-9a-f]{64})"\}$')
                $m.Success | Should -BeTrue -Because "the record must end in a self field: $line"
                $canonical = $m.Groups['payload'].Value + '}'
                $digest = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
                    [System.Text.Encoding]::UTF8.GetBytes($canonical))).ToLowerInvariant()
                $digest | Should -BeExactly $m.Groups['self'].Value
            }
        }

        It 'the file is UTF-8 with no BOM, LF only, and ends with a newline' {
            $bytes = [System.IO.File]::ReadAllBytes($script:ChainPath)
            $bytes[0] | Should -Not -Be 0xEF
            $bytes | Should -Not -Contain 13
            $bytes[-1] | Should -Be 0x0A
        }

        It 'Get-LedgerEntry hands the records back oldest first, with the same hashes' {
            $entries = @(Get-LedgerEntry -LedgerPath $script:ChainPath -Last 0)
            $entries.Count | Should -Be 4
            @($entries | ForEach-Object { $_.Attempt }) | Should -Be @(1, 2, 3, 4)
            $entries[0].Prev | Should -BeExactly $script:Genesis
            for ($i = 1; $i -lt $entries.Count; $i++) {
                $entries[$i].Prev | Should -BeExactly $entries[$i - 1].Self
            }
        }

        It 'appending to an existing chain extends it without rewriting it' {
            $dir = New-TempDir
            $p = New-Chain -Dir $dir -Count 2
            $beforeBytes = [System.IO.File]::ReadAllBytes($p)
            $null = Add-Receipt -Path $p -Attempt 3 -Sha256 ('ab' * 32)
            $afterBytes = [System.IO.File]::ReadAllBytes($p)
            $afterBytes.Length | Should -BeGreaterThan $beforeBytes.Length
            # append-only: the first N bytes are untouched
            $prefix = $afterBytes[0..($beforeBytes.Length - 1)]
            [System.Convert]::ToHexString($prefix) |
                Should -BeExactly ([System.Convert]::ToHexString($beforeBytes))
            (Get-LedgerVerify -LedgerPath $p).Count | Should -Be 3
        }

        It 'a hand-truncated tail is terminated before the next record is glued onto it' {
            $dir = New-TempDir
            $p = New-Chain -Dir $dir -Count 2
            $text = [System.IO.File]::ReadAllText($p)
            [System.IO.File]::WriteAllText($p, $text.TrimEnd("`n"), $script:Utf8NoBom)
            $null = Add-Receipt -Path $p -Attempt 3 -Sha256 ('cd' * 32) -WarningAction SilentlyContinue
            (Get-LedgerVerify -LedgerPath $p).Count | Should -Be 3
        }
    }

    # ================================================================== tamper detection

    Context 'the chain -- tamper detection' {

        It 'the control: an untouched copy of the fixture still verifies' {
            # Without this row every tamper below could be passing because the COPY is broken,
            # not because the tamper was detected.
            $copy = Join-Path (New-TempDir) 'control.jsonl'
            [System.IO.File]::WriteAllLines($copy, $script:ChainLines, $script:Utf8NoBom)
            (Get-LedgerVerify -LedgerPath $copy).Ok | Should -BeTrue
        }

        It 'refuses <Name> with <ErrorId>' -ForEach $script:Tampers {
            $f = New-Tampered -Source $script:ChainPath -Dir $script:WorkDir -Mutation $Mutation
            $err = { Get-LedgerVerify -LedgerPath $f } | Should -Throw -PassThru
            $err.FullyQualifiedErrorId | Should -Match "^$ErrorId"
        }

        It 'a forgery that re-hashes its own record still breaks at the next link' {
            # The interesting attack: edit a payload AND recompute self so the record is
            # internally consistent. The chain notices one record later, which is the whole
            # reason prev is inside the hashed payload.
            $lines = @($script:ChainLines)
            $m = [regex]::Match($lines[1], '^(?<payload>\{.*),"self":"[0-9a-f]{64}"\}$')
            $m.Success | Should -BeTrue
            $forgedPayload = $m.Groups['payload'].Value.Replace('"model":"pester"', '"model":"forged"') + '}'
            $forgedSelf = [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes($forgedPayload))).ToLowerInvariant()
            $lines[1] = $forgedPayload.Substring(0, $forgedPayload.Length - 1) + ',"self":"' + $forgedSelf + '"}'

            $f = Join-Path (New-TempDir) 'forged.jsonl'
            [System.IO.File]::WriteAllLines($f, $lines, $script:Utf8NoBom)
            $err = { Get-LedgerVerify -LedgerPath $f } | Should -Throw -PassThru
            $err.FullyQualifiedErrorId | Should -Match '^LedgerBrokenChain'
            $err.Exception.Message | Should -Match 'line 3'
        }

        It 'Get-LedgerEntry refuses a corrupt record instead of handing it back as data' {
            $f = New-Tampered -Source $script:ChainPath -Dir $script:WorkDir -Mutation 'payload-byte'
            $err = { Get-LedgerEntry -LedgerPath $f -Last 0 } | Should -Throw -PassThru
            $err.FullyQualifiedErrorId | Should -Match '^LedgerBadSelf'
        }

        It 'a blank line is skipped, not treated as a break' {
            $lines = @($script:ChainLines[0], '', $script:ChainLines[1], $script:ChainLines[2], $script:ChainLines[3])
            $f = Join-Path (New-TempDir) 'blank-line.jsonl'
            [System.IO.File]::WriteAllLines($f, $lines, $script:Utf8NoBom)
            (Get-LedgerVerify -LedgerPath $f).Count | Should -Be 4
        }
    }

    # ================================================================== the lock

    Context 'the lock -- the tail read and the append are one critical section' {

        It 'the writer asks for the file exclusively, and says so when it cannot have it' {
            # A foreign handle held with FileShare.None must make the append FAIL. If it did
            # not, two writers could each read the same tail and both claim the same prev.
            $dir = New-TempDir
            $p = New-Chain -Dir $dir -Count 1
            $fs = [System.IO.FileStream]::new($p, [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
            try {
                { Add-Receipt -Path $p -Attempt 2 -Sha256 ('ef' * 32) } | Should -Throw
            }
            finally { $fs.Dispose() }
            (Get-LedgerVerify -LedgerPath $p).Count | Should -Be 1 -Because 'the blocked append wrote nothing'
        }

        It 'four concurrent pwsh writers land twenty distinct records and the chain still verifies' {
            $dir = New-TempDir
            $p = Join-Path $dir 'burst.jsonl'
            $tags = 'a', 'b', 'c', 'd'
            $perTag = 5

            $procs = foreach ($tag in $tags) {
                Start-Process -FilePath (Get-Process -Id $PID).Path -PassThru -NoNewWindow -ArgumentList @(
                    '-NoProfile', '-File', $script:BurstScript,
                    '-ManifestPath', $script:ManifestPath,
                    '-LedgerPath', $p, '-Count', $perTag, '-Tag', $tag)
            }
            $procs | Wait-Process -Timeout 180
            @($procs | ForEach-Object { $_.ExitCode }) | Should -Be @(0, 0, 0, 0)

            $v = Get-LedgerVerify -LedgerPath $p
            $v.Ok | Should -BeTrue
            $v.Count | Should -Be ($tags.Count * $perTag)

            # Not just the count: every record that was asked for, exactly once. A writer that
            # lost an append under contention and a writer that wrote one twice both produce a
            # count that can be made to add up; neither survives a set comparison.
            $expected = foreach ($tag in $tags) {
                for ($i = 1; $i -le $perTag; $i++) {
                    [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData(
                        [System.Text.Encoding]::UTF8.GetBytes("$tag-$i"))).ToLowerInvariant()
                }
            }
            $actual = @(Get-LedgerEntry -LedgerPath $p -Last 0 | ForEach-Object { $_.Sha256 })
            @($actual | Sort-Object -Unique).Count | Should -Be $actual.Count -Because 'no record was written twice'
            @($actual | Sort-Object) | Should -Be @($expected | Sort-Object)
        }
    }

    # ================================================================== the json ban

    Context 'no ConvertTo-Json, ConvertFrom-Json or Test-Json goes anywhere near the chain' {

        BeforeAll {
            # The functions that touch the record bytes: everything from resolving the path,
            # through canonicalising and hashing, to writing, reading back and verifying.
            # THE BAN IS ON THE CHAIN, NOT ON THE MODULE, and the two are different claims --
            # see the It below that says where the module's three real calls live.
            $script:ChainFunctions = @(
                'Resolve-LedgerPath', 'Test-LedgerHex64', 'ConvertTo-LedgerJsonString',
                'ConvertTo-LedgerCanonicalJson', 'Get-LedgerSha256Hex', 'ConvertFrom-LedgerLine',
                'Add-LedgerRecord', 'Get-LedgerVerify', 'Get-LedgerEntry'
            )
        }

        It 'ledger.psm1 parses, so the claims made about its AST are about the whole file' {
            $hit = Get-ForbiddenJsonCmdletHit -Path $script:Psm1Path
            @($hit.ParseErrors) | Should -BeNullOrEmpty
        }

        It 'every function this check claims to cover is really in the file' {
            # A misspelled name in the list above would narrow the scope to nothing and the two
            # Its after this one would pass by looking at an empty set.
            $hit = Get-ForbiddenJsonCmdletHit -Path $script:Psm1Path -InFunction $script:ChainFunctions
            @($hit.MatchedFunction) | Should -Be @($script:ChainFunctions | Sort-Object)
        }

        It 'no chain function calls any of the three' {
            $hit = Get-ForbiddenJsonCmdletHit -Path $script:Psm1Path -InFunction $script:ChainFunctions
            @($hit.CallNames) | Should -BeNullOrEmpty
        }

        It 'and the names appear in no executable token inside a chain function' {
            # Comments and docstrings may name them -- the psm1's own header explains at length
            # that it is "Deliberately not ConvertTo-Json", and that sentence is the reason the
            # ban is legible. FINDINGS F32: a grep would go red on exactly that sentence.
            $hit = Get-ForbiddenJsonCmdletHit -Path $script:Psm1Path -InFunction $script:ChainFunctions
            @($hit.BareTokens) | Should -BeNullOrEmpty
        }

        It 'the calls the module DOES make are all on the Python transport, inside Invoke-LedgerForce' {
            # Measured, and it corrected this suite: the first version of the check banned the
            # three cmdlets from the whole file and went red, because Invoke-LedgerForce uses
            # them for the payload it writes to the snake's stdin and the NDJSON events it reads
            # back. Those bytes are a subprocess protocol, not a record, and nothing hashes them.
            # Stating the boundary is worth more than moving the check until it passes.
            $all = Get-ForbiddenJsonCmdletHit -Path $script:Psm1Path
            $inForce = Get-ForbiddenJsonCmdletHit -Path $script:Psm1Path -InFunction @('Invoke-LedgerForce')
            @($all.CallNames).Count | Should -Be 3
            @($inForce.CallNames).Count | Should -Be 3
            @($inForce.CallNames | Sort-Object) | Should -Be @('ConvertFrom-Json', 'ConvertTo-Json', 'ConvertTo-Json')
            # ...and Invoke-LedgerForce is NOT a chain function: it delegates the record to
            # Add-LedgerRecord, which is.
            $script:ChainFunctions | Should -Not -Contain 'Invoke-LedgerForce'
        }

        It 'the file does discuss them in comments, so the check above is not passing by silence' {
            [System.IO.File]::ReadAllText($script:Psm1Path) | Should -Match 'ConvertTo-Json'
        }

        It 'the planted-defect twin: the same predicate fires on a real call' {
            $planted = @(
                'function Write-Thing {'
                '    param($r)'
                '    $line = ConvertTo-Json $r -Compress'
                '    return $line'
                '}'
            ) -join "`n"
            $hit = Get-ForbiddenJsonCmdletHit -Text $planted
            $hit.Any | Should -BeTrue
            $hit.CallNames | Should -Contain 'ConvertTo-Json'
        }

        It 'and the twin fires through the -InFunction scope too, not only whole-file' {
            # The scoped form is the one the chain checks actually use, so it is the one that
            # has to be shown capable of failing.
            $planted = @(
                'function Add-LedgerRecord {'
                '    param($r)'
                '    $line = ConvertTo-Json $r -Compress'
                '}'
                'function Something-Else { $x = ConvertFrom-Json $y }'
            ) -join "`n"
            $hit = Get-ForbiddenJsonCmdletHit -Text $planted -InFunction @('Add-LedgerRecord')
            @($hit.MatchedFunction) | Should -Be @('Add-LedgerRecord')
            @($hit.CallNames) | Should -Be @('ConvertTo-Json')
        }

        It 'the twin also fires when the call hides in a comment-heavy file' {
            $planted = @(
                '<#'
                '    This module deliberately avoids ConvertTo-Json on the chain.'
                '#>'
                '# ConvertFrom-Json turns ts into a datetime.'
                '$x = Test-Json -Json $text'
            ) -join "`n"
            $hit = Get-ForbiddenJsonCmdletHit -Text $planted
            $hit.CallNames | Should -Contain 'Test-Json'
        }

        It 'the twin does NOT fire on comments alone, which is the whole point of parsing' {
            $planted = @(
                '<#'
                '    Deliberately not ConvertTo-Json. The canonical bytes feed a hash chain.'
                '#>'
                '# read back with System.Text.Json, not ConvertFrom-Json'
                '$x = 1'
            ) -join "`n"
            (Get-ForbiddenJsonCmdletHit -Text $planted).Any | Should -BeFalse
        }

        It 'what the chain uses instead is System.Text.Json and a hand-built canonical string' {
            $text = [System.IO.File]::ReadAllText($script:Psm1Path)
            $text | Should -Match 'System\.Text\.Json\.JsonDocument\]::Parse'
            $text | Should -Match 'function ConvertTo-LedgerCanonicalJson'
        }
    }

    # ================================================================== footprint

    Context 'the suite left no footprint' {

        It 'nothing under modules/ledger was created, changed or removed' {
            $after = Get-TreeSnapshot -Root $script:ModuleRoot
            @($after.Keys) | Should -Be @($script:BeforeSnapshot.Keys)
            foreach ($k in $after.Keys) {
                $after[$k] | Should -BeExactly $script:BeforeSnapshot[$k] -Because "$k must not have changed"
            }
        }

        It 'no live ledger was created at the module default path' {
            # Resolve-LedgerPath's default is <repo>/.ledger/ledger.jsonl. Substrate has no
            # such file and this suite must not be the thing that gives it one.
            Join-Path $script:RepoRoot '.ledger' | Should -Not -Exist
        }

        It 'and every temp fixture it did create is gone' {
            # The anti-vacuity guard first. FINDINGS F26: a cleanup assertion over an empty
            # list is the most flattering lie a suite can tell, and it is the one thing here
            # that has to be asserted rather than assumed.
            $script:TempDirs.Count | Should -BeGreaterThan 3
            foreach ($d in $script:TempDirs) {
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            }
            foreach ($d in $script:TempDirs) { $d | Should -Not -Exist }
        }
    }
}
