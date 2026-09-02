<#
.SYNOPSIS
  Archive tonight's findings ledger beside the shift policy archive.
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [string]$ShiftId = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking
$workspace = Resolve-NSWorkspaceRoot $Project
exit (Invoke-NSEvidenceArchive -Workspace $workspace -ShiftId $ShiftId)
