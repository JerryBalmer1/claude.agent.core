#Requires -Version 7.4
<#
    The plans module's suite.

    Unlike modules/policy, there is no sandbox script to port: image.builder shipped no suite for
    PlanValidator.ps1, and tests/plan.failfirst.ps1 -- the one file the run order names -- had
    already been deleted there for being theatre (FINDINGS.md F8). So every It below is written
    from a MEASUREMENT of the copied validator, not from a sentence about it.

    PHASE 7 REPOINTED THE COPY, and this file is where that cost is itemised. The old copy was
    blob 8e5da768: it restated the plan rules in PowerShell and never opened the schema, so
    -SchemaPath was exposed and inert (F5, F27, F28). The copy is now ff7b2baf, which reads
    schemas/plan.schema.json. Three assertions in this file INVERTED as a result, and they are
    marked where they sit:

      d   a step with no action USED TO FAIL and now passes -- the schema says nothing about the
          shape of a step. F4, inverted exactly as the run order predicted.
      f   a BLANK entry in skills_to_build USED TO FAIL and now passes -- items.type is "string"
          and the empty string is one. The run order did NOT predict this one; it was measured.
      i   -SchemaPath used to be inert and is now read: a schema-rejected plan fails and a
          missing schema path throws.

    Every one of those is the measurement, not a preference. Where a test and a sentence disagree
    here, the test records what ran. FINDINGS.md F70.

    Nothing in this file resolves a path outside modules/plans, and nothing in it writes.
#>

BeforeAll {
    # tests -> modules/plans. The module under test is the whole subtree above this file.
    $script:ModuleRoot    = Split-Path $PSScriptRoot -Parent
    $script:Manifest      = Join-Path $script:ModuleRoot 'plans.psd1'
    $script:ModuleFile    = Join-Path $script:ModuleRoot 'plans.psm1'
    $script:ValidatorFile = Join-Path $script:ModuleRoot 'PlanValidator.ps1'
    $script:SchemaFile    = Join-Path $script:ModuleRoot 'schemas' 'plan.schema.json'
    $script:Fixtures      = Join-Path $PSScriptRoot 'fixtures'

    # Phase 7's pin. Reproducible from image.builder with
    # `git rev-parse 5f71173:src/PlanValidator.ps1`. The module wraps this file; it never edits it.
    # Was 8e5da768 through Phase 6; see this file's header for the three Its that inverted.
    $script:ValidatorBlob = 'ff7b2baf02aec1765e3c6fdcf72490a5a06d5028'

    # NOT $env:TEMP -- unset on ubuntu-latest, where this suite's only gate runs. FINDINGS.md F26.
    # Nothing here writes to it; it is where the deliberately-absent schema path is built.
    $script:TempRoot = [System.IO.Path]::GetTempPath()

    function script:Get-Fixture {
        <#  A plan fixture, parsed the way image.builder's caller parses one: Get-Content -Raw
            piped through ConvertFrom-Json, so the object under test is a PSCustomObject and not a
            hashtable a test happened to find convenient. #>
        param([Parameter(Mandatory)][string]$Name)
        $path = Join-Path $script:Fixtures $Name
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "fixture missing: $path" }
        return (Get-Content -LiteralPath $path -Raw -Encoding utf8 | ConvertFrom-Json -Depth 20)
    }

    function script:Get-GitBlobSha1 {
        <#  The git blob id of a file's bytes ON DISK: sha1("blob <length>\0" + bytes).

            Computed here rather than shelled out to `git hash-object` on purpose. This asserts the
            bytes Pester can see, with no index, no clean filter and no git in the loop, so it is
            still a real assertion in a checkout where git is absent. .gitattributes pins
            `*.ps1 text eol=lf`, so the working tree is LF on both platforms and the two agree --
            verified against `git hash-object` before this was written. #>
        param([Parameter(Mandatory)][string]$Path)
        $bytes  = [System.IO.File]::ReadAllBytes($Path)
        $header = [System.Text.Encoding]::ASCII.GetBytes("blob $($bytes.Length)`0")
        $sha1   = [System.Security.Cryptography.SHA1]::HashData([byte[]]($header + $bytes))
        return ([BitConverter]::ToString($sha1) -replace '-', '').ToLowerInvariant()
    }

    function script:Get-ModuleSnapshot {
        <#  Relative path -> SHA-256 for every file under the module. Module-scoped, as policy's
            check 10 is: other suites in this repository legitimately rewrite files during the same
            Pester run, and a whole-repo snapshot would measure them instead of this. #>
        param([Parameter(Mandatory)][string]$Root)
        $snapshot = [ordered]@{}
        foreach ($file in (Get-ChildItem -LiteralPath $Root -Recurse -File -Force | Sort-Object FullName)) {
            $relative = [System.IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
            $snapshot[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        }
        return $snapshot
    }

    $script:SnapshotBefore = script:Get-ModuleSnapshot -Root $script:ModuleRoot

    Import-Module -Name $script:Manifest -Force -ErrorAction Stop
}

AfterAll {
    Remove-Module -Name 'plans' -Force -ErrorAction SilentlyContinue
}

Describe 'the plans module' -Tag 'plans' {

    It 'a -- the manifest imports, both functions are exported, and the validator is the byte-identical copy' {
        Get-Command -Name 'Test-PlanStructure' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty
        Get-Command -Name 'Get-PlanSchemaPath' -ErrorAction SilentlyContinue | Should -Not -BeNullOrEmpty

        $module = Get-Module -Name 'plans'
        $module | Should -Not -BeNullOrEmpty
        $module.Version.ToString() | Should -Be '0.2.0'
        (@($module.ExportedFunctions.Keys) | Sort-Object) -join ',' |
            Should -Be 'Get-PlanSchemaPath,Test-PlanStructure' -Because 'Phase 7 adds the second export and no third'
        $module.PowerShellVersion.ToString() | Should -Be '7.4'

        # The copy is the contract. If this moves, the module is wrapping something else and every
        # measured behaviour below is a claim about a file that is no longer in the tree.
        script:Get-GitBlobSha1 -Path $script:ValidatorFile |
            Should -BeExactly $script:ValidatorBlob -Because 'PlanValidator.ps1 stays byte-identical to image.builder@5f71173'
    }

    It 'b -- a valid plan passes' {
        $plan = script:Get-Fixture -Name 'valid-plan.json'
        Test-PlanStructure -Plan $plan | Should -BeTrue
    }

    It 'c1 -- a plan missing id fails' {
        $plan = script:Get-Fixture -Name 'missing-id.json'

        $message = ''
        $threw = $false
        try { Test-PlanStructure -Plan $plan | Out-Null }
        catch { $threw = $true; $message = $_.Exception.Message }

        $threw | Should -BeTrue
        $message | Should -BeExactly 'plan is missing required property ''id''' -Because 'the message is the copied validator''s, verbatim, which is how this test proves it delegated'
    }

    It 'c2 -- a plan missing steps fails' {
        $plan = script:Get-Fixture -Name 'missing-steps.json'

        $message = ''
        $threw = $false
        try { Test-PlanStructure -Plan $plan | Out-Null }
        catch { $threw = $true; $message = $_.Exception.Message }

        $threw | Should -BeTrue
        $message | Should -BeExactly 'plan is missing required property ''steps'''
    }

    It 'c3 -- a plan missing expected_output fails' {
        $plan = script:Get-Fixture -Name 'missing-expected-output.json'

        $message = ''
        $threw = $false
        try { Test-PlanStructure -Plan $plan | Out-Null }
        catch { $threw = $true; $message = $_.Exception.Message }

        $threw | Should -BeTrue
        $message | Should -BeExactly 'plan is missing required property ''expected_output'''
    }

    It 'd -- INVERTED IN PHASE 7: a step without action now PASSES, because the schema permits it' {
        # FINDINGS.md F4, inverted. The old copy restated a rule the schema never contained --
        # "every step carries a non-blank action" -- and F4 recorded the disagreement, resolving it
        # in the validator's favour because the validator was what image.builder ran. ff7b2baf
        # resolves it the other way: it reads the schema, the schema says `steps` is an array with
        # minItems 1 and nothing whatever about the shape of a step, so a step with no action is a
        # valid plan.
        #
        # The schema is still NOT edited. F70 records that this is a LOSS of strictness, measured
        # and accepted, not a defect in the wrapper: the run order predicted exactly this and told
        # this suite to measure rather than assume.
        $plan = script:Get-Fixture -Name 'step-without-action.json'
        $actionless = @($plan.steps | Where-Object { $_.PSObject.Properties.Name -notcontains 'action' })
        @($actionless).Count | Should -BeGreaterThan 0 -Because 'the fixture must still carry a step with no action key, or this proves nothing'

        Test-PlanStructure -Plan $plan | Should -BeTrue
    }

    It 'e -- skills_to_build absent passes' {
        # FINDINGS.md F3. The run order lists skills_to_build among the required fields whose
        # absence must fail; the schema requires only id, steps and expected_output, and the
        # validator agrees with the schema here. Testing it as required would assert the opposite
        # of the contract, so it is tested as optional.
        $plan = script:Get-Fixture -Name 'no-skills.json'
        $plan.PSObject.Properties.Name | Should -Not -Contain 'skills_to_build'
        Test-PlanStructure -Plan $plan | Should -BeTrue
    }

    It 'f -- INVERTED IN PHASE 7: a blank skill entry now passes, and an unknown one still does' {
        # MEASURED, and the run order did NOT predict this half. The old copy rejected an entry
        # that was blank once cast to string. ff7b2baf reads the schema instead, and the schema
        # says skills_to_build is an array of `"type": "string"` -- the empty string IS a string,
        # so a blank entry satisfies it. The check did not move; the contract it reads did.
        #
        # This is the second LOSS of strictness in this file and the one nobody scheduled. F70
        # records it, and BACKLOG.md carries the question of whether the schema should grow a
        # minLength, which is a decision about the plan contract and not this packet's to take.
        $blank = script:Get-Fixture -Name 'blank-skill.json'
        $blanks = @($blank.skills_to_build | Where-Object { [string]::IsNullOrWhiteSpace($_) })
        @($blanks).Count | Should -BeGreaterThan 0 -Because 'the fixture must still carry a blank entry, or this proves nothing'
        @($blanks)[0] | Should -BeOfType ([string]) -Because 'and it must be a STRING, which is precisely why the schema now accepts it'

        Test-PlanStructure -Plan $blank | Should -BeTrue

        $unknown = script:Get-Fixture -Name 'valid-plan.json'
        @($unknown.skills_to_build) | Should -Contain 'a-skill-that-does-not-exist'
        $result = Test-PlanStructure -Plan $unknown -InformationVariable info -WarningVariable warn
        $result | Should -BeTrue -Because 'an unknown skill name is accepted'
        @($info) | Should -BeNullOrEmpty -Because 'nothing lists the skill; "listed, not ignored" has no implementation'
        @($warn) | Should -BeNullOrEmpty
    }

    It 'g -- INVERTED IN PHASE 7: -SchemaPath is READ, and a plan the schema rejects now fails' {
        # This replaces the F27 inertness It, which proved the opposite of this one. F5's rule was
        # that the module may not claim schema validation on the strength of a parameter name, and
        # it is satisfied the only way it can be: by behaviour. id 42 is not `"type": "string"`.
        $command = Get-Command -Name 'Test-PlanStructure'
        $command.Parameters.Keys | Should -Contain 'SchemaPath'
        $script:SchemaFile | Should -Exist

        $schema = Get-Content -LiteralPath $script:SchemaFile -Raw -Encoding utf8 | ConvertFrom-Json -Depth 20
        $schema.properties.id.type | Should -Be 'string' -Because 'the rule being enforced must be in the schema, or this tests nothing'

        $badId = script:Get-Fixture -Name 'id-not-a-string.json'
        $badId.id | Should -BeOfType ([long]) -Because 'the fixture must still carry a non-string id'

        $message = ''
        $threw = $false
        try { Test-PlanStructure -Plan $badId | Out-Null }
        catch { $threw = $true; $message = $_.Exception.Message }

        $threw   | Should -BeTrue -Because 'the schema is opened now; this fixture passed under 8e5da768'
        $message | Should -BeExactly "plan property 'id' must be a string, got Int64"
    }

    It 'i -- INVERTED IN PHASE 7: a schema path that does not exist now throws' {
        # The other half of "it is read". Under 8e5da768 this returned $true, because nothing ever
        # opened the file. A validator that cannot find its contract must not return a verdict.
        $plan   = script:Get-Fixture -Name 'valid-plan.json'
        $absent = Join-Path $script:TempRoot ('plans-pester-{0}-no-such-schema.json' -f $PID)
        (Test-Path -LiteralPath $absent) | Should -BeFalse

        $message = ''
        $threw = $false
        try { Test-PlanStructure -Plan $plan -SchemaPath $absent | Out-Null }
        catch { $threw = $true; $message = $_.Exception.Message }

        $threw   | Should -BeTrue -Because 'no schema, no verdict'
        $message | Should -BeExactly "plan schema missing: $absent"

        # And the default still resolves inside the module, so the throw above is about the
        # argument and not about the module being unable to find its own schema.
        $verbose = @(Test-PlanStructure -Plan $plan -Verbose 4>&1 | ForEach-Object { $_.ToString() })
        ($verbose -join "`n") | Should -Match ([regex]::Escape($script:SchemaFile))
    }

    It 'j -- Get-PlanSchemaPath is the module''s, not the copy''s, and the copy''s would miss' {
        # The adaptation Phase 7 could not avoid, asserted from both sides so that neither can rot
        # quietly. image.builder keeps the validator in src/ and the schema in schemas/ at the repo
        # root, so the copy resolves '..' correctly THERE. This module is self-contained, so the
        # same expression climbs out of it.
        Get-PlanSchemaPath | Should -BeExactly ([System.IO.Path]::GetFullPath($script:SchemaFile))
        Get-PlanSchemaPath | Should -Exist

        # The copy's own version, invoked the way plans.psm1 loads it, in a child scope.
        $copied = & {
            . $script:ValidatorFile
            ${function:Get-PlanSchemaPath}
        }
        $copied | Should -Not -BeNullOrEmpty -Because 'ff7b2baf defines it; an older blob would not'

        $copiedAnswer = & $copied
        $copiedAnswer | Should -Not -Be (Get-PlanSchemaPath) -Because 'if these ever agree, the re-implementation is dead weight and should be deleted'
        (Test-Path -LiteralPath $copiedAnswer) | Should -BeFalse -Because "the copy resolves to $copiedAnswer, which is outside this module"
    }

    It 'h -- the suite wrote nothing under modules/plans' {
        $after = script:Get-ModuleSnapshot -Root $script:ModuleRoot

        # Anti-vacuity: an empty or truncated snapshot would compare nothing to nothing and report
        # green. The five files the module cannot exist without must be in it.
        foreach ($required in 'plans.psd1', 'plans.psm1', 'PlanValidator.ps1',
                              'schemas/plan.schema.json', 'tests/plans.Tests.ps1') {
            $script:SnapshotBefore.Contains($required) | Should -BeTrue -Because "'$required' must be in the before-snapshot"
        }

        $after.Count | Should -Be $script:SnapshotBefore.Count -Because "file count under the module must not move ($($script:SnapshotBefore.Count) before)"

        foreach ($relative in $script:SnapshotBefore.Keys) {
            $after.Contains($relative) | Should -BeTrue -Because "'$relative' must still be present"
            $after[$relative] | Should -Be $script:SnapshotBefore[$relative] -Because "'$relative' must be byte-identical"
        }
        foreach ($relative in $after.Keys) {
            $script:SnapshotBefore.Contains($relative) | Should -BeTrue -Because "'$relative' is new under the module; this suite writes nothing"
        }
    }
}
