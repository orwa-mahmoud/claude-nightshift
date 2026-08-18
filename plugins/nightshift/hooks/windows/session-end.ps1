Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($env:NIGHTSHIFT_REVIVAL -eq '1') {
    exit 0
}

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

$raw = [Console]::In.ReadToEnd()
try {
    $payload = $raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    exit 0
}

$hostRoot = if (-not [string]::IsNullOrEmpty($env:CLAUDE_PROJECT_DIR)) {
    $env:CLAUDE_PROJECT_DIR
}
elseif ($null -ne $payload.PSObject.Properties['cwd'] -and -not [string]::IsNullOrEmpty([string]$payload.cwd)) {
    [string]$payload.cwd
}
else {
    [Environment]::CurrentDirectory
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostRoot
}
catch {
    exit 0
}
if ((Get-NSStateKind $workspace) -in @('malformed', 'future')) {
    exit 0
}

$ns = Join-Path $workspace '.nightshift'
$punch = Join-Path $ns 'punch-list.md'
$counts = Get-NSBoxCounts $punch
if (-not (Test-Path -LiteralPath (Join-Path $ns '.shift-armed') -PathType Leaf) `
    -or -not (Test-Path -LiteralPath $punch -PathType Leaf) `
    -or (Test-Path -LiteralPath (Join-Path $ns '.ended') -PathType Leaf) `
    -or $counts.Open -eq 0) {
    exit 0
}

$sessionId = if ($null -eq $payload.PSObject.Properties['session_id']) { '' } else { [string]$payload.session_id }
$session = Read-NSSession $ns
if ($null -ne $session -and -not [string]::IsNullOrEmpty($session.SessionId) -and $session.SessionId -ne $sessionId) {
    exit 0
}

$leasePath = Join-Path $ns '.shift-lease'
if (Test-NSPathEntry $leasePath) {
    $hostProcess = Get-NSHostProcess 'claude'
    $processId = if ($null -eq $hostProcess) { '' } else { [string]$hostProcess.Id }
    $processStart = if ($null -eq $hostProcess) { '' } else { [string]$hostProcess.Start }
    $allow = Test-NSLeaseAllows $ns $sessionId 'claude' $processId $processStart `
        ([string]$env:NIGHTSHIFT_LEASE_TOKEN) ([string]$env:NIGHTSHIFT_LEASE_GENERATION)
    if ($allow -ne 'Allow') {
        exit 0
    }
}

$reason = if ($null -eq $payload.PSObject.Properties['reason']) { 'unknown' } else { [string]$payload.reason }
$reason = ($reason -replace '[\x00-\x1f]', '').Trim()
$line = '{0} - clean session end ({1}){2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $reason, [Environment]::NewLine
[IO.File]::WriteAllText((Join-Path $ns '.session-end'), $line, (New-Object Text.UTF8Encoding($false)))
exit 0
