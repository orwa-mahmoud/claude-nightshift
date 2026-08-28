param(
    [string]$Project = [Environment]::CurrentDirectory,
    [string]$Item = '',
    [string]$Verify = '',
    [string]$Decision = '',
    [string[]]$Source = @(),
    [string[]]$Output = @()
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

function Write-NSReceiptError {
    param([string]$Message)
    [Console]::Error.WriteLine($Message)
}

try {
    $hostPath = Resolve-NSCanonicalPath $Project
}
catch {
    Write-NSReceiptError "write-receipt: cannot cd to $Project"
    exit 1
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostPath
}
catch {
    Write-NSReceiptError 'write-receipt: invalid .nightshift-link'
    exit 1
}

$ns = Join-Path $workspace '.nightshift'
if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
    Write-NSReceiptError "write-receipt: no .nightshift/ at $workspace"
    exit 1
}

try {
    $mode = Get-NSWorkMode $workspace
}
catch {
    Write-NSReceiptError 'write-receipt: work-mode is malformed'
    exit 3
}
if ($mode -ne 'artifact') {
    Write-NSReceiptError "write-receipt: work-mode is $mode; write a git commit in the work target instead"
    exit 3
}

if ([string]::IsNullOrWhiteSpace($Item)) {
    Write-NSReceiptError 'write-receipt: -Item is required'
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Verify)) {
    Write-NSReceiptError 'write-receipt: -Verify is required'
    exit 1
}
$outputs = @($Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($outputs.Count -eq 0) {
    Write-NSReceiptError 'write-receipt: at least one -Output is required'
    exit 2
}

$homeRoot = ''
if (-not [string]::IsNullOrEmpty($env:USERPROFILE)) {
    try { $homeRoot = Resolve-NSCanonicalPath $env:USERPROFILE } catch { $homeRoot = '' }
}
elseif (-not [string]::IsNullOrEmpty($env:HOME)) {
    try { $homeRoot = Resolve-NSCanonicalPath $env:HOME } catch { $homeRoot = '' }
}

$target = ''
try {
    $resolved = Resolve-NSWorkTarget $workspace
    if (-not [string]::IsNullOrEmpty($resolved)) {
        $target = Resolve-NSCanonicalPath $resolved
    }
}
catch {
    $target = ''
}

function Convert-NSReceiptLine {
    param([AllowEmptyString()][string]$Text)
    $sanitized = Convert-NSSanitizedLine $Text $homeRoot $workspace $target
    if ([string]::IsNullOrEmpty($sanitized)) {
        return '(redacted)'
    }
    return $sanitized
}

$okOutputs = New-Object System.Collections.Generic.List[string]
foreach ($raw in $outputs) {
    if ([IO.Path]::IsPathRooted($raw)) {
        $abs = $raw
    }
    else {
        $abs = Join-Path $hostPath $raw
    }
    try {
        $abs = Resolve-NSCanonicalPath $abs
    }
    catch {
        Write-NSReceiptError "write-receipt: missing output: $raw"
        exit 2
    }
    if ((Test-NSReparsePoint $abs) -or -not (Test-Path -LiteralPath $abs -PathType Leaf)) {
        Write-NSReceiptError "write-receipt: missing output: $raw"
        exit 2
    }
    $itemInfo = Get-Item -LiteralPath $abs -Force
    if ($itemInfo.Length -eq 0) {
        Write-NSReceiptError "write-receipt: empty output: $raw"
        exit 2
    }
    try {
        $hash = Get-NSFileSha256 $abs
    }
    catch {
        Write-NSReceiptError "write-receipt: cannot hash $raw"
        exit 1
    }
    $mtime = [int](([DateTimeOffset]$itemInfo.LastWriteTimeUtc) - [DateTimeOffset]::Parse('1970-01-01T00:00:00Z')).TotalSeconds
    $shown = Convert-NSReceiptLine $abs
    [void]$okOutputs.Add("path: $shown")
    [void]$okOutputs.Add("bytes: $($itemInfo.Length)")
    [void]$okOutputs.Add("sha256: $hash")
    [void]$okOutputs.Add("mtime: $mtime")
}

$dir = Get-NSReceiptsDir $workspace
if ((Test-Path -LiteralPath $dir) -and (Test-NSReparsePoint $dir)) {
    Write-NSReceiptError 'write-receipt: refuse to write through a symlink receipts path'
    exit 2
}
$null = New-Item -ItemType Directory -Path $dir -Force
if (Test-NSReparsePoint $dir) {
    Write-NSReceiptError 'write-receipt: refuse to write through a symlink receipts path'
    exit 2
}
$stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
$slug = Get-NSReceiptSlug $Item
$dest = Join-Path $dir "$stamp-$slug.md"
$n = 1
while (Test-Path -LiteralPath $dest) {
    $dest = Join-Path $dir "$stamp-$slug-$n.md"
    $n++
}

$lines = New-Object System.Collections.Generic.List[string]
[void]$lines.Add('# Nightshift artifact receipt')
[void]$lines.Add('')
[void]$lines.Add(('recorded: {0}' -f [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')))
[void]$lines.Add(('item: {0}' -f (Convert-NSReceiptLine $Item)))
[void]$lines.Add(('verification: {0}' -f (Convert-NSReceiptLine $Verify)))
if (-not [string]::IsNullOrWhiteSpace($Decision)) {
    [void]$lines.Add(('decision: {0}' -f (Convert-NSReceiptLine $Decision)))
}
[void]$lines.Add(('workspace: {0}' -f (Convert-NSReceiptLine $workspace)))
if (-not [string]::IsNullOrEmpty($target)) {
    [void]$lines.Add(('work_target: {0}' -f (Convert-NSReceiptLine $target)))
}
[void]$lines.Add('mode: artifact')
$sources = @($Source | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
if ($sources.Count -gt 0) {
    [void]$lines.Add('')
    [void]$lines.Add('## Sources')
    [void]$lines.Add('')
    foreach ($src in $sources) {
        [void]$lines.Add(('- {0}' -f (Convert-NSReceiptLine $src)))
    }
}
[void]$lines.Add('')
[void]$lines.Add('## Outputs')
[void]$lines.Add('')
foreach ($row in $okOutputs) {
    [void]$lines.Add($row)
}

$null = Write-NSAtomicLines -Path $dest -Lines @($lines)
Write-Output $dest
exit 0
