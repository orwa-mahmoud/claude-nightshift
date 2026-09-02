<#
.SYNOPSIS
  Cache capability detection for the shift on native Windows.
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [ValidateSet('claude', 'codex', 'cursor')]
    [string]$HostLabel = 'claude'
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking
$workspace = Resolve-NSWorkspaceRoot $Project
exit (Invoke-NSRefreshInventory -Workspace $workspace -HostLabel $HostLabel)
