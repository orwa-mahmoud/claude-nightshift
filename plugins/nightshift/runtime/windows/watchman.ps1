param(
    [string]$Project = [Environment]::CurrentDirectory,
    [Parameter(Mandatory = $true)]
    [ValidateSet('claude', 'codex')]
    [string]$HostName,
    [int]$IntervalMinutes = -1,
    [string]$Agent = '',
    [int]$MaxWakes = 0
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
$utf8 = New-Object Text.UTF8Encoding($false)

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force

function Write-NSLogLine {
    param([Parameter(Mandatory = $true)][string]$Message)
    if (Test-Path -LiteralPath $ns -PathType Container) {
        $line = '{0} - {1}{2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message, [Environment]::NewLine
        [IO.File]::AppendAllText($log, $line, $utf8)
    }
}

function Get-NSSessionValue {
    param([Parameter(Mandatory = $true)][string]$Name)
    $session = Read-NSSession $ns
    if ($null -eq $session) {
        return ''
    }
    return [string]$session.$Name
}

function Test-NSDeadlinePassed {
    $path = Join-Path $ns 'deadline'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return $false
    }
    try {
        $value = ([IO.File]::ReadAllText($path)).Trim()
        return $value -match '^[0-9]+$' -and (Get-NSUnixTime) -ge [long]$value
    }
    catch {
        return $false
    }
}

function Get-NSTranscript {
    $recorded = Get-NSSessionValue 'Transcript'
    if (-not [string]::IsNullOrEmpty($recorded) -and (Test-Path -LiteralPath $recorded -PathType Leaf)) {
        return $recorded
    }
    if ($HostName -ne 'claude') {
        return ''
    }
    $slug = $workspace -replace '[^A-Za-z0-9]', '-'
    $directory = Join-Path $HOME ".claude/projects/$slug"
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        return ''
    }
    $latest = Get-ChildItem -LiteralPath $directory -Filter '*.jsonl' -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($null -eq $latest) {
        return ''
    }
    return $latest.FullName
}

function Get-NSLastConversationLine {
    $transcript = Get-NSTranscript
    if ([string]::IsNullOrEmpty($transcript)) {
        return ''
    }
    try {
        $lines = @(Get-Content -LiteralPath $transcript -Tail 25 -ErrorAction Stop)
    }
    catch {
        return ''
    }
    $last = ''
    foreach ($line in $lines) {
        if ($line -match '[^\\]"type"\s*:\s*"(user|assistant)"') {
            $last = $line
        }
    }
    return $last
}

function Test-NSOwnerPaused {
    if ($HostName -ne 'claude') {
        return $false
    }
    return (Get-NSLastConversationLine) -match 'Request interrupted by user'
}

function Test-NSErroredTail {
    if ($HostName -ne 'claude') {
        return $false
    }
    return (Get-NSLastConversationLine) -match '[^\\]"isApiErrorMessage"\s*:\s*true'
}

$script:TranscriptStamp = ''
function Set-NSTranscriptBaseline {
    $transcript = Get-NSTranscript
    if ([string]::IsNullOrEmpty($transcript)) {
        $script:TranscriptStamp = ''
        return
    }
    try {
        $item = Get-Item -LiteralPath $transcript -ErrorAction Stop
        $script:TranscriptStamp = "$($item.Length):$($item.LastWriteTimeUtc.Ticks)"
    }
    catch {
        $script:TranscriptStamp = ''
    }
}

function Test-NSTranscriptPulse {
    $transcript = Get-NSTranscript
    if ([string]::IsNullOrEmpty($transcript)) {
        return $false
    }
    try {
        $item = Get-Item -LiteralPath $transcript -ErrorAction Stop
        $current = "$($item.Length):$($item.LastWriteTimeUtc.Ticks)"
        return -not [string]::IsNullOrEmpty($script:TranscriptStamp) -and $current -ne $script:TranscriptStamp
    }
    catch {
        return $false
    }
}

function Get-NSRegistryState {
    if ($HostName -ne 'claude') {
        return 'Unavailable'
    }
    $sessionId = Get-NSSessionValue 'SessionId'
    if ([string]::IsNullOrEmpty($sessionId)) {
        return 'Unavailable'
    }
    try {
        $output = & claude agents --json 2>$null | Out-String
        if ($LASTEXITCODE -ne 0 -or $output.TrimStart()[0] -ne '[') {
            return 'Unavailable'
        }
        if ($output.Contains('"' + $sessionId + '"')) {
            return 'Present'
        }
        return 'Absent'
    }
    catch {
        return 'Unavailable'
    }
}

function Get-NSHostProcessState {
    try {
        $processes = @(Get-Process -Name $HostName -ErrorAction SilentlyContinue)
        if ($processes.Count -gt 0) {
            return 'Present'
        }
        return 'Absent'
    }
    catch {
        return 'Unavailable'
    }
}

function Get-NSSiteVerdict {
    if (Test-NSOwnerPaused) {
        return 'esc'
    }
    if (Test-NSTranscriptPulse) {
        return 'alive'
    }

    $session = Read-NSSession $ns
    if ($null -ne $session -and -not [string]::IsNullOrEmpty($session.ProcessId)) {
        $processState = Test-NSRecordedProcess $session.ProcessId $session.Start
        if ($processState -eq 'Alive') {
            if (Test-NSErroredTail) {
                return 'wedge'
            }
            return 'silent'
        }
        $registry = Get-NSRegistryState
        if ($registry -eq 'Present') {
            if (Test-NSErroredTail) {
                return 'wedge'
            }
            return 'silent'
        }
        if ($processState -eq 'Dead' -or $registry -eq 'Absent') {
            return 'dead'
        }
        return 'unavailable'
    }

    if ($null -ne $session -and $HostName -eq 'claude') {
        $registry = Get-NSRegistryState
        if ($registry -eq 'Present') {
            if (Test-NSErroredTail) {
                return 'wedge'
            }
            return 'silent'
        }
        if ($registry -eq 'Absent') {
            return 'dead'
        }
    }

    if (Test-NSErroredTail) {
        return 'wedge'
    }
    $hostProcesses = Get-NSHostProcessState
    if ($hostProcesses -eq 'Present') {
        return 'tabs'
    }
    if ($hostProcesses -eq 'Unavailable') {
        return 'unavailable'
    }
    return 'dead'
}

function Quote-NSWindowsArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value -notmatch '[\s"]' -and -not [string]::IsNullOrEmpty($Value)) {
        return $Value
    }
    $builder = New-Object Text.StringBuilder
    $null = $builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes++
            continue
        }
        if ($character -eq '"') {
            $null = $builder.Append(('\' * (($slashes * 2) + 1)))
            $null = $builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) {
            $null = $builder.Append(('\' * $slashes))
            $slashes = 0
        }
        $null = $builder.Append($character)
    }
    if ($slashes -gt 0) {
        $null = $builder.Append(('\' * ($slashes * 2)))
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function Quote-NSPowerShellLiteral {
    param([AllowEmptyString()][string]$Value)
    return "'" + $Value.Replace("'", "''") + "'"
}

function Start-NSAgent {
    param(
        [Parameter(Mandatory = $true)][int]$Attempt,
        [Parameter(Mandatory = $true)][int]$TotalAttempts
    )
    $sessionId = Get-NSSessionValue 'SessionId'
    $fresh = $Attempt -ge $TotalAttempts -and $TotalAttempts -gt 1
    $prompt = if ($fresh) { $freshPrompt } else { $revivalPrompt }
    $lease = Takeover-NSLease $ns $sessionId $HostName
    if ($null -eq $lease) {
        Write-NSLogLine 'watchman: process lease transfer failed - not spawning beside an unfenced session'
        return $false
    }

    $commandName = ''
    $commandArguments = New-Object Collections.Generic.List[string]
    $arguments = New-Object Collections.Generic.List[string]
    if (-not [string]::IsNullOrEmpty($Agent)) {
        $commandName = $Agent
        $commandArguments.Add($prompt)
    }
    elseif ($HostName -eq 'claude') {
        $commandName = 'claude'
        if ($Attempt -eq 1 -and -not [string]::IsNullOrEmpty($sessionId)) {
            $commandArguments.Add('--resume')
            $commandArguments.Add($sessionId)
            $commandArguments.Add('-p')
        }
        elseif ($fresh) {
            $commandArguments.Add('-p')
        }
        else {
            $commandArguments.Add('--continue')
            $commandArguments.Add('-p')
        }
        $commandArguments.Add($prompt)
    }
    else {
        $commandName = 'codex'
        $kind = Get-NSCodexIdentityKind $sessionId
        if ($Attempt -eq 1 -and $kind -eq 'resumable') {
            $commandArguments.Add('exec')
            $commandArguments.Add('resume')
            $commandArguments.Add('-c')
            $commandArguments.Add('sandbox_mode="danger-full-access"')
            $commandArguments.Add($sessionId)
            $commandArguments.Add($prompt)
        }
        else {
            $commandArguments.Add('exec')
            $commandArguments.Add('-s')
            $commandArguments.Add('danger-full-access')
            $commandArguments.Add($freshPrompt)
        }
    }
    $invocation = '& { & ' + (Quote-NSPowerShellLiteral $commandName)
    foreach ($argument in $commandArguments) {
        $invocation += ' ' + (Quote-NSPowerShellLiteral $argument)
    }
    $invocation += '; $nsOk = $?; $nsExit = $LASTEXITCODE; ' +
        'if ($null -ne $nsExit) { exit $nsExit }; if (-not $nsOk) { exit 1 } }'
    $fileName = 'powershell.exe'
    $arguments.Add('-NoProfile')
    $arguments.Add('-NonInteractive')
    $arguments.Add('-ExecutionPolicy')
    $arguments.Add('Bypass')
    $arguments.Add('-Command')
    $arguments.Add($invocation)

    $oldProject = if ($HostName -eq 'claude') { $env:CLAUDE_PROJECT_DIR } else { $env:CODEX_PROJECT_DIR }
    $oldRevival = $env:NIGHTSHIFT_REVIVAL
    $oldGeneration = $env:NIGHTSHIFT_LEASE_GENERATION
    $oldToken = $env:NIGHTSHIFT_LEASE_TOKEN
    try {
        if ($HostName -eq 'claude') {
            $env:CLAUDE_PROJECT_DIR = $workspace
        }
        else {
            $env:CODEX_PROJECT_DIR = $workspace
        }
        $env:NIGHTSHIFT_REVIVAL = '1'
        $env:NIGHTSHIFT_LEASE_GENERATION = [string]$lease.Generation
        $env:NIGHTSHIFT_LEASE_TOKEN = $lease.Token
        $argumentLine = (($arguments | ForEach-Object { Quote-NSWindowsArgument $_ }) -join ' ')
        try {
            $process = Start-Process -FilePath $fileName -ArgumentList $argumentLine `
                -WorkingDirectory $workTarget -WindowStyle Hidden -PassThru -ErrorAction Stop
        }
        catch {
            Write-NSLogLine ('watchman: spawn failed: ' + $_.Exception.Message)
            return $false
        }
        $start = Get-NSProcessStart $process.Id
        $null = Attach-NSLeaseProcess $ns $HostName $lease.Token ([string]$lease.Generation) ([string]$process.Id) $start
        $process.WaitForExit()
        return $process.ExitCode -eq 0
    }
    finally {
        if ($HostName -eq 'claude') {
            $env:CLAUDE_PROJECT_DIR = $oldProject
        }
        else {
            $env:CODEX_PROJECT_DIR = $oldProject
        }
        $env:NIGHTSHIFT_REVIVAL = $oldRevival
        $env:NIGHTSHIFT_LEASE_GENERATION = $oldGeneration
        $env:NIGHTSHIFT_LEASE_TOKEN = $oldToken
    }
}

function Get-NSHoldReason {
    if (Test-Path -LiteralPath (Join-Path $ns 'STOP') -PathType Leaf) {
        return 'stop-work order'
    }
    if ((Test-Path -LiteralPath (Join-Path $ns '.ended') -PathType Leaf) `
        -or -not (Test-Path -LiteralPath $punch -PathType Leaf)) {
        return 'shift ended'
    }
    if ((Get-NSBoxCounts $punch).Open -eq 0) {
        return 'all boxes ticked'
    }
    if (Test-NSDeadlinePassed) {
        return 'deadline passed'
    }
    if ($HostName -eq 'claude' -and (Test-Path -LiteralPath (Join-Path $ns '.session-end') -PathType Leaf)) {
        return 'clean session end'
    }
    $verdict = Get-NSSiteVerdict
    if ($verdict -eq 'alive') { return 'session activity' }
    if ($verdict -eq 'esc') { return 'owner Esc' }
    if ($verdict -eq 'silent') { return 'live shift session' }
    if ($verdict -eq 'tabs') { return "a live $HostName process" }
    if ($verdict -eq 'unavailable') { return 'process evidence unavailable' }
    return ''
}

$workspace = Resolve-NSWorkspaceRoot (Resolve-NSCanonicalPath $Project)
$ns = Join-Path $workspace '.nightshift'
if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
    throw "watchman: no .nightshift at $workspace"
}
$stateKind = Get-NSStateKind $workspace
if ($stateKind -in @('malformed', 'future')) {
    Write-NSReason $ns 'unsupported-state' $stateKind
    throw ('watchman: ' + (Get-NSStateRefuseMessage $stateKind))
}
try {
    $workTarget = Resolve-NSWorkTarget $workspace
}
catch {
    $workTarget = $workspace
}

if ($IntervalMinutes -lt 0) {
    $override = [string]$env:NIGHTSHIFT_WATCH
    $rawInterval = Get-NSRule $workspace 'watchMinutes' $override
    if ($rawInterval -notmatch '^[0-9]+$') {
        Write-NSReason $ns 'unreadable-rules' 'watchMinutes'
        throw 'watchman: watchMinutes is missing or is not a whole number'
    }
    $IntervalMinutes = [int]$rawInterval
}
if ($IntervalMinutes -eq 0) {
    exit 0
}

$retrySpacing = Get-NSRule $workspace 'watchRetrySeconds' ([string]$env:NIGHTSHIFT_WATCH_RETRY)
$revivalPrompt = Get-NSRule $workspace 'revivalPrompt' ([string]$env:NIGHTSHIFT_REVIVAL_PROMPT)
$freshPrompt = Get-NSRule $workspace 'freshRevivalPrompt' ([string]$env:NIGHTSHIFT_FRESH_PROMPT)
if ([string]::IsNullOrEmpty($retrySpacing) -or [string]::IsNullOrEmpty($revivalPrompt) `
    -or [string]::IsNullOrEmpty($freshPrompt)) {
    Write-NSReason $ns 'unreadable-rules' 'recovery prompt or retry spacing'
    throw 'watchman: rules.json is missing recovery settings'
}
$retryValues = New-Object Collections.Generic.List[int]
foreach ($value in ($retrySpacing -split '\s+')) {
    if ([string]::IsNullOrEmpty($value)) {
        continue
    }
    if ($value -notmatch '^[0-9]+$') {
        throw 'watchman: watchRetrySeconds must contain whole seconds'
    }
    $retryValues.Add([int]$value)
}

$punch = Join-Path $ns 'punch-list.md'
$log = Join-Path $ns 'shift-log.md'
$pidFile = Join-Path $ns '.watchman'
$tick = Join-Path $ns '.watchman-tick'

$watchmanMutex = Enter-NSMutex $ns '.watchman'
if ($null -eq $watchmanMutex) {
    throw 'watchman: another watchman owns this workspace'
}

try {
    if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
        try {
            $oldOwner = [IO.File]::ReadAllLines($pidFile)
            $oldPid = if ($oldOwner.Count -gt 0) { $oldOwner[0] } else { '' }
            $oldStart = if ($oldOwner.Count -gt 1) { $oldOwner[1] } else { '' }
            if ($oldPid -ne [string]$PID -and (Test-NSRecordedProcess $oldPid $oldStart) -eq 'Alive') {
                throw "watchman: already watching (pid $oldPid)"
            }
        }
        catch {
            if ($_.Exception.Message -match 'already watching') {
                throw
            }
        }
    }
    $null = Write-NSAtomicLines -Path $pidFile -Lines @([string]$PID, (Get-NSProcessStart $PID))

    Write-NSLogLine "watchman ($HostName, Windows) armed - every ${IntervalMinutes}m"
    [IO.File]::WriteAllText($tick, '', $utf8)
    Set-NSTranscriptBaseline

    $sleepSeconds = $IntervalMinutes * 60
    if (-not [string]::IsNullOrEmpty([string]$env:NIGHTSHIFT_WATCH_SLEEP)) {
        if ([string]$env:NIGHTSHIFT_WATCH_SLEEP -notmatch '^[0-9]+$') {
            throw 'watchman: NIGHTSHIFT_WATCH_SLEEP must be whole seconds'
        }
        $sleepSeconds = [int]$env:NIGHTSHIFT_WATCH_SLEEP
    }

    $wake = 0
    $previousStandby = ''
    while ($true) {
        Start-Sleep -Seconds $sleepSeconds
        $wake++

        if (Test-Path -LiteralPath (Join-Path $ns 'STOP') -PathType Leaf) {
            Write-NSReason $ns 'owner-stop'
            Write-NSLogLine 'watchman: stop-work order - standing down'
            exit 0
        }
        if (Test-Path -LiteralPath (Join-Path $ns '.ended') -PathType Leaf) {
            Write-NSReason $ns 'completed'
            exit 0
        }
        if (-not (Test-Path -LiteralPath $punch -PathType Leaf)) {
            Write-NSReason $ns 'stand-down' 'punch list missing'
            exit 0
        }

        $session = Read-NSSession $ns
        $sessionHost = if ($null -eq $session) { 'claude' } else { $session.HostName }
        if ($sessionHost -ne $HostName) {
            Write-NSReason $ns 'wrong-host' $sessionHost
            Write-NSLogLine "watchman: shift belongs to $sessionHost - standing down"
            exit 0
        }

        $counts = Get-NSBoxCounts $punch
        if ($counts.Open -eq 0 -or (Test-NSDeadlinePassed)) {
            $label = if ($counts.Open -eq 0) { 'every box is ticked' } else { 'quitting time passed' }
            Write-NSLogLine "watchman: $label but the shift never clocked out - spawning the clock-out"
            $null = Start-NSAgent 1 2
            if (Test-Path -LiteralPath (Join-Path $ns '.ended') -PathType Leaf) {
                Write-NSReason $ns $(if ($counts.Open -eq 0) { 'completed' } else { 'deadline' })
                exit 0
            }
            Write-NSLogLine 'watchman: clock-out returned without releasing the shift - retrying next wake'
            Set-NSTranscriptBaseline
            [IO.File]::WriteAllText($tick, '', $utf8)
            if ($MaxWakes -gt 0 -and $wake -ge $MaxWakes) {
                exit 7
            }
            continue
        }

        if ($HostName -eq 'claude' -and (Test-Path -LiteralPath (Join-Path $ns '.session-end') -PathType Leaf)) {
            Write-NSReason $ns 'clean-session-end'
            Write-NSLogLine 'watchman: clean session end - the owner closed it; standing down'
            exit 0
        }

        $verdict = Get-NSSiteVerdict
        if ($verdict -eq 'alive') {
            $previousStandby = ''
        }
        elseif ($verdict -eq 'esc') {
            Write-NSReason $ns 'esc-standby'
            if ($previousStandby -ne 'esc') {
                Write-NSLogLine 'watchman: owner pressed Esc - standing by, not resuming'
            }
            $previousStandby = 'esc'
        }
        elseif ($verdict -eq 'silent' -or $verdict -eq 'tabs') {
            Write-NSReason $ns 'silent-standby' $verdict
            if ($previousStandby -ne $verdict) {
                Write-NSLogLine "watchman: live $HostName process evidence - standing by"
            }
            $previousStandby = $verdict
        }
        elseif ($verdict -eq 'unavailable') {
            Write-NSReason $ns 'process-evidence-unavailable'
            if ($previousStandby -ne 'unavailable') {
                Write-NSLogLine 'watchman: process evidence unavailable - standing down, not reviving'
            }
            $previousStandby = 'unavailable'
        }
        else {
            $previousStandby = ''
            $sessionId = Get-NSSessionValue 'SessionId'
            if ($HostName -eq 'codex' -and [string]::IsNullOrEmpty($Agent)) {
                $kind = Get-NSCodexIdentityKind $sessionId
                if ($kind -notin @('resumable', 'missing')) {
                    Write-NSReason $ns 'non-resumable-session' $kind
                    Write-NSLogLine "watchman: recorded Codex identity is $kind - standing down"
                    exit 0
                }
            }
            if ($verdict -eq 'wedge') {
                Write-NSLogLine 'watchman: probable API wedge - reviving the recorded conversation'
            }

            $totalAttempts = $retryValues.Count + 1
            $revived = $false
            $aborted = ''
            for ($attempt = 1; $attempt -le $totalAttempts; $attempt++) {
                if ($attempt -gt 1) {
                    $gap = $retryValues[$attempt - 2]
                    if ($gap -gt 0) {
                        Start-Sleep -Seconds $gap
                    }
                    $aborted = Get-NSHoldReason
                    if (-not [string]::IsNullOrEmpty($aborted)) {
                        Write-NSLogLine "watchman: $aborted during retries - holding the remaining attempts"
                        break
                    }
                }
                Write-NSLogLine "watchman: site dead quiet with open boxes - resume attempt $attempt"
                if (Start-NSAgent $attempt $totalAttempts) {
                    $revived = $true
                    break
                }
                Set-NSTranscriptBaseline
            }
            if ($revived) {
                if ($totalAttempts -gt 1 -and $attempt -ge $totalAttempts) {
                    Write-NSReason $ns 'fresh-fallback'
                }
                elseif ([string]::IsNullOrEmpty($sessionId)) {
                    Write-NSReason $ns 'fresh-fallback'
                }
                else {
                    Write-NSReason $ns 'revived'
                }
                Write-NSLogLine 'watchman: revival returned - the night continues'
            }
            elseif ([string]::IsNullOrEmpty($aborted)) {
                Write-NSReason $ns 'exhausted-retry'
                Write-NSLogLine "watchman: all $totalAttempts attempts failed - retrying next wake"
            }
        }

        Set-NSTranscriptBaseline
        [IO.File]::WriteAllText($tick, '', $utf8)
        if ($MaxWakes -gt 0 -and $wake -ge $MaxWakes) {
            exit 7
        }
    }
}
finally {
    try {
        if (Test-Path -LiteralPath $pidFile -PathType Leaf) {
            $ownerPid = ([IO.File]::ReadAllLines($pidFile) | Select-Object -First 1)
            if ($ownerPid -eq [string]$PID) {
                Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        Exit-NSMutex $watchmanMutex
    }
}
