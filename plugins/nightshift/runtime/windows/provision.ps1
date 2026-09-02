<#
.SYNOPSIS
  Auto-add provisioning verbs on native Windows.

.DESCRIPTION
  Mirrors runtime/provision.sh. `plan` reads the recipe, the resolved shift
  policy and the work target, prints the plan and touches nothing. `recover`
  and `rollback` are native: they finish or undo an interrupted transaction
  from .nightshift/provision-transaction.json and prove the restore against
  the recorded digests before clearing anything. `recover -Rollback` forces the
  undo whatever the stage; `recover -Diagnose` only reports, one tab-separated
  line. `apply` reports that no provisioning runtime is available on this host
  and changes nothing.
  Exit: 0 ok - 1 usage/runtime failure - 2 refused or malformed - 3 unproven
  or unavailable
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('plan', 'apply', 'recover', 'rollback')]
    [string]$Command,
    [string]$Recipe = '',
    [string]$Capability = '',
    [string]$BudgetSeconds = '',
    [switch]$Rollback,
    [switch]$Diagnose
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

exit (Invoke-NSProvisionCommand -Project $Project -Command $Command -Recipe $Recipe `
        -Capability $Capability -BudgetSeconds $BudgetSeconds -Rollback:$Rollback -Diagnose:$Diagnose)
