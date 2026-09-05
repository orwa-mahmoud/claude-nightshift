<#
.SYNOPSIS
  Versioned findings ledger for native Windows (JSON Lines).

.DESCRIPTION
  Mirrors runtime/evidence.sh byte for byte on the bundled PowerShell alone.
  Validates records. Does not verify a Nightshift tick or interpret domain meaning.
  Exit: 0 ok - 1 usage / no .nightshift - 2 contract failure
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [Parameter(Position = 0)]
    [ValidateSet('', 'init', 'validate', 'append', 'disposition', 'render', 'export-tsv', 'migrate')]
    [string]$Command = '',
    [string]$Record = '',
    [string]$Raw = '',
    [string]$Id = '',
    [string]$Disposition = '',
    [string]$Ladder = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

# The render table carries an em dash, so pin stdout to UTF-8 whatever the host
# console code page is.
[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

exit (Invoke-NSEvidenceCommand -Project $Project -Command $Command -Record $Record -Raw $Raw -Id $Id -Disposition $Disposition -Ladder $Ladder)
