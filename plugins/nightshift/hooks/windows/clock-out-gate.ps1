param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('claude', 'codex')]
    [string]$HostName
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}
$utf8 = New-Object Text.UTF8Encoding($false)

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

function Write-Block {
    param([Parameter(Mandatory = $true)][string]$Reason)
    [Console]::Out.WriteLine((@{ decision = 'block'; reason = $Reason } | ConvertTo-Json -Compress))
    exit 0
}

function Write-Release {
    if ($HostName -eq 'codex') {
        [Console]::Out.WriteLine('{"continue":true}')
    }
    exit 0
}

function Get-PropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = ''
    )
    if ($null -eq $Object) {
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }
    return $property.Value
}

function Write-NSLogLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    if (Test-Path -LiteralPath $ns -PathType Container) {
        $line = '{0} - {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message, [Environment]::NewLine
        [IO.File]::AppendAllText($log, $line, $utf8)
    }
}

function Release-NSLeaseWithRetry {
    if (Release-NSLease $ns) {
        return
    }
    Start-Sleep -Milliseconds 200
    if (-not (Release-NSLease $ns)) {
        Write-NSLogLine 'process lease release deferred: lease mutex remained busy'
    }
}

function Save-NSReceipt {
    param([Parameter(Mandatory = $true)][string]$Summary)
    if (-not (Test-Path -LiteralPath (Join-Path $ns '.git') -PathType Container)) {
        return
    }
    try {
        $null = Invoke-NSGitCommand $ns @('add', '-A')
        $committed = Invoke-NSGitCommand $ns @(
            '-c', 'user.name=nightshift',
            '-c', 'user.email=nightshift@localhost',
            '-c', 'commit.gpgsign=false',
            'commit', '-q', '-m', $Summary
        )
        if ($committed.ExitCode -ne 0 -and $committed.Text -notmatch 'nothing to commit|nothing added') {
            Write-NSLogLine ('receipts commit failed: ' + (($committed.Text -split "`r?`n")[0]))
        }
    }
    catch {
        Write-NSLogLine ('receipts commit failed: ' + $_.Exception.Message)
    }
}

function Invoke-NSWhistle {
    param([Parameter(Mandatory = $true)][string]$Summary)
    if ([string]::IsNullOrEmpty($notify)) {
        return
    }
    $stream = $null
    try {
        $stream = [IO.File]::Open($notified, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $stream.Dispose()
        $stream = $null
    }
    catch {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
        return
    }
    $oldSummary = $env:NIGHTSHIFT_SUMMARY
    try {
        $env:NIGHTSHIFT_SUMMARY = $Summary
        $null = Invoke-Expression $notify 2>$null
    }
    catch {
    }
    finally {
        $env:NIGHTSHIFT_SUMMARY = $oldSummary
    }
}

function Complete-NSShift {
    param([Parameter(Mandatory = $true)][string]$Summary)
    if (Test-Path -LiteralPath $ns -PathType Container) {
        [IO.File]::WriteAllText($ended, '', $utf8)
    }
    Remove-Item -LiteralPath $armed -Force -ErrorAction SilentlyContinue
    Release-NSLeaseWithRetry
    Save-NSReceipt $Summary
    Invoke-NSWhistle $Summary
}

function Test-NSDeadlinePassed {
    if (-not (Test-Path -LiteralPath $deadline -PathType Leaf)) {
        return $false
    }
    try {
        $rawDeadline = ([IO.File]::ReadAllText($deadline)).Trim()
        if ($rawDeadline -match '^[0-9]+$') {
            return (Get-NSUnixTime) -ge [long]$rawDeadline
        }
        $parsed = [DateTimeOffset]::Parse(
            $rawDeadline,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AssumeLocal
        )
        return [DateTimeOffset]::Now -ge $parsed
    }
    catch {
        return $false
    }
}

function Get-NSProjectHead {
    try {
        $target = Resolve-NSWorkTarget $workspace
        $head = Invoke-NSGit $target @('rev-parse', 'HEAD')
        if (-not [string]::IsNullOrWhiteSpace($head)) {
            return $head
        }
    }
    catch {
    }
    return 'nohead'
}

$raw = Get-NSStdinText -Piped (($input | ForEach-Object { $_ }) -join "`n")
$payload = $null
if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
        $payload = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $payload = $null
    }
}
$sessionId = [string](Get-PropertyValue $payload 'session_id')
$transcript = [string](Get-PropertyValue $payload 'transcript_path')
$payloadCwd = [string](Get-PropertyValue $payload 'cwd' ([Environment]::CurrentDirectory))

if ($HostName -eq 'claude') {
    $hostRoot = if (-not [string]::IsNullOrEmpty($env:CLAUDE_PROJECT_DIR)) { $env:CLAUDE_PROJECT_DIR } else { $payloadCwd }
}
else {
    $hostRoot = if (-not [string]::IsNullOrEmpty($env:CODEX_PROJECT_DIR)) { $env:CODEX_PROJECT_DIR } else { $payloadCwd }
}
if ([string]::IsNullOrEmpty($hostRoot)) {
    $hostRoot = [Environment]::CurrentDirectory
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostRoot
}
catch {
    Write-Block 'DO NOT STOP - .nightshift-link is invalid. Open the correct project task or repair the explicit link to an absolute workspace containing .nightshift/.'
}

$stateKind = Get-NSStateKind $workspace
if ($stateKind -in @('malformed', 'future')) {
    Write-Block ('DO NOT STOP - ' + (Get-NSStateRefuseMessage $stateKind))
}

$ns = Join-Path $workspace '.nightshift'
$punch = Join-Path $ns 'punch-list.md'
$stop = Join-Path $ns 'STOP'
$deadline = Join-Path $ns 'deadline'
$stall = Join-Path $ns '.stall'
$notified = Join-Path $ns '.notified'
$ended = Join-Path $ns '.ended'
$armed = Join-Path $ns '.shift-armed'
$log = Join-Path $ns 'shift-log.md'

if (-not (Test-Path -LiteralPath $armed -PathType Leaf)) {
    Write-Release
}

$counts = Get-NSBoxCounts $punch
$stallMaxRaw = Get-NSRule $workspace 'stallMax' ([string]$env:NIGHTSHIFT_STALL_MAX)
$stallWarnRaw = Get-NSRule $workspace 'stallWarnEvery' ([string]$env:NIGHTSHIFT_STALL_WARN)
$stallReady = $stallMaxRaw -match '^[0-9]+$' -and $stallWarnRaw -match '^[1-9][0-9]*$'
$stallMax = if ($stallReady) { [int]$stallMaxRaw } else { 0 }
$stallWarn = if ($stallReady) { [int]$stallWarnRaw } else { 0 }
$notify = Get-NSRule $workspace 'notifyCommand' ([string]$env:NIGHTSHIFT_NOTIFY_CMD)
$gateMessage = Get-NSRule $workspace 'clockOutMessage' ([string]$env:NIGHTSHIFT_GATE_MESSAGE)

# STOP is an owner capability. Process ownership must never make emergency stop unusable.
if (Test-Path -LiteralPath $stop -PathType Leaf) {
    $mutex = Enter-NSMutex $ns '.lock.d'
    try {
        $reason = ''
        try {
            $reason = (([IO.File]::ReadLines($stop) | Select-Object -First 1) -as [string]).Trim()
        }
        catch {
        }
        if (Test-Path -LiteralPath $punch -PathType Leaf) {
            $suffix = if ([string]::IsNullOrEmpty($reason)) { '' } else { " ($reason)" }
            Complete-NSShift ("shift ended${suffix}: $($counts.Ticked)/$($counts.Total) done")
        }
        else {
            Remove-Item -LiteralPath $armed -Force -ErrorAction SilentlyContinue
            Release-NSLeaseWithRetry
        }
    }
    finally {
        if ($null -ne $mutex) {
            Exit-NSMutex $mutex
        }
    }
    Write-Release
}

if ($null -eq $payload) {
    Write-Block 'DO NOT STOP - the hook payload is unreadable while a shift is active. Retry after the host can provide valid hook JSON.'
}

$token = [string]$env:NIGHTSHIFT_LEASE_TOKEN
$generation = [string]$env:NIGHTSHIFT_LEASE_GENERATION
$revival = $env:NIGHTSHIFT_REVIVAL -eq '1'

$unbound = Resolve-NSShiftUnbound -NightshiftDir $ns -HostName $HostName `
    -Token $token -Generation $generation -Revival $revival -Mode gate
if ($unbound.Status -eq 'Pass') { Write-Release }
if ($unbound.Status -eq 'Fail') { Write-Block $unbound.Message }

$hostProcess = Get-NSHostProcess $HostName
$processId = if ($null -eq $hostProcess) { '' } else { [string]$hostProcess.Id }
$processStart = if ($null -eq $hostProcess) { '' } else { [string]$hostProcess.Start }

$session = Read-NSSession $ns
if ($null -eq $session -and -not [string]::IsNullOrEmpty($sessionId)) {
    $null = Claim-NSSession $ns $sessionId $transcript $processId $processStart $HostName
}

$owned = Resolve-NSShiftOwnership -NightshiftDir $ns -HostName $HostName `
    -SessionId $sessionId -Transcript $transcript -ProcessId $processId `
    -ProcessStart $processStart -Token $token -Generation $generation `
    -Revival $revival -Mode gate
if ($owned.Status -eq 'Pass') { Write-Release }
if ($owned.Status -eq 'Fail') { Write-Block $owned.Message }
$session = $owned.Session

$mutex = Enter-NSMutex $ns '.lock.d'
# An unlockable site is decided unlocked: the gate must answer, never queue.
try {
    if (Test-Path -LiteralPath $stop -PathType Leaf) {
        $reason = ''
        try {
            $reason = (([IO.File]::ReadLines($stop) | Select-Object -First 1) -as [string]).Trim()
        }
        catch {
        }
        $suffix = if ([string]::IsNullOrEmpty($reason)) { '' } else { " ($reason)" }
        Complete-NSShift ("shift ended${suffix}: $($counts.Ticked)/$($counts.Total) done")
        Write-Release
    }

    if (-not (Test-Path -LiteralPath $punch -PathType Leaf)) {
        Remove-Item -LiteralPath $armed -Force -ErrorAction SilentlyContinue
        Release-NSLeaseWithRetry
        Write-Release
    }
    if ($counts.Open -eq 0) {
        Complete-NSShift "shift done: $($counts.Ticked)/$($counts.Total)"
        Write-Release
    }
    if (Test-NSDeadlinePassed) {
        Write-NSLogLine "quitting time - shift ended, $($counts.Ticked)/$($counts.Total) done, items left open"
        [IO.File]::WriteAllText($stop, "deadline$([Environment]::NewLine)", $utf8)
        Complete-NSShift "quitting time: $($counts.Ticked)/$($counts.Total) done, items left open"
        Write-Release
    }

    if ($stallReady) {
        $fingerprint = "$($counts.Ticked):$(Get-NSProjectHead)"
        $previousFingerprint = ''
        $previousAttempts = 0
        if (Test-Path -LiteralPath $stall -PathType Leaf) {
            try {
                $lines = [IO.File]::ReadAllLines($stall)
                if ($lines.Count -gt 0) {
                    $previousFingerprint = $lines[0]
                }
                if ($lines.Count -gt 1 -and $lines[1] -match '^[0-9]+$') {
                    $previousAttempts = [int]$lines[1]
                }
            }
            catch {
            }
        }
        $attempts = if ($previousFingerprint -eq $fingerprint) { $previousAttempts + 1 } else { 1 }
        if ($stallMax -gt 0 -and $attempts -ge $stallMax) {
            Write-NSLogLine "stalled - auto-ended, $attempts attempts no progress, $($counts.Ticked)/$($counts.Total) done, items left open"
            [IO.File]::WriteAllText($stop, "stalled$([Environment]::NewLine)", $utf8)
            Complete-NSShift "stalled: $($counts.Ticked)/$($counts.Total) done, $attempts attempts no progress"
            Write-Release
        }
        if ($stallMax -eq 0 -and $attempts -ge $stallWarn) {
            Write-NSLogLine "stall warning - $attempts attempts no progress, $($counts.Ticked)/$($counts.Total) done; keeping shift open"
            $attempts = 0
        }
        $null = Write-NSAtomicLines -Path $stall -Lines @($fingerprint, [string]$attempts)
    }
    else {
        Write-NSLogLine 'stall guard down - stallMax/stallWarnEvery unreadable; run Setup again'
    }
}
finally {
    if ($null -ne $mutex) {
        Exit-NSMutex $mutex
    }
}

if (-not [string]::IsNullOrEmpty($gateMessage)) {
    Write-Block $gateMessage
}
Write-Block 'DO NOT STOP - the punch list (.nightshift/punch-list.md) still has open items. Work them one at a time per its contract, run each item''s gate, and tick only after completion; park owner decisions in .nightshift/parking-lot.md and keep working. (nightshift: clockOutMessage is unreadable; run Setup again.)'
