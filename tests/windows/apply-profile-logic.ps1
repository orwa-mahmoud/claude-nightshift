# Portable PowerShell coverage for Windows apply-profile armed refuse.
# Run on macOS or Windows: pwsh -File tests/windows/apply-profile-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/apply-profile.ps1'
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

function Invoke-ApplyProfile {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [switch]$Apply
    )
    $argList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $helper, '-Project', $Project,
        '-Profile', 'no-push', '-Mode', 'fill'
    )
    if ($Apply) {
        $argList += '-Apply'
    }
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

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-apply-profile-logic-" + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path (Join-Path $root '.nightshift') -Force
    Copy-Item -LiteralPath $template -Destination (Join-Path $root '.nightshift/rules.json')
    [IO.File]::WriteAllText((Join-Path $root '.nightshift/.shift-armed'), '')
    $before = Get-FileHash -LiteralPath (Join-Path $root '.nightshift/rules.json') -Algorithm SHA256
    $refused = Invoke-ApplyProfile $root -Apply
    Expect-True ($refused.ExitCode -eq 2) "armed apply exits 2 (got $($refused.ExitCode) $($refused.Stderr))"
    Expect-True ($refused.Stderr -match 'refuse to write rules while the shift is armed') `
        "armed refuse names the armed marker: $($refused.Stderr)"
    $after = Get-FileHash -LiteralPath (Join-Path $root '.nightshift/rules.json') -Algorithm SHA256
    Expect-True ($after.Hash -eq $before.Hash) 'armed refuse writes no rules.json'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "apply-profile-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'apply-profile-logic ok'
exit 0
