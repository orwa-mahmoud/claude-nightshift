param(
    [string]$Project = [Environment]::CurrentDirectory
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

try {
    $hostPath = Resolve-NSCanonicalPath $Project
}
catch {
    [Console]::Error.WriteLine("migrate-state: cannot cd to $Project")
    exit 4
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostPath
}
catch {
    [Console]::Error.WriteLine('migrate-state: invalid .nightshift-link - Nightshift will not guess a workspace')
    exit 2
}

$ns = Join-Path $workspace '.nightshift'
if (Test-Path -LiteralPath $ns -PathType Container) {
    $legacy = Invoke-NSMigrateCapabilityPolicy $workspace
    switch ([string]$legacy['state']) {
        'migrated' {
            $line = "capability-policy.json is retired; tooling policy $($legacy['toolingPolicy']) is now the shift-defaults prefill"
            Write-Output "migrate-state: $line"
            Write-NSControlLog $ns $line
        }
        'discarded' {
            $line = 'capability-policy.json is retired; it named no known tooling policy'
            Write-Output "migrate-state: $line"
            Write-NSControlLog $ns $line
        }
        'armed' {
            [Console]::Error.WriteLine('migrate-state: refuse to migrate while the shift is armed')
            exit 1
        }
        'failed' {
            [Console]::Error.WriteLine('migrate-state: failed to write shift-defaults.json')
            exit 3
        }
    }
}

$kind = Get-NSStateKind $workspace
switch ($kind) {
    'current' {
        Write-Output "Nightshift state-version is already $(Get-NSStateVersion $workspace)"
        exit 0
    }
    'legacy' { }
    'future' {
        [Console]::Error.WriteLine((Get-NSStateRefuseMessage 'future'))
        exit 2
    }
    'malformed' {
        [Console]::Error.WriteLine((Get-NSStateRefuseMessage 'malformed'))
        exit 2
    }
    default {
        [Console]::Error.WriteLine("migrate-state: no .nightshift/ at $workspace - run setup first")
        exit 2
    }
}

$code = Invoke-NSMigrateState $workspace
switch ($code) {
    0 {
        Write-Output "Nightshift state-version is now $(Get-NSStateVersion $workspace)"
        exit 0
    }
    1 {
        [Console]::Error.WriteLine('migrate-state: refuse to migrate while the shift is armed')
        exit 1
    }
    3 {
        [Console]::Error.WriteLine('migrate-state: failed to write state-version')
        exit 3
    }
    default {
        [Console]::Error.WriteLine((Get-NSStateRefuseMessage $kind))
        exit 2
    }
}
