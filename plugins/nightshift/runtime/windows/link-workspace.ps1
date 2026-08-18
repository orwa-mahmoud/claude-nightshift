param(
    [Parameter(Mandatory = $true)][string]$HostRoot,
    [Parameter(Mandatory = $true)][string]$Workspace
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force

$hostPath = Resolve-NSCanonicalPath $HostRoot
$workspacePath = Resolve-NSCanonicalPath $Workspace
if (-not (Test-Path -LiteralPath (Join-Path $workspacePath '.nightshift') -PathType Container)) {
    throw 'workspace does not contain .nightshift'
}

$link = Join-Path $hostPath '.nightshift-link'
if (Test-NSReparsePoint $link) {
    throw 'refusing to replace a reparse-point .nightshift-link'
}
Write-NSAtomicLines -Path $link -Lines @($workspacePath)

$gitDirectory = Invoke-NSGit $hostPath @('rev-parse', '--git-dir')
if (-not [string]::IsNullOrWhiteSpace($gitDirectory)) {
    if (-not [IO.Path]::IsPathRooted($gitDirectory)) {
        $gitDirectory = Join-Path $hostPath $gitDirectory
    }
    $info = Join-Path $gitDirectory 'info'
    $null = New-Item -ItemType Directory -Path $info -Force
    $exclude = Join-Path $info 'exclude'
    $lines = if (Test-Path -LiteralPath $exclude -PathType Leaf) {
        @([IO.File]::ReadAllLines($exclude))
    }
    else {
        @()
    }
    if ($lines -notcontains '.nightshift-link') {
        Write-NSAtomicLines -Path $exclude -Lines @($lines + '.nightshift-link')
    }
}

"linked $hostPath -> $workspacePath"
