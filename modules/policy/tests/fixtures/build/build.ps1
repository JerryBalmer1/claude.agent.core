#Requires -Version 7.4
<#
.SYNOPSIS
    Fixture for sandbox check 2. Reports the module's build identity from the manifest.

.DESCRIPTION
    Sandbox check 2 ran claude.build.policy's own repo-root build.ps1 and asserted three things:
    exit 0, stdout naming the version, stdout naming the module. build.ps1 is a repo-root script
    and was not part of the Phase 2.1 copy, so in substrate there is nothing to run.

    This fixture reproduces that script's contract against the copied manifest. It reads
    modules/policy/policy.psd1, cross-checks it against the build.json beside this
    file, and prints the same two [build] lines the original printed.

    The cross-check is the part worth carrying over rather than the printing. The original
    build.ps1's real work was refusing to report an identity the manifest did not agree with, so
    a fixture that only echoed two hard-coded strings would pass while proving nothing about the
    manifest. Here the version and the name both come OUT of the manifest, and a build.json that
    disagrees with it is a throw, not a warning.

    It never leaves the repository. The walk up from $PSScriptRoot stops at modules/policy: no
    sibling repo is read, and nothing outside this module is imported.

.EXAMPLE
    pwsh -NoProfile -File modules/policy/tests/fixtures/build/build.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true

# tests/fixtures/build -> tests/fixtures -> tests -> modules/policy. Three levels, inside the
# module, every time. Nothing here resolves a sibling repository.
$moduleRoot = [System.IO.Path]::GetFullPath(
    (Join-Path -Path $PSScriptRoot -ChildPath '..' -AdditionalChildPath '..', '..'))

$manifestPath = Join-Path -Path $moduleRoot -ChildPath 'policy.psd1'
$buildJsonPath = Join-Path -Path $PSScriptRoot -ChildPath 'build.json'

if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    throw "manifest not found at $manifestPath"
}

Write-Verbose "Reading $manifestPath"
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath

$version = $manifest.ModuleVersion
$name = [System.IO.Path]::GetFileNameWithoutExtension($manifestPath)

Write-Verbose "Reading $buildJsonPath"
$build = Get-Content -LiteralPath $buildJsonPath -Raw | ConvertFrom-Json

if ($build.version -ne $version) {
    throw "build.json version '$($build.version)' does not match manifest ModuleVersion '$version'"
}
if ($build.name -ne $name) {
    throw "build.json name '$($build.name)' does not match manifest name '$name'"
}

Write-Output "[build] version $version"
Write-Output "[build] name $name"

exit 0
