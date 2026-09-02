<#
.SYNOPSIS
  Deterministic shift planner on native Windows (read-only).
#>
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][double]$Hours,
    [ValidateSet('automatic', 'guided')][string]$Selection = 'automatic',
    [ValidateSet('review-first', 'run-direct')][string]$Launch = 'review-first',
    [string]$Learning = '',
    [string]$SelectionIds = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Write-Error @'
shift planner is optional on native Windows until a PowerShell port ships.
Use the POSIX runtime/shift-planner.sh from a bash host, or run Hunt/Quality on Claude Code or Codex.
'@
exit 2
