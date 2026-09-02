<#
.SYNOPSIS
  Records a checkpoint before a risky cluster for native Windows.

.DESCRIPTION
  Mirrors runtime/evidence-checkpoint.sh. Writes a domain "checkpoint" record
  through the ledger: the worktree digest and HEAD, the baseline the cluster
  relies on, the generated-artifact inventory with content digests, the exact
  touched surface, the rollback ref or provisioning transaction id, and the
  verification plan.
  Exit: 0 written - 1 usage / no .nightshift - 2 contract failure
#>
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$cli = ConvertFrom-NSEvidenceCheckpointCli $args
if ($null -eq $cli) { exit (Write-NSEvidenceCheckpointUsage) }

exit (Invoke-NSEvidenceCheckpointCommand -Project $cli.Project -Id $cli.Id `
        -Baseline $cli.Baseline -Artifacts $cli.Artifacts -Touched $cli.Touched `
        -Rollback $cli.Rollback -Plan $cli.Plan -Scope $cli.Scope `
        -SourceClass $cli.SourceClass -HostLabel $cli.HostLabel)
