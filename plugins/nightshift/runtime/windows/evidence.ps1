<#
.SYNOPSIS
  Versioned findings ledger for native Windows (JSON Lines).

.DESCRIPTION
  Mirrors runtime/evidence.sh. Validates records. Does not verify a Nightshift tick
  or interpret domain meaning.
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [Parameter(Position = 0)]
    [ValidateSet('init', 'validate', 'append', 'disposition', 'render', 'export-tsv', 'migrate')]
    [string]$Command = 'validate',
    [string]$Record = '',
    [string]$Raw = '',
    [string]$Id = '',
    [string]$Disposition = '',
    [string]$Ladder = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$py = Join-Path $pluginRoot 'runtime/evidence.py'
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $python) {
    [Console]::Error.WriteLine('evidence: python3 is required for the ledger helper')
    exit 1
}

$argsList = @($py, '--project', $Project, $Command)
switch ($Command) {
    'append' {
        if (-not $Record) { [Console]::Error.WriteLine('evidence: -Record is required'); exit 1 }
        $argsList += @('--record', $Record)
        if ($Raw) { $argsList += @('--raw', $Raw) }
    }
    'disposition' {
        if (-not $Id -or -not $Disposition) {
            [Console]::Error.WriteLine('evidence: -Id and -Disposition are required')
            exit 1
        }
        $argsList += @($Id, $Disposition)
        if ($Ladder) { $argsList += $Ladder }
    }
}

& $python.Source @argsList
exit $LASTEXITCODE
