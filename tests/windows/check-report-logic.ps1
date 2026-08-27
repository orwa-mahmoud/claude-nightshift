# Portable PowerShell coverage for cited-research check-report.
# Run on macOS or Windows: pwsh -File tests/windows/check-report-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/check-report.ps1'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function Invoke-CheckReport {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [string[]]$Extra = @()
    )
    $argList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $helper, '-Project', $Project
    ) + $Extra
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

function Write-NSValidBundle {
    param([string]$Dir)
    $null = New-Item -ItemType Directory -Path $Dir -Force
    $tsv = @(
        "ok`t2026-08-28T08:00:00Z`tS1`thttps://example.com/page",
        "unavailable`t2026-08-28T08:00:00Z`tS2`thttps://example.com/gone"
    )
    [IO.File]::WriteAllLines((Join-Path $Dir 'sources.tsv'), $tsv)
    $report = @(
        '# Brief',
        '',
        '## Executive summary',
        '',
        'S1 describes the published page. S2 could not be retrieved.',
        '',
        '## Sources',
        '',
        '- S1 ok https://example.com/page retrieved 2026-08-28T08:00:00Z',
        '- S2 unavailable https://example.com/gone HTTP 404',
        '',
        '## Observations',
        '',
        'The page states a heading of "Hello" [S1].',
        '',
        '## Inferences',
        '',
        'Without S2, ranking claims are out of scope.'
    )
    [IO.File]::WriteAllLines((Join-Path $Dir 'report.md'), $report)
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-check-report-logic-" + [guid]::NewGuid().ToString('N'))
try {
    $okDir = Join-Path $root 'ok'
    Write-NSValidBundle $okDir
    $ok = Invoke-CheckReport $okDir @(
        '-Report', (Join-Path $okDir 'report.md'),
        '-Manifest', (Join-Path $okDir 'sources.tsv'),
        '-Output', (Join-Path $okDir 'report.md')
    )
    Expect-True ($ok.ExitCode -eq 0) "valid report exits 0 (got $($ok.ExitCode) $($ok.Stderr))"

    $fakeDir = Join-Path $root 'fake'
    Write-NSValidBundle $fakeDir
    [IO.File]::AppendAllText((Join-Path $fakeDir 'report.md'), "`nInvented claim [S9].`n")
    $fake = Invoke-CheckReport $fakeDir @(
        '-Report', (Join-Path $fakeDir 'report.md'),
        '-Manifest', (Join-Path $fakeDir 'sources.tsv')
    )
    Expect-True ($fake.ExitCode -eq 2) "fabricated citation exits 2 (got $($fake.ExitCode))"
    Expect-True ($fake.Stderr -match 'fabricated citation') 'names the fabricated id'

    $secretDir = Join-Path $root 'secret'
    Write-NSValidBundle $secretDir
    [IO.File]::AppendAllText((Join-Path $secretDir 'report.md'), "`npassword=supersecret`n")
    $secret = Invoke-CheckReport $secretDir @(
        '-Report', (Join-Path $secretDir 'report.md'),
        '-Manifest', (Join-Path $secretDir 'sources.tsv')
    )
    Expect-True ($secret.ExitCode -eq 2) "secret line exits 2 (got $($secret.ExitCode))"
    Expect-True ($secret.Stderr -match 'secret') 'names the secret refusal'

    $emptyDir = Join-Path $root 'empty'
    Write-NSValidBundle $emptyDir
    $blank = Join-Path $emptyDir 'blank.md'
    [IO.File]::WriteAllText($blank, '')
    $empty = Invoke-CheckReport $emptyDir @(
        '-Report', (Join-Path $emptyDir 'report.md'),
        '-Manifest', (Join-Path $emptyDir 'sources.tsv'),
        '-Output', $blank
    )
    Expect-True ($empty.ExitCode -eq 2) "empty output exits 2 (got $($empty.ExitCode))"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "check-report logic failed ($($failures.Count)):"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}
Write-Host 'check-report logic passed'
exit 0
