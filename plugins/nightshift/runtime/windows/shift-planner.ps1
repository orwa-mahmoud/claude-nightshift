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

$py = Join-Path (Split-Path $PSScriptRoot -Parent) 'shift-planner.py'
if (-not (Test-Path -LiteralPath $py)) {
    Write-Error 'runtime/shift-planner.py is not installed'
    exit 2
}
$args = @('--input', $InputPath, '--hours', "$Hours", '--selection', $Selection, '--launch', $Launch)
if ($Learning) { $args += @('--learning', $Learning) }
if ($SelectionIds) { $args += @('--selection-ids', $SelectionIds) }
& python3 $py @args
exit $LASTEXITCODE
