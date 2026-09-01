<#
.SYNOPSIS
  Read-only capability detector for native Windows.

.DESCRIPTION
  Mirrors runtime/detect-capabilities.py. Prints one canonical JSON document on
  stdout with LF line endings. Never writes, installs, or mutates the work target.
#>
param(
    [string]$Project,
    [ValidateSet('claude', 'codex', 'cursor')][string]$HostName = 'claude',
    [switch]$Normalize
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

if ([string]::IsNullOrEmpty($Project)) {
    [Console]::Error.WriteLine('usage: detect-capabilities.ps1 -Project DIR [-HostName claude|codex|cursor] [-Normalize]')
    exit 1
}

$target = Get-NSAbsolutePath $Project
if (-not (Test-Path -LiteralPath $target -PathType Container)) {
    [Console]::Error.WriteLine("detect-capabilities: not a directory: $target")
    exit 1
}

$document = Get-NSCapabilityDocument -Project $target -HostName $HostName -SearchPath $env:PATH
if ($Normalize) {
    # Drop host so fixture/adapter parity can compare Claude/Codex/Cursor outputs.
    $document.Remove('host')
}

[Console]::Out.Write((ConvertTo-NSCanonicalJson $document))
[Console]::Out.Write("`n")
exit 0
