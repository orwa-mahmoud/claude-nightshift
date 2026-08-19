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
    [Console]::Error.WriteLine("export-support: cannot cd to $Project")
    exit 1
}

$linkState = 'absent'
try {
    $workspace = Resolve-NSWorkspaceRoot $hostPath
    $link = Join-Path $hostPath '.nightshift-link'
    if (Test-NSPathEntry $link) {
        $linkState = 'valid'
    }
}
catch {
    [Console]::Error.WriteLine('export-support: invalid .nightshift-link - Nightshift will not guess a workspace')
    exit 2
}

$ns = Join-Path $workspace '.nightshift'
if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
    [Console]::Error.WriteLine("export-support: no .nightshift/ at $workspace")
    exit 2
}

$homeRoot = ''
if (-not [string]::IsNullOrEmpty($env:USERPROFILE)) {
    try { $homeRoot = Resolve-NSCanonicalPath $env:USERPROFILE } catch { $homeRoot = '' }
}
elseif (-not [string]::IsNullOrEmpty($env:HOME)) {
    try { $homeRoot = Resolve-NSCanonicalPath $env:HOME } catch { $homeRoot = '' }
}

$target = ''
try {
    $resolved = Resolve-NSWorkTarget $workspace
    if (-not [string]::IsNullOrEmpty($resolved)) {
        $target = Resolve-NSCanonicalPath $resolved
    }
}
catch {
    $target = ''
}

$pluginJson = Join-Path $pluginRoot '.claude-plugin/plugin.json'
$pluginVer = 'unknown'
$pluginName = 'nightshift'
if (Test-Path -LiteralPath $pluginJson -PathType Leaf) {
    try {
        $manifest = Get-Content -LiteralPath $pluginJson -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $manifest.PSObject.Properties['version'] -and -not [string]::IsNullOrEmpty([string]$manifest.version)) {
            $pluginVer = [string]$manifest.version
        }
        if ($null -ne $manifest.PSObject.Properties['name'] -and -not [string]::IsNullOrEmpty([string]$manifest.name)) {
            $pluginName = [string]$manifest.name
        }
    }
    catch {
    }
}

$stateKind = Get-NSStateKind $workspace
$stateVer = Get-NSStateVersion $workspace
if ($stateKind -notin @('current', 'legacy')) {
    $stateVer = ''
}

$rulesPath = Join-Path $ns 'rules.json'
$rulesState = 'missing'
$rulesKeys = ''
if (-not (Test-Path -LiteralPath $rulesPath -PathType Leaf)) {
    $rulesState = 'missing'
}
else {
    $rules = Get-NSRulesObject $workspace
    if ($null -eq $rules) {
        $rulesState = 'unreadable'
    }
    else {
        $rulesState = 'valid'
        $rulesKeys = (($rules.PSObject.Properties | ForEach-Object { $_.Name }) -join ' ')
    }
}

$reason = Get-NSReasonCode $ns
$reasonLabel = ''
if (-not [string]::IsNullOrEmpty($reason)) {
    $reasonLabel = Get-NSReasonLabel $reason
}

$leaseState = 'absent'
$leaseHost = ''
$leaseGeneration = ''
$leaseMode = ''
$leasePath = Join-Path $ns '.shift-lease'
if (Test-NSPathEntry $leasePath) {
    $lease = Read-NSLease $ns
    if ($null -ne $lease) {
        $leaseState = 'valid'
        $leaseHost = [string]$lease.HostName
        $leaseGeneration = [string]$lease.Generation
        $leaseMode = if (-not [string]::IsNullOrEmpty([string]$lease.Nonce)) { 'recovered' } else { 'interactive' }
    }
    else {
        $leaseState = 'malformed'
    }
}

$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$outdir = Join-Path $ns 'support'
try {
    $null = New-Item -ItemType Directory -Path $outdir -Force
}
catch {
    [Console]::Error.WriteLine("export-support: cannot create $outdir")
    exit 2
}
$tmp = Join-Path $outdir ".$stamp.$PID"
$dest = Join-Path $outdir "$stamp.txt"

function Format-NSIdentity {
    param([string]$Value, [string]$Label)
    if ([string]::IsNullOrEmpty($Value)) {
        return "${Label}: omitted"
    }
    $token = Convert-NSTokenizedText $Value $homeRoot $workspace $target
    if ($null -eq $token) {
        return "${Label}: omitted"
    }
    return "${Label}: $token"
}

$lines = New-Object Collections.Generic.List[string]
$null = $lines.Add('Nightshift support bundle')
$null = $lines.Add("Generated: $stamp")
$null = $lines.Add('')
$null = $lines.Add('== plugin ==')
$null = $lines.Add("name: $pluginName")
$null = $lines.Add("version: $pluginVer")
$null = $lines.Add('')
$null = $lines.Add('== host ==')
$null = $lines.Add("uname: $([Environment]::OSVersion.Platform)")
$null = $lines.Add("link: $linkState")
$null = $lines.Add('')
$null = $lines.Add('== state ==')
$null = $lines.Add("kind: $stateKind")
if (-not [string]::IsNullOrEmpty($stateVer)) {
    $null = $lines.Add("version: $stateVer")
}
$null = $lines.Add('')
$null = $lines.Add('== identities ==')
$null = $lines.Add((Format-NSIdentity $hostPath 'task'))
$null = $lines.Add((Format-NSIdentity $workspace 'workspace'))
if ([string]::IsNullOrEmpty($target)) {
    $null = $lines.Add('work_target: unresolved')
}
else {
    $null = $lines.Add((Format-NSIdentity $target 'work_target'))
}
$null = $lines.Add('')
$null = $lines.Add('== markers ==')
$null = $lines.Add(('armed: {0}' -f $(if (Test-Path -LiteralPath (Join-Path $ns '.shift-armed') -PathType Leaf) { 'yes' } else { 'no' })))
$null = $lines.Add(('ended: {0}' -f $(if (Test-Path -LiteralPath (Join-Path $ns '.ended') -PathType Leaf) { 'yes' } else { 'no' })))
$null = $lines.Add(('stop: {0}' -f $(if (Test-Path -LiteralPath (Join-Path $ns 'STOP') -PathType Leaf) { 'yes' } else { 'no' })))
$null = $lines.Add(('session_end: {0}' -f $(if (Test-Path -LiteralPath (Join-Path $ns '.session-end') -PathType Leaf) { 'yes' } else { 'no' })))
$null = $lines.Add(('session_record: {0}' -f $(if (Test-Path -LiteralPath (Join-Path $ns '.shift-session') -PathType Leaf) { 'present' } else { 'absent' })))
$null = $lines.Add("process_lease: $leaseState")
if (-not [string]::IsNullOrEmpty($leaseHost)) { $lines.Add("lease_host: $leaseHost") }
if (-not [string]::IsNullOrEmpty($leaseGeneration)) { $lines.Add("lease_generation: $leaseGeneration") }
if (-not [string]::IsNullOrEmpty($leaseMode)) { $lines.Add("lease_mode: $leaseMode") }
$null = $lines.Add(('watchman_pidfile: {0}' -f $(if (Test-Path -LiteralPath (Join-Path $ns '.watchman') -PathType Leaf) { 'present' } else { 'absent' })))
$null = $lines.Add('')
$null = $lines.Add('== rules ==')
$null = $lines.Add("validity: $rulesState")
$null = $lines.Add("keys: $rulesKeys")
$null = $lines.Add('')
$null = $lines.Add('== watchman reason ==')
if (-not [string]::IsNullOrEmpty($reason)) {
    $null = $lines.Add("code: $reason")
    $null = $lines.Add("label: $reasonLabel")
}
else {
    $null = $lines.Add('code: none')
}
$null = $lines.Add('')
$null = $lines.Add('== runtime log tail ==')
$logPath = Join-Path $ns 'scheduled.log'
if ((Test-Path -LiteralPath $logPath -PathType Leaf) -and -not (Test-NSReparsePoint $logPath)) {
    $tailOk = 0
    $tailSkip = 0
    $allLines = [IO.File]::ReadAllLines($logPath)
    $start = [Math]::Max(0, $allLines.Count - 40)
    for ($i = $start; $i -lt $allLines.Count; $i++) {
        $line = [string]$allLines[$i]
        if ($hostPath -ne $workspace) {
            $line = $line.Replace($hostPath, $workspace)
        }
        $sanitized = Convert-NSSanitizedLine $line $homeRoot $workspace $target
        if ($null -eq $sanitized) {
            $tailSkip++
        }
        else {
            $null = $lines.Add($sanitized)
            $tailOk++
        }
    }
    if ($tailOk -eq 0 -and $tailSkip -gt 0) {
        $null = $lines.Add('omitted: every line failed sanitization')
    }
}
else {
    $null = $lines.Add('absent')
}

try {
    $null = Write-NSAtomicLines -Path $tmp -Lines @($lines) -Private
    Move-Item -LiteralPath $tmp -Destination $dest -Force
}
catch {
    if (Test-Path -LiteralPath $tmp -PathType Leaf) {
        Remove-NSFile $tmp
    }
    [Console]::Error.WriteLine('export-support: failed to write bundle')
    exit 2
}

Write-Output "Support bundle: $dest"
Write-Output 'Included: plugin metadata, host, state version, tokenized identities, marker and lease state, rules validity and key names, reason codes, sanitized runtime-log tail'
Write-Output 'Omitted: environment, secrets, rule values, repository contents, diffs, transcripts, prompts, owner files, credentials, network, session identities, lease capabilities'
Write-Output 'Inspect the file before sharing. Never uploaded, attached, or opened automatically.'
exit 0
