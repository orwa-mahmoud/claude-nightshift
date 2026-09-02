<#
.SYNOPSIS
  Explainable shift preview on native Windows (read-only).
#>
param([string]$InputPath = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

Write-Error @'
shift preview is optional on native Windows until a PowerShell planner ships.
Use the POSIX runtime/shift-preview.sh from a bash host, or run Hunt/Quality Review-first on Claude Code or Codex.
'@
exit 2
