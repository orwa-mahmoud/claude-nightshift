<#
.SYNOPSIS
  The compact morning receipt for native Windows.

.DESCRIPTION
  Mirrors runtime/morning-receipt.sh byte for byte on the bundled PowerShell
  alone. Renders Markdown from records only - the ledger, the resolved policy,
  the punch list, the parking lot, the shift log - and omits any section it has
  no record for. It invents nothing and never renders a disabled check as a
  check that passed. Views: owner (default), reviewer, release, artifact.
  Exit: 0 rendered - 1 usage - 2 contract failure
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [ValidateSet('', 'owner', 'reviewer', 'release', 'artifact')]
    [string]$View = '',
    [string]$Out = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

# The receipt carries an em dash, so pin stdout to UTF-8 whatever the host
# console code page is.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

exit (Invoke-NSMorningReceiptCommand -Project $Project -View $View -Out $Out)
