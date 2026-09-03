<#
.SYNOPSIS
  Unused planner stub. Hunt and Quality plan in the skill. Do not call this.
#>
param(
    [Parameter(Mandatory = $false)][string]$InputPath = '',
    [Parameter(Mandatory = $false)][double]$Hours = 0,
    [ValidateSet('automatic', 'guided')][string]$Selection = 'automatic',
    [ValidateSet('review-first', 'run-direct')][string]$Launch = 'review-first',
    [string]$Learning = '',
    [string]$SelectionIds = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Write-Error @'
shift-planner.ps1 is unused. Hunt and Quality plan in the skill. Do not call a planner.
'@
exit 2
