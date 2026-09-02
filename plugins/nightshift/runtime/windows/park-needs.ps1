<#
.SYNOPSIS
  Park the items the shift policy will not let the agent finish.

.DESCRIPTION
  Mirrors runtime/park-needs.sh. Appends one parking-lot.md entry per item and
  missing elevation category so Start parks mechanically instead of asking.
  Idempotent: an entry already on file is left alone.
  Exit: 0 ok - 1 usage / no .nightshift
#>
param(
    [string]$Project = [Environment]::CurrentDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

# The parked entry carries an em dash, so pin stdout to UTF-8 whatever the host
# console code page is.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

exit (Invoke-NSParkNeedsCommand -Project $Project)
