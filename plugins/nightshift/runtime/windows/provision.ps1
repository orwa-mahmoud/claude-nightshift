<#
.SYNOPSIS
  Forward Auto-add provisioning verbs on native Windows.

.DESCRIPTION
  Mirrors runtime/provision.sh. Resolves the plugin root and calls runtime/provision.py.
  The Python engine is authoritative; this wrapper does not implement plan, apply,
  recover, or rollback.
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('plan', 'apply', 'recover', 'rollback')]
    [string]$Command,
    [string]$Recipe = '',
    [string]$Capability = '',
    [string]$BudgetSeconds = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$py = Join-Path $pluginRoot 'runtime/provision.py'
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $python) {
    [Console]::Error.WriteLine('provision: python3 is required')
    exit 1
}

$argsList = @($py, '--project', $Project)
if ($Recipe) {
    $argsList += @('--recipe', $Recipe)
}
if ($Capability) {
    $argsList += @('--capability', $Capability)
}
if ($BudgetSeconds) {
    $argsList += @('--budget-seconds', $BudgetSeconds)
}
$argsList += $Command

& $python.Source @argsList
exit $LASTEXITCODE
