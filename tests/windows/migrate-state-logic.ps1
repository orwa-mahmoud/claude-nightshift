# Portable PowerShell coverage for Windows migrate-state armed refuse and legacy write.
# Run on macOS or Windows: pwsh -File tests/windows/migrate-state-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/migrate-state.ps1'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function Invoke-Migrate {
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

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-migrate-state-logic-" + [guid]::NewGuid().ToString('N'))
try {
    $legacy = Join-Path $root 'legacy'
    $null = New-Item -ItemType Directory -Path (Join-Path $legacy '.nightshift') -Force
    $wrote = Invoke-Migrate $legacy
    Expect-True ($wrote.ExitCode -eq 0) "unarmed legacy exits 0 (got $($wrote.ExitCode) $($wrote.Stderr))"
    Expect-True ($wrote.Stdout -match 'state-version is now 1') 'unarmed legacy writes version 1'
    $marker = Join-Path $legacy '.nightshift/state-version'
    Expect-True ((Test-Path -LiteralPath $marker -PathType Leaf) `
        -and (([IO.File]::ReadAllText($marker)).Trim() -eq '1')) `
        'unarmed legacy publishes a current marker'

    $again = Invoke-Migrate $legacy
    Expect-True ($again.ExitCode -eq 0) "already current exits 0 (got $($again.ExitCode) $($again.Stderr))"
    Expect-True ($again.Stdout -match 'state-version is already 1') 'current state is idempotent'

    $armed = Join-Path $root 'armed'
    $null = New-Item -ItemType Directory -Path (Join-Path $armed '.nightshift') -Force
    [IO.File]::WriteAllText((Join-Path $armed '.nightshift/.shift-armed'), '')
    $refused = Invoke-Migrate $armed
    Expect-True ($refused.ExitCode -eq 1) "armed legacy exits 1 (got $($refused.ExitCode) $($refused.Stderr))"
    Expect-True ($refused.Stderr -match 'refuse to migrate while the shift is armed') `
        'armed refuse names the armed marker'
    Expect-True (-not (Test-Path -LiteralPath (Join-Path $armed '.nightshift/state-version'))) `
        'armed refuse writes no state-version'

    $future = Join-Path $root 'future'
    $null = New-Item -ItemType Directory -Path (Join-Path $future '.nightshift') -Force
    [IO.File]::WriteAllText((Join-Path $future '.nightshift/state-version'), "9`n")
    $blocked = Invoke-Migrate $future
    Expect-True ($blocked.ExitCode -eq 2) "future marker exits 2 (got $($blocked.ExitCode) $($blocked.Stderr))"
    Expect-True (([IO.File]::ReadAllText((Join-Path $future '.nightshift/state-version'))).Trim() -eq '9') `
        'future marker is left untouched'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "migrate-state logic failed ($($failures.Count)):"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}
Write-Host 'migrate-state logic passed'
exit 0
