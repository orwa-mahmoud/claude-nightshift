# Portable PowerShell probe for the on-disk worker fence.
# Run on macOS or Windows: pwsh -File tests/windows/fence-check-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$plugin = Join-Path $repository 'plugins/nightshift'
Import-Module (Join-Path $plugin 'lib/Nightshift.psm1') -Force -DisableNameChecking

$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-fence-logic-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root -Force
$ns = Join-Path $root '.nightshift'
$null = New-Item -ItemType Directory -Path $ns -Force
[IO.File]::WriteAllText((Join-Path $ns 'punch-list.md'), "## Items`n- [ ] **1. first.**`n")
$null = New-Item -ItemType File -Path (Join-Path $ns '.shift-armed') -Force

$wrapper = Join-Path $plugin 'runtime/windows/continuity-handoff.ps1'
$bashFence = Join-Path $plugin 'runtime/continuity-handoff.sh'

try {
    $missing = Test-NSHandoffFence -Project $root
    Expect-True ($missing.ExitCode -eq 2 -and -not $missing.takeoverAllowed) `
        "missing lease refuses: exit=$($missing.ExitCode) allowed=$($missing.takeoverAllowed)"

    $ok = Write-NSLease -NightshiftDir $ns -SessionId 'shift-session' -HostName 'claude' `
        -Generation 1 -Nonce 'fence.1' -ProcessId '' -Start ''
    Expect-True $ok 'empty-pid lease writes'
    $fenced = Test-NSHandoffFence -Project $root
    Expect-True ($fenced.ExitCode -eq 0 -and $fenced.takeoverAllowed -and $fenced.priorOwnerFenced) `
        "empty pid is fenced: exit=$($fenced.ExitCode) allowed=$($fenced.takeoverAllowed)"

    $livePid = $PID
    $liveStart = ''
    try {
        $liveStart = (Get-Process -Id $livePid).StartTime.ToUniversalTime().ToString('o')
    }
    catch { }
    $ok = Write-NSLease -NightshiftDir $ns -SessionId 'shift-session' -HostName 'claude' `
        -Generation 1 -Nonce '' -ProcessId ([string]$livePid) -Start $liveStart
    Expect-True $ok 'live-pid lease writes'
    $live = Test-NSHandoffFence -Project $root
    Expect-True ($live.ExitCode -eq 1 -and -not $live.takeoverAllowed -and $live.priorWorkerActive) `
        "live pid refuses: exit=$($live.ExitCode) active=$($live.priorWorkerActive)"

    $wrapperMissing = & $wrapper -Command fence-check -Project $root -Manifest (Join-Path $repository 'tests/fixtures/continuity/fence-ok.json')
    $wrapperCode = $LASTEXITCODE
    Expect-True ($wrapperCode -eq 1) "wrapper ignores JSON flags over a live lease: exit=$wrapperCode out=$wrapperMissing"

    $ok = Write-NSLease -NightshiftDir $ns -SessionId 'shift-session' -HostName 'claude' `
        -Generation 1 -Nonce 'fence.1' -ProcessId '' -Start ''
    Expect-True $ok 'restore fenced lease'
    if (Get-Command bash -ErrorAction SilentlyContinue) {
        $bashLines = @(& bash $bashFence fence-check --project $root)
        $bashCode = $LASTEXITCODE
        $pwsh = Test-NSHandoffFence -Project $root
        Expect-True ($bashCode -eq $pwsh.ExitCode) "twins share exit: bash=$bashCode pwsh=$($pwsh.ExitCode)"
        $bashDoc = ($bashLines -join "`n") | ConvertFrom-Json
        Expect-True ($bashDoc.takeoverAllowed -eq $pwsh.takeoverAllowed) `
            "twins share takeoverAllowed: bash=$($bashDoc.takeoverAllowed) pwsh=$($pwsh.takeoverAllowed)"
        Expect-True ($bashDoc.priorOwnerFenced -eq $pwsh.priorOwnerFenced) `
            "twins share priorOwnerFenced: bash=$($bashDoc.priorOwnerFenced) pwsh=$($pwsh.priorOwnerFenced)"
        Expect-True ($bashDoc.action -eq $pwsh.action) "twins share action: bash=$($bashDoc.action) pwsh=$($pwsh.action)"
    }
}
finally {
    if (Test-Path -LiteralPath $root) {
        Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host ("{0} fence-check-logic failures" -f $failures.Count)
    exit 1
}
Write-Host 'fence-check-logic ok'
exit 0
