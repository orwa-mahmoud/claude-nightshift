<#
.SYNOPSIS
  Read-only permission and revival check on native Windows.

.DESCRIPTION
  Mirrors runtime/provision-preflight.sh. Prints JSON {ok, skipReasons,
  recoverNeeded}. Never writes the punch list. Never installs. A
  permission-prompt risk is a skip, not a freeze.
#>
param(
    [string]$Project = [Environment]::CurrentDirectory,
    [Parameter(Position = 0)]
    [ValidateSet('check')]
    [string]$Command = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

if ($Command -ne 'check') {
    [Console]::Error.WriteLine('provision-preflight: usage: provision-preflight.ps1 -Project DIR check')
    exit 1
}

try {
    $hostPath = Resolve-NSCanonicalPath $Project
}
catch {
    [Console]::Error.WriteLine("provision-preflight: cannot cd to $Project")
    exit 1
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostPath
}
catch {
    [Console]::Error.WriteLine('provision-preflight: invalid .nightshift-link')
    exit 1
}

$ns = Join-Path $workspace '.nightshift'
$tx = Join-Path $ns 'provision-transaction.json'
$recoverNeeded = $false
if ((Test-Path -LiteralPath $tx -PathType Leaf) -and -not (Test-NSReparsePoint $tx)) {
    $recoverNeeded = $true
}

$grant = $false
$permissionFiles = @(
    (Join-Path $hostPath '.claude/settings.local.json'),
    (Join-Path $hostPath '.claude/settings.json'),
    (Join-Path $workspace '.claude/settings.local.json'),
    (Join-Path $workspace '.claude/settings.json')
) | Select-Object -Unique
foreach ($permissionFile in $permissionFiles) {
    if (-not (Test-Path -LiteralPath $permissionFile -PathType Leaf)) {
        continue
    }
    $settingsText = [IO.File]::ReadAllText($permissionFile)
    if ($settingsText -match 'bypassPermissions|"allow"') {
        $grant = $true
        break
    }
}

$codexGrant = [string]$env:CODEX_SANDBOX + [string]$env:CODEX_SANDBOX_MODE + [string]$env:NIGHTSHIFT_WATCH_AGENT
if ($codexGrant -match 'danger-full-access|bypassPermissions|-a never') {
    $grant = $true
}

$attended = $false
if ([string]$env:NIGHTSHIFT_REVIVAL -ne '1') {
    try {
        if (-not [Console]::IsInputRedirected) {
            $attended = $true
        }
    }
    catch {
    }
}

$skipReasons = New-Object System.Collections.Generic.List[string]
if ((-not $grant) -and (-not $attended)) {
    [void]$skipReasons.Add('permission-prompt-required')
}

$ok = ($skipReasons.Count -eq 0)
if ($skipReasons.Count -eq 0) {
    $reasonsJson = '[]'
}
else {
    $quoted = @($skipReasons | ForEach-Object { '"{0}"' -f $_ })
    $reasonsJson = '[' + ($quoted -join ',') + ']'
}
$okJson = if ($ok) { 'true' } else { 'false' }
$recoverJson = if ($recoverNeeded) { 'true' } else { 'false' }
Write-Output ('{{"ok":{0},"skipReasons":{1},"recoverNeeded":{2}}}' -f $okJson, $reasonsJson, $recoverJson)
exit 0
