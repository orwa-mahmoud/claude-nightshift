# Portable PowerShell coverage for artifact-mode write-receipt.
# Run on macOS or Windows: pwsh -File tests/windows/write-receipt-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/write-receipt.ps1'
$doctor = Join-Path $repository 'plugins/nightshift/runtime/windows/doctor.ps1'
$module = Join-Path $repository 'plugins/nightshift/lib/Nightshift.psm1'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function Invoke-WriteReceipt {
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

function Invoke-Doctor {
    param([Parameter(Mandatory = $true)][string]$Project)
    $argList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $doctor, '-Project', $Project
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

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-write-receipt-logic-" + [guid]::NewGuid().ToString('N'))
try {
    $artifact = Join-Path $root 'notes'
    $outDir = Join-Path $artifact 'out'
    $ns = Join-Path $artifact '.nightshift'
    $null = New-Item -ItemType Directory -Path $ns, $outDir -Force
    [IO.File]::WriteAllText((Join-Path $ns 'work-mode'), "artifact`n")
    [IO.File]::WriteAllText((Join-Path $ns 'work-target'), "$artifact`n")
    Import-Module $module -Force -DisableNameChecking
    Expect-True ($null -eq (Get-NSLatestReceipt $artifact)) 'no latest receipt before any write'

    $note = Join-Path $outDir 'topic.md'
    [IO.File]::WriteAllText($note, "research notes`n")

    $ok = Invoke-WriteReceipt $artifact @(
        '-Item', 'Write the brief',
        '-Verify', 'file exists',
        '-Source', 'https://example.com/doc',
        '-Output', $note
    )
    Expect-True ($ok.ExitCode -eq 0) "artifact success exits 0 (got $($ok.ExitCode) $($ok.Stderr))"
    Expect-True (Test-Path -LiteralPath $ok.Stdout.Trim() -PathType Leaf) 'prints a receipt path'
    Expect-True ($ok.Stdout -match [regex]::Escape((Join-Path $ns 'receipts'))) 'receipt lands under .nightshift/receipts'
    $body = [IO.File]::ReadAllText($ok.Stdout.Trim())
    Expect-True ($body -match 'mode: artifact') 'receipt records artifact mode'
    Expect-True ($body -match 'sha256:') 'receipt records file identity'
    $firstName = [IO.Path]::GetFileName($ok.Stdout.Trim())
    Expect-True (([IO.Path]::GetFileName((Get-NSLatestReceipt $artifact))) -eq $firstName) `
        'Get-NSLatestReceipt names the first receipt'
    Start-Sleep -Seconds 1

    $secret = Invoke-WriteReceipt $artifact @(
        '-Item', 'x',
        '-Verify', 'ok',
        '-Decision', 'password=supersecret',
        '-Output', $note
    )
    Expect-True ($secret.ExitCode -eq 0) "secret decision still writes (got $($secret.ExitCode))"
    $secretBody = [IO.File]::ReadAllText($secret.Stdout.Trim())
    Expect-True ($secretBody -notmatch 'supersecret') 'secret value is omitted'
    Expect-True ($secretBody -match 'decision: \(redacted\)') 'secret decision is redacted'
    $secondName = [IO.Path]::GetFileName($secret.Stdout.Trim())
    Expect-True (([IO.Path]::GetFileName((Get-NSLatestReceipt $artifact))) -eq $secondName) `
        'Get-NSLatestReceipt names the newest receipt'
    $report = Invoke-Doctor $artifact
    Expect-True ($report.ExitCode -eq 0) "Doctor exits 0 (got $($report.ExitCode) $($report.Stderr))"
    Expect-True ($report.Stdout -match 'artifact receipts 2') 'Doctor counts both receipts'
    Expect-True ($report.Stdout -match [regex]::Escape("latest artifact receipt $secondName")) `
        'Doctor names the newest receipt filename'
    Expect-True ($report.Stdout -notmatch [regex]::Escape("latest artifact receipt $firstName")) `
        'Doctor does not name the older receipt as latest'

    $empty = Join-Path $outDir 'blank.md'
    [IO.File]::WriteAllText($empty, '')
    $blank = Invoke-WriteReceipt $artifact @(
        '-Item', 'x', '-Verify', 'ok', '-Output', $empty
    )
    Expect-True ($blank.ExitCode -eq 2) "empty output exits 2 (got $($blank.ExitCode))"

    $missing = Invoke-WriteReceipt $artifact @(
        '-Item', 'x', '-Verify', 'ok', '-Output', (Join-Path $outDir 'nope.md')
    )
    Expect-True ($missing.ExitCode -eq 2) "missing output exits 2 (got $($missing.ExitCode))"

    $repo = Join-Path $root 'repo'
    $null = New-Item -ItemType Directory -Path (Join-Path $repo '.nightshift') -Force
    [IO.File]::WriteAllText((Join-Path $repo '.nightshift/work-mode'), "repository`n")
    $repoOut = Join-Path $repo 'out.md'
    [IO.File]::WriteAllText($repoOut, "ok`n")
    $refused = Invoke-WriteReceipt $repo @(
        '-Item', 'x', '-Verify', 'ok', '-Output', $repoOut
    )
    Expect-True ($refused.ExitCode -eq 3) "repository mode exits 3 (got $($refused.ExitCode) $($refused.Stderr))"
    Expect-True (-not (Test-Path -LiteralPath (Join-Path $repo '.nightshift/receipts'))) `
        'repository refuse writes no receipts directory'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "write-receipt logic failed ($($failures.Count)):"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}
Write-Host 'write-receipt logic passed'
exit 0
