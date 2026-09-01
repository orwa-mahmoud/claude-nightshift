<#
.SYNOPSIS
  Persist the owner's tooling policy and inventory cache on native Windows.

.DESCRIPTION
  Mirrors runtime/capability-policy.sh. Writes only .nightshift/capability-policy.json
  and .nightshift/capabilities.json. Never writes the punch list. Inventory is a cache,
  not proof of a tick. Does not install tools.
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [Parameter(Position = 0)]
    [ValidateSet('get', 'set', 'migrate', 'inventory')]
    [string]$Command = 'get',
    [Parameter(Position = 1)]
    [string]$Subcommand = '',
    [string]$Policy = '',
    [string]$WorkMode = 'repository',
    [string]$Remember = 'true',
    [string]$Record = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
$py = Join-Path $pluginRoot 'runtime/capability-policy.py'
$python = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $python) {
    $python = Get-Command python -ErrorAction SilentlyContinue
}
if (-not $python) {
    [Console]::Error.WriteLine('capability-policy: python3 is required')
    exit 1
}

$argsList = @($py, '--project', $Project, '--work-mode', $WorkMode)
switch ($Command) {
    'get' {
        $argsList += 'get'
    }
    'set' {
        if (-not $Policy) {
            [Console]::Error.WriteLine('capability-policy: -Policy is required')
            exit 1
        }
        $argsList += @('--policy', $Policy, '--remember', $Remember, 'set')
    }
    'migrate' {
        $argsList += 'migrate'
    }
    'inventory' {
        $action = $Subcommand
        if (-not $action) {
            if ($Record) { $action = 'set' } else { $action = 'get' }
        }
        if ($action -eq 'set') {
            if (-not $Record) {
                [Console]::Error.WriteLine('capability-policy: -Record is required')
                exit 1
            }
            $argsList += @('inventory', 'set', '--record', $Record)
        } else {
            $argsList += @('inventory', 'get')
        }
    }
}

& $python.Source @argsList
exit $LASTEXITCODE
