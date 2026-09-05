<#
.SYNOPSIS
  Baseline-to-now comparison for native Windows.

.DESCRIPTION
  Mirrors runtime/evidence-compare.sh byte for byte on the bundled PowerShell
  alone. Reruns nothing: it reads the records sharing the baseline's source class
  and classifies each as new, cleared, unchanged, regressed, unavailable,
  rejected-duplicate, parked, or human-only. A tool that failed, an unavailable
  source, and a moved environment digest are reported as unavailable.
  Exit: 0 satisfied - 1 usage - 2 contract failure - 3 not satisfied
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [string]$Baseline = '',
    [switch]$Json,
    [switch]$Md
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

# The table carries an em dash, so pin stdout to UTF-8 whatever the host console
# code page is.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

exit (Invoke-NSEvidenceCompareCommand -Project $Project -Baseline $Baseline -Json:$Json -Md:$Md)
