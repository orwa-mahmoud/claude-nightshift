param(
    [string]$Project = [Environment]::CurrentDirectory,
    [string]$At = '',
    [string]$Agent = 'claude -p',
    [string]$Prompt = '/nightshift:start',
    [switch]$List,
    [switch]$Remove,
    [switch]$Preflight,
    [switch]$AsJson
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force

function Escape-NSSingleQuoted {
    param([Parameter(Mandatory = $true)][string]$Value)
    return $Value.Replace("'", "''")
}

function Escape-NSXml {
    param([AllowEmptyString()][string]$Value)
    return [Security.SecurityElement]::Escape($Value)
}

function Get-NSProjectHash {
    param([Parameter(Mandatory = $true)][string]$Value)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Value.ToUpperInvariant())
        $hash = $sha.ComputeHash($bytes)
    }
    finally {
        $sha.Dispose()
    }
    return (($hash[0..5] | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Get-NSTask {
    param([Parameter(Mandatory = $true)][string]$Name)
    try {
        return Get-ScheduledTask -TaskName $Name -ErrorAction Stop
    }
    catch {
        return $null
    }
}

$hostPath = Resolve-NSCanonicalPath $Project
$workspace = Resolve-NSWorkspaceRoot $hostPath
$ns = Join-Path $workspace '.nightshift'
if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
    throw "schedule: no .nightshift at $workspace - run Setup first"
}
$stateKind = Get-NSStateKind $workspace
if ($stateKind -in @('malformed', 'future')) {
    throw ('schedule: ' + (Get-NSStateRefuseMessage $stateKind))
}

$baseName = (Split-Path -Leaf $workspace) -replace '[^A-Za-z0-9]+', '-'
$baseName = $baseName.Trim('-')
if ([string]::IsNullOrEmpty($baseName)) {
    $baseName = 'project'
}
$id = "$baseName-$(Get-NSProjectHash $workspace)"
$taskName = "Nightshift-$id"
$taskPath = '\'
$log = Join-Path $ns 'scheduled.log'

if ($List) {
    $task = Get-NSTask $taskName
    if ($null -eq $task) {
        "Nothing registered for $workspace"
    }
    else {
        "Registered for ${workspace}:"
        "  task: $taskPath$taskName"
        "  state: $($task.State)"
    }
    exit 0
}

if ($Remove) {
    if ($null -eq (Get-NSTask $taskName)) {
        "Nothing registered for $workspace"
        exit 0
    }
    "To unregister:"
    ''
    "  Unregister-ScheduledTask -TaskPath '$taskPath' -TaskName '$taskName' -Confirm:`$false"
    exit 0
}

$timeText = if ($Preflight -and [string]::IsNullOrEmpty($At)) { '04:05' } else { $At }
if ($timeText -notmatch '^(?<hour>[01][0-9]|2[0-3]):(?<minute>[0-5][0-9])$') {
    throw "schedule: -At needs a 24-hour HH:mm value, got '$timeText'"
}
$hour = [int]$Matches.hour
$minute = [int]$Matches.minute
$start = (Get-Date).Date.AddHours($hour).AddMinutes($minute)
if ($start -le (Get-Date)) {
    $start = $start.AddDays(1)
}

$quotedWorkspace = Escape-NSSingleQuoted $workspace
$quotedPrompt = Escape-NSSingleQuoted $Prompt
$quotedLog = Escape-NSSingleQuoted $log
$runScript = "& { Set-Location -LiteralPath '$quotedWorkspace'; $Agent '$quotedPrompt' *>> '$quotedLog' }"
$encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($runScript))
$identity = [Security.Principal.WindowsIdentity]::GetCurrent().Name

$xml = @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.4" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo>
    <Description>Start the Nightshift punch list for $(Escape-NSXml $workspace)</Description>
    <URI>$(Escape-NSXml "$taskPath$taskName")</URI>
  </RegistrationInfo>
  <Triggers>
    <CalendarTrigger>
      <StartBoundary>$($start.ToString('yyyy-MM-ddTHH:mm:ss'))</StartBoundary>
      <Enabled>true</Enabled>
      <ScheduleByDay><DaysInterval>1</DaysInterval></ScheduleByDay>
    </CalendarTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author">
      <UserId>$(Escape-NSXml $identity)</UserId>
      <LogonType>InteractiveToken</LogonType>
      <RunLevel>LeastPrivilege</RunLevel>
    </Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <IdleSettings>
      <StopOnIdleEnd>false</StopOnIdleEnd>
      <RestartOnIdle>false</RestartOnIdle>
    </IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <RunOnlyIfIdle>false</RunOnlyIfIdle>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
  </Settings>
  <Actions Context="Author">
    <Exec>
      <Command>powershell.exe</Command>
      <Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encodedCommand</Arguments>
      <WorkingDirectory>$(Escape-NSXml $workspace)</WorkingDirectory>
    </Exec>
  </Actions>
</Task>
"@

try {
    $null = [xml]$xml
}
catch {
    throw 'schedule: generated Task Scheduler XML is invalid'
}

$xmlBase64 = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($xml))
$registerCommand = "`$xml = [Text.Encoding]::Unicode.GetString([Convert]::FromBase64String('$xmlBase64')); Register-ScheduledTask -TaskPath '$taskPath' -TaskName '$taskName' -Xml `$xml"

if ($Preflight) {
    $failures = New-Object Collections.Generic.List[string]
    "Nightshift schedule preflight"
    "Host:      $hostPath"
    "Workspace: $workspace"
    try {
        $target = Resolve-NSWorkTarget $workspace
        "Work:      $target"
    }
    catch {
        'Work:      unresolved (workspace itself will be the working directory)'
    }
    $rules = Get-NSRulesObject $workspace
    if ($null -eq $rules) {
        $failures.Add('rules.json is unreadable or is not a JSON object')
        'FAIL rules.json is unreadable or is not a JSON object'
    }
    else {
        $watch = Get-NSRule $workspace 'watchMinutes'
        if ($watch -notmatch '^[0-9]+$') {
            $failures.Add('watchMinutes is missing or invalid')
            'FAIL watchMinutes is missing or invalid'
        }
        else {
            "OK   rules.json (watchMinutes $watch)"
        }
    }
    $counts = Get-NSBoxCounts (Join-Path $ns 'punch-list.md')
    if ($counts.Open -eq 0) {
        $failures.Add('punch list has no open items')
        'FAIL punch list has no open items - a scheduled start promotes nothing'
    }
    else {
        "OK   punch list has $($counts.Open) open item(s)"
    }
    'OK   Task Scheduler XML parses'
    "OK   task path $taskPath$taskName"
    "OK   run log $log"
    $agentExecutable = ($Agent.Trim() -split '\s+')[0].Trim("'`"")
    if ($null -eq (Get-Command $agentExecutable -ErrorAction SilentlyContinue)) {
        "WARN selected agent $agentExecutable is not on PATH - the scheduled run cannot start on this machine"
    }
    else {
        "OK   selected agent executable $agentExecutable"
    }
    ''
    'Claude Code'
    $claudeCommand = Get-Command claude -ErrorAction SilentlyContinue
    if ($null -eq $claudeCommand) {
        'WARN claude is not on PATH - a Claude scheduled run cannot start'
    }
    else {
        "OK   binary $($claudeCommand.Source)"
    }
    $permissionGranted = $false
    $permissionFiles = @(
        (Join-Path $workspace '.claude/settings.local.json'),
        (Join-Path $workspace '.claude/settings.json'),
        (Join-Path $hostPath '.claude/settings.local.json'),
        (Join-Path $hostPath '.claude/settings.json')
    ) | Select-Object -Unique
    foreach ($permissionFile in $permissionFiles) {
        if (Test-Path -LiteralPath $permissionFile -PathType Leaf) {
            $settingsText = [IO.File]::ReadAllText($permissionFile)
            if ($settingsText -match 'bypassPermissions|allow') {
                $permissionGranted = $true
                break
            }
        }
    }
    if ($permissionGranted) {
        'OK   headless permissions look granted'
    }
    else {
        'WARN no bypassPermissions/allow in .claude\settings*.json - a headless Claude run may stall'
    }
    ''
    'Codex'
    $codexCommand = Get-Command codex -ErrorAction SilentlyContinue
    if ($null -eq $codexCommand) {
        'WARN codex is not on PATH - a Codex scheduled run cannot start'
    }
    else {
        "OK   binary $($codexCommand.Source)"
    }
    'OK   recommended agent: codex exec -s danger-full-access'
    if ($Agent -match '(?i)codex') {
        if ($Agent -match '(?i)danger-full-access|bypass') {
            'OK   -Agent carries a headless sandbox grant'
        }
        else {
            'WARN -Agent names Codex without a headless grant; the run may stall on the first tool'
        }
    }
    if ($null -ne (Get-NSTask $taskName)) {
        'WARN an entry is already registered for this project - generation will refuse a second one'
    }
    ''
    'Task uses the current interactive user token, starts a missed run when that user is next logged in, and never wakes a sleeping or powered-off machine.'
    'Preflight writes and registers nothing.'
    if ($failures.Count -gt 0) {
        exit 1
    }
    exit 0
}

if ($null -ne (Get-NSTask $taskName)) {
    'Already registered for this project - nothing to install.'
    ''
    "  task: $taskPath$taskName"
    ''
    'Two entries would put two agents on one punch list. Remove the existing task first to replace it.'
    exit 3
}

if ($AsJson) {
    [pscustomobject]@{
        project = $workspace
        taskPath = $taskPath
        taskName = $taskName
        start = $start.ToString('o')
        runScript = $runScript
        xml = $xml
        registerCommand = $registerCommand
        log = $log
    } | ConvertTo-Json -Depth 5
    exit 0
}

"Scheduled start for $workspace at $timeText"
''
"Task: $taskPath$taskName"
''
'Run this PowerShell command to register it:'
''
"  $registerCommand"
''
'Generated Task Scheduler XML:'
''
$xml
''
'The task runs only in the current user session. StartWhenAvailable catches a missed time after login, but Nightshift does not wake or power on the machine.'
"Check it: & '$PSCommandPath' -Project '$quotedWorkspace' -List"
"Output of each run lands in $log"
