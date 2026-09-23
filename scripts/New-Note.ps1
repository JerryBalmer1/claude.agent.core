#Requires -Version 7.4
<#
.SYNOPSIS
    Writes one raw note: docs/notes/raw/YYYY-MM-DD-HHmm-<slug>.md, four-line front matter, then the body.

.DESCRIPTION
    The body comes from exactly one of -Body, -BodyFile, or the pipeline / stdin when neither
    is given. -BodyFile is in its own parameter set, so combining it with -Body or with piped
    input is a binding error rather than a silent choice between them.
    Refuses to overwrite an existing note. Prints the path it wrote.
#>
[CmdletBinding(DefaultParameterSetName = 'Body')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z0-9]+(-[a-z0-9]+)*$')]
    [string] $Slug,

    # ValueFromPipeline: `pwsh -File` hands redirected stdin to the script as pipeline input,
    # one line per object. Without a pipeline-bound parameter every line is a binding error.
    [Parameter(ParameterSetName = 'Body', ValueFromPipeline)]
    [string] $Body,

    [Parameter(ParameterSetName = 'BodyFile', Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string] $BodyFile,

    [string] $Source = 'chat'
)

begin {
    $ErrorActionPreference = 'Stop'
    $PSNativeCommandUseErrorActionPreference = $true
    $lines = [System.Collections.Generic.List[string]]::new()
}

process {
    if ($PSBoundParameters.ContainsKey('Body')) { $lines.Add($Body) }
}

end {
    $text = if ($PSCmdlet.ParameterSetName -eq 'BodyFile') {
        Get-Content -LiteralPath $BodyFile -Raw
    } elseif ($lines.Count -gt 0) {
        $lines -join "`n"
    } else {
        [Console]::In.ReadToEnd()
    }
    if ($null -eq $text) { $text = '' }

    $now  = Get-Date
    $root = (Resolve-Path (Join-Path $PSScriptRoot '../docs/notes')).Path -replace '\\', '/'
    $path = "$root/raw/$($now.ToString('yyyy-MM-dd-HHmm'))-$Slug.md"

    $note = @(
        '---'
        "date: $($now.ToString('yyyy-MM-ddTHH:mm:sszzz'))"
        "slug: $Slug"
        "source: $Source"
        'status: raw'
        '---'
        ''
        ($text -replace "`r`n", "`n").TrimEnd("`n")
    ) -join "`n"

    # CreateNew throws if the file exists: that is the refusal to overwrite.
    $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write)
    try {
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes("$note`n")
        $stream.Write($bytes, 0, $bytes.Length)
    } finally {
        $stream.Dispose()
    }

    $path
}
