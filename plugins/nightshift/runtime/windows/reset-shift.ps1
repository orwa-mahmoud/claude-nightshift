param(
    [string]$Project = ''
)

# reset-shift.ps1  -  abandon current runtime mechanics. Preserves punch list, rules, and history.
#   reset-shift.ps1 -Project DIR
# -Project is required. Does not use the current working directory.

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    [Console]::Error.WriteLine('reset-shift: -Project is required')
    exit 1
}

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

try {
    $lines = @(Reset-NSShift -Project $Project)
}
catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
$lines | ForEach-Object { Write-Output $_ }
if ($lines -contains 'watchman unverified') { exit 2 }
exit 0
