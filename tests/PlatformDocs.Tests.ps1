#Requires -Version 7.4
<#
    docs/claude-platform/ and scripts/Test-PlatformDocs.ps1 -- the dated, hash-pinned reference
    for Claude Code's extension surface, and the instrument that says whether it is still true.

    HERMETIC. Invoke-WebRequest is MOCKED for every call in this file, so CI never touches the
    network and a flaky docs server cannot turn `pester` red. The real fetch is a manual step:
    `pwsh -NoProfile -File scripts/Test-PlatformDocs.ps1` on a workstation.

    The mock cannot serve the real pages -- their bytes are not in this repository, on purpose --
    so it serves synthetic bodies. That decides the shape of the suite. Against the COMMITTED
    manifest, a synthetic body can only ever be drift, so the committed run asserts that every
    URL is reported as drift and none is waved through. The clean path is driven against a
    manifest built here from the committed URL list, with hashes computed over the synthetic
    bodies. Between the two, the script is exercised on exactly the URLs that ship.

    The script is invoked in-process with `&`, which is what makes its exit codes testable and
    what lets the mock reach it; tests/Preflight.Tests.ps1 records why -File and -Command do not.

    The second half asserts the tree's own contract, statically: front matter on every summary,
    every cited URL present in the manifest, and an acceptance test in every opportunity file.
#>

BeforeDiscovery {
    # Discovery-time lists, as global, for the reason tests/Preflight.Tests.ps1 records: a -ForEach
    # list built in BeforeAll is empty at discovery and zero cases report exactly like passing ones.
    $root = Split-Path $PSScriptRoot -Parent
    $dir  = Join-Path $root 'docs/claude-platform'
    $global:PlatformSummaryCases = @(Get-ChildItem -LiteralPath $dir -Filter '*.md' -File |
        Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
    $global:PlatformOpportunityCases = @(Get-ChildItem -LiteralPath (Join-Path $dir 'opportunities') -Filter '*.md' -File |
        Where-Object { $_.Name -ne 'INDEX.md' } | Sort-Object Name |
        ForEach-Object { @{ Name = $_.Name; Path = $_.FullName } })
}

BeforeAll {
    $script:RepoRoot     = Split-Path $PSScriptRoot -Parent
    $script:ScriptPath   = Join-Path $script:RepoRoot 'scripts/Test-PlatformDocs.ps1'
    $script:DocsDir      = Join-Path $script:RepoRoot 'docs/claude-platform'
    $script:ManifestPath = Join-Path $script:DocsDir 'manifest.json'
    $script:Manifest     = Get-Content -LiteralPath $script:ManifestPath -Raw | ConvertFrom-Json -Depth 20
    $script:Urls         = @($script:Manifest.pages | ForEach-Object { [string]$_.url })

    # GLOBAL, because a mock body runs in the scope of whatever called the mocked command -- here
    # the script under test -- where `script:` names that script's scope, not this file's.
    # Measured: as script: functions, every mocked fetch threw "not recognized" and the script,
    # correctly, reported every url as unseen.
    function global:Get-PlatformDocsTestBody {
        param([string]$Url)
        [System.Text.Encoding]::UTF8.GetBytes("synthetic body for $Url")
    }

    function script:Get-Sha {
        param([byte[]]$Bytes)
        [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    }

    function global:New-PlatformDocsTestResponse {
        param([int]$Status, [byte[]]$Bytes)
        [pscustomobject]@{ StatusCode = $Status; RawContentStream = [System.IO.MemoryStream]::new($Bytes) }
    }

    # A manifest over the committed URL list whose hashes match the synthetic bodies.
    function script:New-SyntheticManifest {
        param([string]$Path, [string[]]$Urls)
        $pages = foreach ($u in $Urls) {
            $b = global:Get-PlatformDocsTestBody $u
            [ordered]@{ url = $u; sha256 = (script:Get-Sha $b); fetched = '2026-09-23'; bytes = $b.Length }
        }
        [ordered]@{ schema = 'claude.agent.core/platform-docs/1'; pages = @($pages) } |
            ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    }

    function script:Invoke-Check {
        param([string]$Manifest)
        $global:LASTEXITCODE = $null
        $out = & $script:ScriptPath -ManifestPath $Manifest 6>$null 2>$null
        [pscustomobject]@{ Exit = $global:LASTEXITCODE; Drift = @($out | Where-Object { $_ -is [pscustomobject] }) }
    }

    # Every URL a summary cites, fragments stripped. Only the two docs hosts count as citations of
    # the platform; a link to this repository or anywhere else is not a claim about Claude Code.
    function script:Get-CitedUrls {
        param([string]$Text)
        @([regex]::Matches($Text, 'https://(?:code|platform)\.claude\.com/[^\s)\]>"''`]+') |
            ForEach-Object { ($_.Value -replace '#.*$', '').TrimEnd('.', ',', ';', ':') } |
            Sort-Object -Unique)
    }

    function script:Get-FrontMatter {
        param([string]$Text)
        $m = [regex]::Match($Text, '\A---\n(.*?)\n---\n', 'Singleline')
        if (-not $m.Success) { return $null }
        $m.Groups[1].Value
    }
}

AfterAll {
    Remove-Item -Path function:global:Get-PlatformDocsTestBody, function:global:New-PlatformDocsTestResponse -ErrorAction SilentlyContinue
}

Describe 'the manifest' {

    It 'lists llms.txt, the index every page was chosen from' {
        $script:Urls | Should -Contain 'https://code.claude.com/docs/llms.txt'
    }

    It 'has one entry per url, each with a 64-hex sha256, a positive byte count and an ISO date' {
        $script:Urls.Count | Should -BeGreaterThan 1
        ($script:Urls | Sort-Object -Unique).Count | Should -Be $script:Urls.Count
        foreach ($p in $script:Manifest.pages) {
            [string]$p.url     | Should -Match '^https://'
            [string]$p.sha256  | Should -MatchExactly '^[0-9a-f]{64}$'
            [string]$p.fetched | Should -Match '^\d{4}-\d{2}-\d{2}$'
            [int]$p.bytes      | Should -BeGreaterThan 0
        }
    }

    It 'names raw markdown pages, not the HTML ones' {
        foreach ($u in ($script:Urls | Where-Object { $_ -notlike '*/llms.txt' })) {
            $u | Should -Match '\.md$' -Because 'the .md URL is the raw page; the HTML page is a rendering of it'
        }
    }
}

Describe 'Test-PlatformDocs.ps1, with the network mocked' {

    BeforeAll {
        $script:Synthetic = Join-Path $TestDrive 'synthetic.json'
        script:New-SyntheticManifest -Path $script:Synthetic -Urls $script:Urls
    }

    It 'is clean, exit 0, when every url serves the bytes its hash was taken over' {
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 200 (global:Get-PlatformDocsTestBody $Uri) }
        $r = script:Invoke-Check $script:Synthetic
        $r.Exit | Should -Be 0
        $r.Drift | Should -BeNullOrEmpty
        Should -Invoke Invoke-WebRequest -Times $script:Urls.Count -Exactly
    }

    It 'reports exactly the one changed url, exit 1' {
        $changed = $script:Urls[1]
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 200 (global:Get-PlatformDocsTestBody $Uri) }
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 200 ([System.Text.Encoding]::UTF8.GetBytes('edited upstream')) } -ParameterFilter { $Uri -eq $changed }
        $r = script:Invoke-Check $script:Synthetic
        $r.Exit | Should -Be 1
        @($r.Drift.Url) | Should -Be @($changed)
    }

    It 'treats a 404 as drift, not as blindness' {
        $gone = $script:Urls[-1]
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 200 (global:Get-PlatformDocsTestBody $Uri) }
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 404 ([byte[]]@()) } -ParameterFilter { $Uri -eq $gone }
        $r = script:Invoke-Check $script:Synthetic
        $r.Exit | Should -Be 1
        @($r.Drift.Url) | Should -Be @($gone)
        $r.Drift[0].Reason | Should -Be 'HTTP 404'
    }

    It 'exits 2, never 0, when the network cannot be reached' {
        Mock Invoke-WebRequest { throw 'No such host is known.' }
        (script:Invoke-Check $script:Synthetic).Exit | Should -Be 2
    }

    It 'exits 1, not 2, when one url drifted and another could not be fetched' {
        $changed = $script:Urls[1]; $unreachable = $script:Urls[2]
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 200 (global:Get-PlatformDocsTestBody $Uri) }
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 200 ([byte[]]@(1)) } -ParameterFilter { $Uri -eq $changed }
        Mock Invoke-WebRequest { throw 'timed out' } -ParameterFilter { $Uri -eq $unreachable }
        $r = script:Invoke-Check $script:Synthetic
        $r.Exit | Should -Be 1
        @($r.Drift.Url) | Should -Be @($changed)
    }

    It 'exits 2 on a manifest with no pages, because checking nothing is not a clean result' {
        $empty = Join-Path $TestDrive 'empty.json'
        '{"schema":"x","pages":[]}' | Set-Content -LiteralPath $empty -Encoding utf8NoBOM
        Mock Invoke-WebRequest { throw 'must not be called' }
        (script:Invoke-Check $empty).Exit | Should -Be 2
        Should -Invoke Invoke-WebRequest -Times 0 -Exactly
    }

    It 'exits 2 on a manifest entry with no sha256' {
        $bad = Join-Path $TestDrive 'bad.json'
        '{"pages":[{"url":"https://code.claude.com/docs/llms.txt","fetched":"2026-09-23","bytes":1}]}' |
            Set-Content -LiteralPath $bad -Encoding utf8NoBOM
        Mock Invoke-WebRequest { throw 'must not be called' }
        (script:Invoke-Check $bad).Exit | Should -Be 2
    }

    It 'against the COMMITTED manifest, reports every url as drift when served bytes it was not taken over' {
        # The committed hashes are over the real pages. A synthetic body matching one of them would
        # be a SHA-256 collision, so every url must come back as drift -- a script that waved any of
        # them through would be comparing against something other than the committed manifest.
        Mock Invoke-WebRequest { global:New-PlatformDocsTestResponse 200 (global:Get-PlatformDocsTestBody $Uri) }
        $r = script:Invoke-Check $script:ManifestPath
        $r.Exit | Should -Be 1
        @($r.Drift.Url | Sort-Object) | Should -Be @($script:Urls | Sort-Object)
        Should -Invoke Invoke-WebRequest -Times $script:Urls.Count -Exactly
    }
}

Describe 'every topic summary carries its provenance' {

    It 'there is at least one summary to check' {
        $global:PlatformSummaryCases.Count | Should -BeGreaterThan 0 -Because 'zero cases report exactly like passing ones'
    }

    It '<Name> opens with front matter naming verified, sources and scope' -ForEach $global:PlatformSummaryCases {
        $text = (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
        $fm = script:Get-FrontMatter $text
        $fm | Should -Not -BeNullOrEmpty
        $fm | Should -Match '(?m)^verified:\s*\d{4}-\d{2}-\d{2}\s*$'
        $fm | Should -Match '(?m)^sources:\s*$'
        $fm | Should -Match '(?m)^\s+-\s+https://'
        $fm | Should -Match '(?m)^scope:\s*\S'
    }

    It '<Name> cites only urls the manifest pins' -ForEach $global:PlatformSummaryCases {
        $cited = script:Get-CitedUrls (Get-Content -LiteralPath $Path -Raw)
        $cited | Should -Not -BeNullOrEmpty
        $missing = @($cited | Where-Object { $script:Urls -notcontains $_ })
        $missing | Should -BeNullOrEmpty -Because 'a claim whose source is not pinned cannot be checked for drift'
    }

    It '<Name> names a source under every section heading' -ForEach $global:PlatformSummaryCases {
        $lines = @((Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n" -split "`n")
        $unsourced = [System.Collections.Generic.List[string]]::new()
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch '^#{2,3} ' -or $lines[$i] -eq '## Not found in source') { continue }
            $next = @($lines[($i + 1)..([Math]::Min($i + 3, $lines.Count - 1))] | Where-Object { $_.Trim() })
            if ($next.Count -eq 0 -or $next[0] -notmatch '^Source: https://') { $unsourced.Add($lines[$i]) }
        }
        $unsourced | Should -BeNullOrEmpty
    }
}

Describe 'every opportunity is testable' {

    It 'there is at least one opportunity to check' {
        $global:PlatformOpportunityCases.Count | Should -BeGreaterThan 0 -Because 'zero cases report exactly like passing ones'
    }

    It '<Name> has a non-empty acceptance test section' -ForEach $global:PlatformOpportunityCases {
        $text = (Get-Content -LiteralPath $Path -Raw) -replace "`r`n", "`n"
        $m = [regex]::Match($text, '(?ms)^## Acceptance test\s*\n(.*?)(?=^## |\z)')
        $m.Success | Should -BeTrue
        $m.Groups[1].Value.Trim() | Should -Not -BeNullOrEmpty
    }

    It '<Name> cites only urls the manifest pins' -ForEach $global:PlatformOpportunityCases {
        $cited = script:Get-CitedUrls (Get-Content -LiteralPath $Path -Raw)
        $cited | Should -Not -BeNullOrEmpty -Because 'an opportunity says what the feature does, cited'
        @($cited | Where-Object { $script:Urls -notcontains $_ }) | Should -BeNullOrEmpty
    }

    It 'INDEX.md lists every opportunity file, and nothing else' {
        $index = Get-Content -LiteralPath (Join-Path $script:DocsDir 'opportunities/INDEX.md') -Raw
        $listed = @([regex]::Matches($index, '\]\(([a-z0-9-]+\.md)\)') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $onDisk = @($global:PlatformOpportunityCases | ForEach-Object { $_.Name } | Sort-Object)
        $listed | Should -Be $onDisk
    }
}
