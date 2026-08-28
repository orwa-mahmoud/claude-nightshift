param(
    [string]$Project = [Environment]::CurrentDirectory,
    [string]$Date = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

function Write-NSArchiveReceiptsError {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

try {
    $hostPath = Resolve-NSCanonicalPath $Project
}
catch {
    Write-NSArchiveReceiptsError "archive-receipts: cannot cd to $Project"
    exit 1
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostPath
}
catch {
    Write-NSArchiveReceiptsError 'archive-receipts: invalid .nightshift-link - Nightshift will not guess a workspace'
    exit 2
}

$kind = Get-NSStateKind $workspace
if ($kind -in @('malformed', 'future')) {
    Write-NSArchiveReceiptsError ("archive-receipts: {0}" -f (Get-NSStateRefuseMessage $kind))
    exit 2
}
if ($kind -eq 'absent') {
    Write-NSArchiveReceiptsError "archive-receipts: no .nightshift/ at $workspace"
    exit 2
}

$ns = Join-Path $workspace '.nightshift'
if ([string]::IsNullOrWhiteSpace($Date)) {
    $Date = Get-Date -Format 'yyyy-MM-dd'
}
if ($Date -notmatch '^\d{4}-\d{2}-\d{2}$') {
    Write-NSArchiveReceiptsError 'archive-receipts: -Date must be YYYY-MM-DD'
    exit 1
}

$src = Get-NSReceiptsDir $workspace
$dest = Join-Path $ns "archive/$Date/receipts"
if ((Test-Path -LiteralPath $src) -and (Test-NSReparsePoint $src)) {
    Write-NSArchiveReceiptsError 'archive-receipts: refuse to write through a symlink receipts path'
    exit 2
}
if ((Test-Path -LiteralPath $src) -and -not (Test-Path -LiteralPath $src -PathType Container)) {
    Write-NSArchiveReceiptsError 'archive-receipts: receipts path is not a directory'
    exit 2
}
foreach ($p in @((Join-Path $ns 'archive'), (Join-Path $ns "archive/$Date"), $dest)) {
    if (Test-Path -LiteralPath $p) {
        $item = Get-Item -LiteralPath $p -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-NSArchiveReceiptsError 'archive-receipts: refuse to write through a symlink archive path'
            exit 2
        }
    }
}

$copied = 0
if (Test-Path -LiteralPath $src -PathType Container) {
    $files = @(Get-ChildItem -LiteralPath $src -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            -not $_.Name.StartsWith('.') -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        })
    if ($files.Count -gt 0) {
        $null = New-Item -ItemType Directory -Path $dest -Force
        $destItem = Get-Item -LiteralPath $dest -Force
        if ($destItem.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Write-NSArchiveReceiptsError 'archive-receipts: refuse to write through a symlink archive path'
            exit 2
        }
        foreach ($file in $files) {
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $dest $file.Name) -Force
            $copied++
        }
    }
}

if ($copied -eq 0) {
    exit 0
}
Write-Output $dest
exit 0
