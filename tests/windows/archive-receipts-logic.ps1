# Portable PowerShell coverage for artifact-mode archive-receipts.
# Run on macOS or Windows: pwsh -File tests/windows/archive-receipts-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/archive-receipts.ps1'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'
$onWin32 = [Environment]::OSVersion.Platform -eq 'Win32NT'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function Invoke-ArchiveReceipts {
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

function New-ReparseDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Target
    )
    if ($onWin32) {
        $null = New-Item -ItemType Junction -Path $Path -Target $Target
    }
    else {
        $null = New-Item -ItemType SymbolicLink -Path $Path -Target $Target
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-archive-receipts-logic-" + [guid]::NewGuid().ToString('N'))
try {
    $artifact = Join-Path $root 'notes'
    $ns = Join-Path $artifact '.nightshift'
    $recv = Join-Path $ns 'receipts'
    $null = New-Item -ItemType Directory -Path $recv -Force
    [IO.File]::WriteAllText((Join-Path $ns 'work-mode'), "artifact`n")
    [IO.File]::WriteAllText((Join-Path $recv '20260101T000000Z-one.md'), "one`n")
    [IO.File]::WriteAllText((Join-Path $recv '20260101T000001Z-two.md'), "two`n")
    [IO.File]::WriteAllText((Join-Path $recv '.not-a-receipt'), "dot`n")
    $nestedRecv = Join-Path $recv 'nested'
    $null = New-Item -ItemType Directory -Path $nestedRecv -Force
    [IO.File]::WriteAllText((Join-Path $nestedRecv '20260101T000000Z-nested.md'), "nested`n")

    $ok = Invoke-ArchiveReceipts $artifact @('-Date', '2026-08-28')
    Expect-True ($ok.ExitCode -eq 0) "copy exits 0 (got $($ok.ExitCode) $($ok.Stderr))"
    $dest = $ok.Stdout.Trim()
    Expect-True ($dest -match [regex]::Escape((Join-Path $ns 'archive/2026-08-28/receipts'))) `
        'prints the dated archive receipts path'
    Expect-True (Test-Path -LiteralPath (Join-Path $recv '20260101T000000Z-one.md') -PathType Leaf) `
        'leaves the first live receipt'
    Expect-True (Test-Path -LiteralPath (Join-Path $recv '20260101T000001Z-two.md') -PathType Leaf) `
        'leaves the second live receipt'
    Expect-True (Test-Path -LiteralPath (Join-Path $dest '20260101T000000Z-one.md') -PathType Leaf) `
        'copies the first receipt'
    Expect-True (Test-Path -LiteralPath (Join-Path $dest '20260101T000001Z-two.md') -PathType Leaf) `
        'copies the second receipt'
    Expect-True (-not (Test-Path -LiteralPath (Join-Path $dest '.not-a-receipt'))) `
        'does not copy a hidden file'
    Expect-True (-not (Test-Path -LiteralPath (Join-Path $dest '20260101T000000Z-nested.md'))) `
        'does not copy a nested receipt'

    $symlinkNotes = Join-Path $root 'symlink-receipts'
    $symlinkNs = Join-Path $symlinkNotes '.nightshift'
    $symlinkRecv = Join-Path $symlinkNs 'receipts'
    $null = New-Item -ItemType Directory -Path $symlinkRecv -Force
    [IO.File]::WriteAllText((Join-Path $symlinkNs 'work-mode'), "artifact`n")
    $realReceipt = Join-Path $symlinkRecv '20260101T000000Z-real.md'
    [IO.File]::WriteAllText($realReceipt, "real`n")
    $receiptLink = Join-Path $symlinkRecv '20260101T000000Z-link.md'
    $fileLinkCreated = $true
    try {
        $null = New-Item -ItemType SymbolicLink -Path $receiptLink -Target $realReceipt -ErrorAction Stop
    }
    catch {
        if ($onWin32) {
            $fileLinkCreated = $false
        }
        else {
            throw
        }
    }
    if ($fileLinkCreated) {
        $skipLink = Invoke-ArchiveReceipts $symlinkNotes @('-Date', '2026-08-28')
        Expect-True ($skipLink.ExitCode -eq 0) "symlink receipt copy exits 0 (got $($skipLink.ExitCode) $($skipLink.Stderr))"
        $skipDest = $skipLink.Stdout.Trim()
        Expect-True (Test-Path -LiteralPath (Join-Path $skipDest '20260101T000000Z-real.md') -PathType Leaf) `
            'copies the regular receipt beside a symlink'
        Expect-True (-not (Test-Path -LiteralPath (Join-Path $skipDest '20260101T000000Z-link.md'))) `
            'does not copy a symlink receipt'
        Expect-True (Test-Path -LiteralPath $receiptLink) 'leaves the live symlink receipt'
    }

    $empty = Join-Path $root 'empty-notes'
    $emptyNs = Join-Path $empty '.nightshift'
    $null = New-Item -ItemType Directory -Path $emptyNs -Force
    [IO.File]::WriteAllText((Join-Path $emptyNs 'work-mode'), "artifact`n")
    $none = Invoke-ArchiveReceipts $empty @('-Date', '2026-08-28')
    Expect-True ($none.ExitCode -eq 0) "empty receipts exit 0 (got $($none.ExitCode) $($none.Stderr))"
    Expect-True ([string]::IsNullOrWhiteSpace($none.Stdout)) 'empty receipts print nothing'
    Expect-True (-not (Test-Path -LiteralPath (Join-Path $emptyNs 'archive/2026-08-28/receipts'))) `
        'empty receipts create no archive folder'

    $bad = Invoke-ArchiveReceipts $artifact @('-Date', 'not-a-date')
    Expect-True ($bad.ExitCode -eq 1) "malformed date exits 1 (got $($bad.ExitCode))"

    $missing = Invoke-ArchiveReceipts (Join-Path $root 'no-such-project')
    Expect-True ($missing.ExitCode -eq 1) "missing project exits 1 (got $($missing.ExitCode))"

    $linked = Join-Path $root 'link-notes'
    $linkedNs = Join-Path $linked '.nightshift'
    $linkedRecv = Join-Path $linkedNs 'receipts'
    $outside = Join-Path $root 'outside'
    $null = New-Item -ItemType Directory -Path $linkedRecv, $outside -Force
    [IO.File]::WriteAllText((Join-Path $linkedNs 'work-mode'), "artifact`n")
    [IO.File]::WriteAllText((Join-Path $linkedRecv '20260101T000000Z-real.md'), "real`n")
    New-ReparseDirectory (Join-Path $linkedNs 'archive') $outside
    $refused = Invoke-ArchiveReceipts $linked @('-Date', '2026-08-28')
    Expect-True ($refused.ExitCode -eq 2) "symlink archive path exits 2 (got $($refused.ExitCode) $($refused.Stderr))"
    Expect-True (-not (Test-Path -LiteralPath (Join-Path $outside 'receipts/20260101T000000Z-real.md'))) `
        'does not write through a reparse archive path'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "archive-receipts-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) {
        Write-Host " - $failure"
    }
    exit 1
}
Write-Host 'archive-receipts logic passed'
exit 0
