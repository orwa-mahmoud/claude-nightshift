<#
.SYNOPSIS
  Explainable shift preview on native Windows (read-only).
#>
param([string]$InputPath = '')

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$py = Join-Path (Split-Path $PSScriptRoot -Parent) 'shift-preview.py'
if (-not (Test-Path -LiteralPath $py)) {
    Write-Error 'runtime/shift-preview.py is not installed'
    exit 2
}
if ($InputPath) {
    & python3 $py --input $InputPath
} else {
    & python3 $py
}
exit $LASTEXITCODE
