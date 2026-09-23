#Requires -Version 7.4
<#
.SYNOPSIS
    Renders docs/POLICY.md and .github/PULL_REQUEST_TEMPLATE.md from config/repo.json.

.DESCRIPTION
    config/repo.json is the single source of truth. Everything that restates it is generated
    here, so the policy cannot be true in one file and false in another.

    Output is DETERMINISTIC by construction: no timestamps, no host name, no culture-dependent
    formatting, LF line endings, UTF-8 without a BOM. The same config renders byte-identical
    files on a Windows clone and on an ubuntu runner. That property is what makes -Check
    meaningful - a byte comparison is only evidence if the bytes are reproducible.

    -Check does not write to the working tree. It renders in memory and compares sha256 against
    the committed files, exiting 1 on drift. CI check "generated-match-config" is this switch.

.EXAMPLE
    pwsh -NoProfile -File scripts/Generate-Policy.ps1

.EXAMPLE
    pwsh -NoProfile -File scripts/Generate-Policy.ps1 -Check
#>
[CmdletBinding()]
param(
    [switch]$Check
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version 3.0

$RepoRoot   = Split-Path $PSScriptRoot -Parent
$ConfigPath = Join-Path $RepoRoot 'config/repo.json'
$SchemaPath = Join-Path $RepoRoot 'schemas/repo.schema.json'

function Get-Utf8NoBom { [System.Text.UTF8Encoding]::new($false) }

function Get-Sha256Hex {
    param([Parameter(Mandatory)] [byte[]]$Bytes)
    return [System.Convert]::ToHexString([System.Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function ConvertTo-LfBytes {
    <#
        One join, one encoding, one trailing newline. Every renderer in this file returns a
        [string[]] of lines and this is the only thing that turns lines into bytes, so there is
        exactly one place where a line ending can be got wrong.
    #>
    # AllowEmptyString is load-bearing: a mandatory [string[]] refuses an element that is the
    # empty string, and every blank line in the templates is exactly that.
    param([Parameter(Mandatory)] [AllowEmptyCollection()] [AllowEmptyString()] [string[]]$Lines)
    $text = ($Lines -join "`n") + "`n"
    return (Get-Utf8NoBom).GetBytes($text)
}

function Get-SectionFlag {
    <#
        StrictMode-safe read of an optional boolean on a pull_request.sections entry.

        `collapsible` and `open` are optional in schemas/repo.schema.json, and a JSON Schema
        `default` is an annotation, not a rule -- nothing writes the property into the parsed
        object. Under Set-StrictMode -Version 3.0 a bare $Section.collapsible on a section that
        omits it is a terminating error, so the default is applied here, in one place, rather
        than by every caller remembering to guard.
    #>
    param(
        [Parameter(Mandatory)] $Section,
        [Parameter(Mandatory)] [string]$Name
    )
    $prop = $Section.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $false }
    return [bool]$prop.Value
}

function Get-OptionalValue {
    <#
        StrictMode-safe read of an optional property, with the default applied here for the same
        reason Get-SectionFlag applies its own: a JSON Schema `default` is an annotation, and
        nothing writes the property into the parsed object.
    #>
    param(
        [Parameter(Mandatory)] [AllowNull()] $Object,
        [Parameter(Mandatory)] [string]$Name,
        $Default = $null
    )
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return $prop.Value
}

function ConvertTo-XmlText {
    <#
        The five XML predefined entities, escaped by hand. Config text reaches the SVG through
        here, so a title containing an ampersand produces a valid document rather than one a
        browser silently refuses to draw.
    #>
    param([Parameter(Mandatory)] [AllowEmptyString()] [string]$Text)
    return $Text.
        Replace('&', '&amp;').
        Replace('<', '&lt;').
        Replace('>', '&gt;').
        Replace('"', '&quot;').
        Replace("'", '&apos;')
}

function Get-HeaderRawUrl {
    <#
        Where the banner lives for a reader who is not inside a checkout. A pull request body is
        rendered outside the repository, so a relative path resolves to nothing there; the README
        is rendered inside it, so a relative path is correct there and is what it uses. Both
        halves of that come out of config: the slug and the long-lived branch name.

        The host is github.com/<slug>/blob/<branch>/...?raw=true, not raw.githubusercontent.com.
        raw.githubusercontent is an unauthenticated origin: while this repository is private it
        answers 404 to the image fetch a rendered PR body makes, whatever is on the branch --
        measured, not assumed, and recorded in FINDINGS. The blob URL is served through the
        viewer's own session, so it renders for everyone who can already see the pull request.
    #>
    param([Parameter(Mandatory)] $Config)
    return 'https://github.com/{0}/blob/{1}/assets/header.svg?raw=true' -f $Config.repo, $Config.branches.develop
}

function Get-RepoConfig {
    if (-not (Test-Path -LiteralPath $ConfigPath)) { throw "config not found: $ConfigPath" }
    $json = [System.IO.File]::ReadAllText($ConfigPath)

    # Validate before rendering. A config that does not satisfy its own schema must never
    # reach the templates - a bad review.mode would otherwise be rendered as policy.
    if (Test-Path -LiteralPath $SchemaPath) {
        $null = Test-Json -Json $json -SchemaFile $SchemaPath -ErrorAction Stop
        Write-Verbose 'config validates against schemas/repo.schema.json'
    }
    else {
        Write-Warning "schema missing at $SchemaPath - rendering an unvalidated config"
    }
    return ($json | ConvertFrom-Json -Depth 20)
}

function New-HeaderSvg {
    <#
        The committed banner. Pure SVG: no script, no external reference, no font download, no
        network. That is the whole reason it is generated and committed rather than hotlinked from
        an image service -- a banner served by somebody else is a dependency that can change what
        this repository looks like, or stop answering, without a commit.

        ANIMATION IS SMIL, AND THAT IS AN ASSUMPTION, NOT A MEASUREMENT. Nothing here fetched a
        page to watch it run, so the reasoning is stated instead of a result being claimed. An SVG
        referenced from Markdown is loaded as an IMAGE, and in that context a browser runs
        declarative animation but refuses script and external resources. <animate> and
        <animateTransform> are declarative and need no <style> element, so they survive a
        sanitiser that strips <style> as well as one that strips <script>; a CSS @keyframes
        version would depend on <style> surviving the trip. If the banner ever renders still,
        this paragraph is where to look first.

        DETERMINISM. No timestamp, no host name, no randomness, and every coordinate is an
        integer -- so no decimal separator can vary with culture. Every number derives from
        height and every colour from palette, which is what makes the drift check evidence
        rather than decoration.

        The wave animates by interpolating the path's `d` between two phases with an identical
        segment structure, rather than by translating a double-width band. Translating one would
        drag the gradient with it and slide the colours; interpolating leaves everything but the
        crest still.
    #>
    param([Parameter(Mandatory)] $Config)

    $header = Get-OptionalValue -Object $Config -Name 'header'
    if ($null -eq $header) { throw 'New-HeaderSvg: config/repo.json has no header block' }

    $title     = ConvertTo-XmlText ([string](Get-OptionalValue -Object $header -Name 'title'))
    $subtitle  = ConvertTo-XmlText ([string](Get-OptionalValue -Object $header -Name 'subtitle'  -Default ''))
    $palette   = @(Get-OptionalValue -Object $header -Name 'palette'   -Default @('111827', '0E7490'))
    $shape     = [string](Get-OptionalValue -Object $header -Name 'shape'     -Default 'rect')
    $height    = [int](   Get-OptionalValue -Object $header -Name 'height'    -Default 200)
    $animation = [string](Get-OptionalValue -Object $header -Name 'animation' -Default 'none')

    $w      = 1200
    $waveH  = if ($shape -in @('wave', 'waving')) { 40 } else { 0 }
    $bottom = $height - $waveH
    $amp    = 16

    # Three periods across the viewBox, walked right to left so the path closes back at the
    # origin. Both phases have the same segments in the same order, which is what `d`
    # interpolation requires -- only the control points' sign differs.
    function Get-WavePath {
        param([int]$Base, [int]$Amp, [int]$Height, [int]$Width, [int]$Sign)
        $sb = [System.Text.StringBuilder]::new()
        [void]$sb.Append("M 0 0 L $Width 0 L $Width $Base")
        $period = [int]($Width / 3)
        for ($x = $Width; $x -gt 0; $x -= $period) {
            $c1x = $x - [int]($period / 4)
            $c2x = $x - [int]($period * 3 / 4)
            $c1y = $Base + ($Sign * $Amp)
            $c2y = $Base - ($Sign * $Amp)
            [void]$sb.Append(" C $c1x $c1y, $c2x $c2y, $($x - $period) $Base")
        }
        [void]$sb.Append(' Z')
        return $sb.ToString()
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $add = { param([string]$s) $lines.Add($s) }

    & $add '<?xml version="1.0" encoding="UTF-8"?>'
    & $add '<!--'
    & $add '  GENERATED FILE - DO NOT EDIT BY HAND.'
    & $add '  Rendered from config/repo.json by scripts/Generate-Policy.ps1.'
    & $add '  CI check "generated-match-config" fails the build if this file and the config disagree.'
    & $add '-->'
    & $add ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {0} {1}" width="{0}" height="{1}" role="img" aria-label="{2}">' -f $w, $height, $title)
    & $add '  <defs>'
    & $add '    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="0">'
    if ($palette.Count -eq 1) {
        & $add ('      <stop offset="0%" stop-color="#{0}"/>' -f $palette[0])
    }
    else {
        for ($i = 0; $i -lt $palette.Count; $i++) {
            $offset = [int](($i * 100) / ($palette.Count - 1))
            & $add ('      <stop offset="{0}%" stop-color="#{1}"/>' -f $offset, $palette[$i])
        }
    }
    & $add '    </linearGradient>'
    & $add '  </defs>'

    switch ($shape) {
        'rounded' { & $add ('  <rect x="0" y="0" width="{0}" height="{1}" rx="24" fill="url(#bg)"/>' -f $w, $height) }
        'soft'    { & $add ('  <rect x="0" y="0" width="{0}" height="{1}" rx="48" fill="url(#bg)"/>' -f $w, $height) }
        'rect'    { & $add ('  <rect x="0" y="0" width="{0}" height="{1}" fill="url(#bg)"/>' -f $w, $height) }
        default   {
            $phaseA = Get-WavePath -Base $bottom -Amp $amp -Height $height -Width $w -Sign 1
            if ($shape -eq 'waving') {
                $phaseB = Get-WavePath -Base $bottom -Amp $amp -Height $height -Width $w -Sign -1
                & $add ('  <path fill="url(#bg)" d="{0}">' -f $phaseA)
                & $add ('    <animate attributeName="d" values="{0};{1};{0}" dur="7s" repeatCount="indefinite"/>' -f $phaseA, $phaseB)
                & $add '  </path>'
            }
            else {
                & $add ('  <path fill="url(#bg)" d="{0}"/>' -f $phaseA)
            }
        }
    }

    # A system font stack, because an SVG loaded as an image cannot fetch a webfont. Which glyphs
    # a given machine draws is not deterministic; the BYTES are, and the bytes are what is checked.
    $titleSize = [int][math]::Max(28, [math]::Floor($height * 0.19))
    $subSize   = [int][math]::Max(14, [math]::Floor($height * 0.085))
    $titleY    = [int][math]::Floor($height * 0.44)
    $subY      = [int][math]::Floor($height * 0.62)
    $font      = 'Segoe UI, Ubuntu, Helvetica Neue, Arial, sans-serif'
    $startOpacity = if ($animation -eq 'fadeIn') { '0' } else { '1' }

    & $add ('  <g text-anchor="middle" font-family="{0}" fill="#FFFFFF" opacity="{1}">' -f $font, $startOpacity)
    switch ($animation) {
        'fadeIn'    { & $add '    <animate attributeName="opacity" from="0" to="1" dur="1400ms" fill="freeze"/>' }
        'twinkling' { & $add '    <animate attributeName="opacity" values="1;0.4;1" dur="3s" repeatCount="indefinite"/>' }
        default     { }
    }
    & $add ('    <text x="{0}" y="{1}" font-size="{2}" font-weight="700" letter-spacing="1">{3}</text>' -f
            [int]($w / 2), $titleY, $titleSize, $title)
    if ($subtitle) {
        & $add ('    <text x="{0}" y="{1}" font-size="{2}" opacity="0.82">{3}</text>' -f
                [int]($w / 2), $subY, $subSize, $subtitle)
    }
    & $add '  </g>'
    & $add '</svg>'

    return $lines.ToArray()
}

function New-PolicyMarkdown {
    param([Parameter(Mandatory)] $Config)

    $lines = [System.Collections.Generic.List[string]]::new()
    $add = { param([string]$s) $lines.Add($s) }

    & $add '<!--'
    & $add '  GENERATED FILE - DO NOT EDIT BY HAND.'
    & $add '  Rendered from config/repo.json by scripts/Generate-Policy.ps1.'
    & $add '  Edit the config and regenerate:'
    & $add '      pwsh -NoProfile -File scripts/Generate-Policy.ps1'
    & $add '  CI check "generated-match-config" fails the build if this file and the config disagree.'
    & $add '-->'
    & $add ''
    & $add "# Policy - $($Config.repo)"
    & $add ''
    & $add 'Every rule below is rendered from `config/repo.json`. This file is evidence of the'
    & $add 'config, not a second copy of it. If you want to change a rule, change the config.'
    & $add ''
    & $add '## Branch flow'
    & $add ''
    & $add "Long-lived branches: ``$($Config.branches.main)`` and ``$($Config.branches.develop)``."
    & $add "Work starts on a branch named ``$($Config.branches.feature_prefix)<something>``."
    & $add ''
    & $add '| From | Into |'
    & $add '|---|---|'
    foreach ($row in $Config.flow) {
        & $add ('| `{0}` | `{1}` |' -f $row[0], $row[1])
    }
    & $add ''
    & $add 'Any other pair is refused by the `branch-flow` check. There is no path that skips'
    & $add ('`{0}`.' -f $Config.branches.develop)
    & $add ''
    & $add '## Merge strategy'
    & $add ''
    & $add ('Strategy: **{0}**. Delete the branch on merge: **{1}**.' -f
            $Config.merge.strategy, $Config.merge.delete_branch_on_merge.ToString().ToLowerInvariant())
    & $add ''
    & $add 'Merge commits only. Never squash, never rebase, never force-push, never amend anything'
    & $add 'already pushed. A merge commit has two parents and that is the evidence; a squash has'
    & $add 'one parent and a hash that corresponds to nothing that was ever reviewed.'
    & $add ''
    & $add '## Review mode'
    & $add ''
    & $add ('Mode: **{0}**.' -f $Config.review.mode)
    & $add ''
    & $add ('> {0}' -f $Config.review.note)
    & $add ''
    if ($Config.review.mode -eq 'auto') {
        & $add 'While the mode is `auto`, `.github/workflows/automerge.yml` merges a pull request'
        & $add 'whose required checks are all green, with a merge commit. No human approval is'
        & $add 'waited for. Flipping the mode to `human` and regenerating stops that on the next PR.'
    }
    else {
        & $add 'While the mode is `human`, `.github/workflows/automerge.yml` stands down and exits'
        & $add 'without merging. A human merges, and the checks below still have to be green.'
    }
    & $add ''
    & $add '## Checks that must be green'
    & $add ''
    foreach ($c in $Config.required_checks) {
        & $add ('- `{0}`' -f $c)
    }
    & $add ''
    & $add 'One CI job per entry, named exactly the string above. The `generated-match-config` job'
    & $add 'asserts that the set of job names in `.github/workflows/ci.yml` equals this list, so'
    & $add 'the workflow cannot quietly drop a check.'
    & $add ''
    & $add '## Commit trailer'
    & $add ''
    & $add ('Every commit carries a `{0}:` trailer as its **last line**. Allowed values:' -f $Config.trailer.key)
    & $add ''
    foreach ($a in $Config.trailer.allowed) {
        & $add ('- `{0}: {1}`' -f $Config.trailer.key, $a)
    }
    & $add ''
    & $add 'Verify your own commit before pushing:'
    & $add ''
    & $add '```powershell'
    & $add ("git log -1 --format='%(trailers:key={0},valueonly)'" -f $Config.trailer.key)
    & $add '```'
    & $add ''
    & $add 'The trailer is **operator-asserted**. It is not a signature and it does not prove'
    & $add 'anything. It is a place to be caught lying, checked by `trailer-guard`.'
    & $add ''
    & $add '## Script version floor'
    & $add ''
    & $add ('PowerShell **{0}+** only. Every `.ps1` and `.psm1` in this repository starts with:' -f $Config.scripts.requires_version)
    & $add ''
    & $add '```powershell'
    & $add ('#Requires -Version {0}' -f $Config.scripts.requires_version)
    & $add '```'
    & $add ''
    & $add 'No bash, no sh, no heredocs - including in CI, where workflow steps use `shell: pwsh`'
    & $add 'and call scripts in `scripts/`. The `requires-header` check enforces the header.'
    & $add ''
    & $add '## Runtimes'
    & $add ''
    & $add ('PowerShell **{0}+**. This section is the whole list of languages this repository is' -f $Config.runtimes.powershell)
    & $add 'allowed to contain, so the floor is restated here; it must equal the one above, and'
    & $add '`Test-Runtimes.ps1` fails the `requires-header` check if the two ever disagree.'
    & $add ''
    & $add ('Python **{0}+** is permitted, and only under:' -f $Config.runtimes.python.version)
    & $add ''
    foreach ($p in $Config.runtimes.python.allowed_under) {
        & $add ('- `{0}`' -f $p)
    }
    & $add ''
    # The rule itself is config/repo.json -> runtimes.rule, rendered verbatim. Prose that lives
    # in the generator is prose the config cannot be held to.
    $firstRule = $true
    foreach ($r in $Config.runtimes.rule) {
        if (-not $firstRule) { & $add '' }
        & $add $r
        $firstRule = $false
    }
    & $add ''
    & $add '## Owners'
    & $add ''
    foreach ($o in $Config.owners) {
        & $add ('- {0}' -f $o)
    }

    return $lines.ToArray()
}

function New-PullRequestTemplate {
    param([Parameter(Mandatory)] $Config)

    $lines = [System.Collections.Generic.List[string]]::new()
    $add = { param([string]$s) $lines.Add($s) }

    & $add '<!--'
    & $add '  GENERATED FILE - DO NOT EDIT BY HAND.'
    & $add '  Rendered from config/repo.json by scripts/Generate-Policy.ps1.'
    & $add '  CI check "generated-match-config" fails the build if this file and the config disagree.'
    & $add '-->'
    & $add ''
    # The banner, by absolute URL rather than by relative path: a pull request body is rendered
    # outside the repository and a relative path resolves to nothing there. The README is
    # rendered inside it and uses the relative path instead. Which absolute host, and why it is
    # not raw.githubusercontent while this repository is private, is in Get-HeaderRawUrl. A URL
    # is not a path token, so pr-body-links has nothing to say about this line -- confirmed by
    # running it on the generated template, not assumed.
    $headerBlock = Get-OptionalValue -Object $Config -Name 'header'
    if ($null -ne $headerBlock) {
        & $add ('![{0}]({1})' -f (Get-OptionalValue -Object $headerBlock -Name 'title'), (Get-HeaderRawUrl -Config $Config))
        & $add ''
    }
    # A collapsible section is <details> rather than `## heading`, because the sections this
    # template asks for are not the same size: How is one block per commit and grows with the
    # branch, Verify is a wall of pasted output. Both are worth having and neither is worth
    # scrolling past, so the shape is a config flag and not a house style argued per PR.
    foreach ($s in $Config.pull_request.sections) {
        if (Get-SectionFlag -Section $s -Name 'collapsible') {
            $openAttr = if (Get-SectionFlag -Section $s -Name 'open') { ' open' } else { '' }
            & $add ('<details{0}>' -f $openAttr)
            & $add ('<summary><strong>{0}</strong></summary>' -f $s.heading)
            & $add ''
            & $add ('<!-- {0} -->' -f $s.prompt)
            & $add ''
            & $add '</details>'
            & $add ''
        }
        else {
            & $add ('## {0}' -f $s.heading)
            & $add ''
            & $add ('<!-- {0} -->' -f $s.prompt)
            & $add ''
        }
    }
    & $add '## Base branch'
    & $add ''
    & $add 'Tick exactly one. Any other pair fails the `branch-flow` check.'
    & $add ''
    foreach ($row in $Config.flow) {
        & $add ('- [ ] `{0}` -> `{1}`' -f $row[0], $row[1])
    }
    & $add ''
    & $add '## Trailer'
    & $add ''
    & $add ('- [ ] Every commit ends with a `{0}:` trailer as its last line' -f $Config.trailer.key)
    & $add ('- [ ] The value is one of: {0}' -f (($Config.trailer.allowed | ForEach-Object { "``$_``" }) -join ', '))
    & $add ''
    & $add '## Merge'
    & $add ''
    & $add ('- [ ] This will land as a **{0} commit** - not a squash, not a rebase' -f $Config.merge.strategy)
    & $add ''
    & $add '## Checks that must be green'
    & $add ''
    foreach ($c in $Config.required_checks) {
        & $add ('- [ ] `{0}`' -f $c)
    }
    & $add ''
    if ($Config.review.mode -eq 'auto') {
        & $add ('`review.mode` is `{0}`: once every check above is green, the automerge workflow' -f $Config.review.mode)
        & $add 'merges this pull request without waiting for a human.'
    }
    else {
        & $add ('`review.mode` is `{0}`: the automerge workflow stands down. A human merges this.' -f $Config.review.mode)
    }
    & $add ''
    # The Wall states each rule WITHOUT naming a path, and that is not a style preference. This
    # template is the body a contributor fills in, and the pr-body-links step of `trailer-guard`
    # requires every path named in a body to be a sha-pinned permalink. A generated template
    # cannot carry one: it is rendered once, with no sha to pin to. So the boxes as shipped used
    # to fail the check they ship with, on `src/`, `modules/` and the Python prefix -- three reds
    # a contributor could only clear by editing a generated file. A rule nobody can satisfy is a
    # rule that gets switched off, so the rule is named here and the paths stay in the policy
    # document, which is rendered from the same config two functions above.
    & $add '## Wall'
    & $add ''
    & $add '- [ ] No module code outside the modules a run order named'
    & $add '- [ ] No sibling repository was touched'
    & $add '- [ ] No container surface was added - core is never a container'
    $pyPrefixCount = @($Config.runtimes.python.allowed_under).Count
    $pyPhrase = if ($pyPrefixCount -eq 1) { 'the one prefix' } else { "one of the $pyPrefixCount prefixes" }
    & $add ('- [ ] No Python outside {0} the runtime rule permits' -f $pyPhrase)

    return $lines.ToArray()
}

# ------------------------------------------------------------------------- run

$config = Get-RepoConfig
Write-Verbose "config: $ConfigPath (repo=$($config.repo), review.mode=$($config.review.mode))"

$targets = @(
    @{ Path = (Join-Path $RepoRoot 'docs/POLICY.md');                    Bytes = (ConvertTo-LfBytes (New-PolicyMarkdown      -Config $config)) }
    @{ Path = (Join-Path $RepoRoot '.github/PULL_REQUEST_TEMPLATE.md');  Bytes = (ConvertTo-LfBytes (New-PullRequestTemplate -Config $config)) }
)

# The banner is registered only when the config asks for one. A sibling repository that vendors
# core and omits the header block renders two files, not three, and its drift check stays honest
# about that rather than reporting a missing file it was never meant to have.
if ($null -ne (Get-OptionalValue -Object $config -Name 'header')) {
    $targets += @{ Path = (Join-Path $RepoRoot 'assets/header.svg'); Bytes = (ConvertTo-LfBytes (New-HeaderSvg -Config $config)) }
}

if ($Check) {
    $drift = 0
    foreach ($t in $targets) {
        $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $t.Path).Replace('\', '/')
        $want = Get-Sha256Hex -Bytes $t.Bytes
        if (-not (Test-Path -LiteralPath $t.Path)) {
            Write-Host "DRIFT  $rel -- missing; config renders $($t.Bytes.Length) bytes (sha256 $want)"
            $drift++
            continue
        }
        $onDisk = [System.IO.File]::ReadAllBytes($t.Path)
        $have   = Get-Sha256Hex -Bytes $onDisk
        if ($have -cne $want) {
            Write-Host "DRIFT  $rel -- on disk $have ($($onDisk.Length) bytes), config renders $want ($($t.Bytes.Length) bytes)"
            $drift++
        }
        else {
            Write-Host "OK     $rel -- $have"
        }
    }
    if ($drift -gt 0) {
        Write-Host "generated-match-config: FAIL -- $drift file(s) drifted from config/repo.json"
        Write-Host 'Fix: pwsh -NoProfile -File scripts/Generate-Policy.ps1   (then commit the result)'
        exit 1
    }
    Write-Host 'generated-match-config: PASS -- every generated file matches config/repo.json'
    exit 0
}

foreach ($t in $targets) {
    $dir = Split-Path $t.Path -Parent
    if (-not (Test-Path -LiteralPath $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force }
    [System.IO.File]::WriteAllBytes($t.Path, $t.Bytes)
    $rel = [System.IO.Path]::GetRelativePath($RepoRoot, $t.Path).Replace('\', '/')
    Write-Host ('wrote  {0} -- {1} bytes, sha256 {2}' -f $rel, $t.Bytes.Length, (Get-Sha256Hex -Bytes $t.Bytes))
}
exit 0
