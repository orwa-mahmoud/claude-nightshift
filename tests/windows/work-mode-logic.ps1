# Portable PowerShell coverage for work-mode discovery skips of reparse children.
# Run on macOS or Windows: pwsh -File tests/windows/work-mode-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $repository 'plugins/nightshift/lib/Nightshift.psm1') -Force -DisableNameChecking
$failures = New-Object 'System.Collections.Generic.List[string]'
$onWin32 = [Environment]::OSVersion.Platform -eq 'Win32NT'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
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

function New-GitRepo {
    param([Parameter(Mandatory = $true)][string]$Path)
    $null = New-Item -ItemType Directory -Path $Path -Force
    & git -C $Path init --quiet
    if ($LASTEXITCODE -ne 0) {
        throw "git init failed in $Path"
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-work-mode-logic-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root -Force
try {
    $notes = Join-Path $root 'notes'
    $null = New-Item -ItemType Directory -Path (Join-Path $notes 'research') -Force
    [IO.File]::WriteAllText((Join-Path $notes 'research/topic.md'), "notes`n")
    $planted = Join-Path $root 'planted'
    New-GitRepo $planted

    $linkCreated = $true
    try {
        New-ReparseDirectory (Join-Path $notes 'decoy') $planted
    }
    catch {
        if ($onWin32) {
            $linkCreated = $false
        }
        else {
            throw
        }
    }

    if ($linkCreated) {
        $mode = Get-NSProposedWorkMode $notes
        Expect-True ($mode -eq 'artifact') "symlink child proposes artifact (got $mode)"

        $threw = $false
        try {
            $null = Resolve-NSWorkTarget $notes
        }
        catch {
            $threw = $true
            Expect-True ([string]$_.Exception.Message -match 'no Git work target found') `
                "unstored resolve names no Git work target (got $($_.Exception.Message))"
        }
        Expect-True $threw 'unstored resolve throws for a symlink-only child'
    }

    $parent = Join-Path $root 'parent'
    $null = New-Item -ItemType Directory -Path $parent -Force
    New-GitRepo (Join-Path $parent 'repo')
    $realMode = Get-NSProposedWorkMode $parent
    Expect-True ($realMode -eq 'repository') "real child proposes repository (got $realMode)"
    $realTarget = Resolve-NSWorkTarget $parent
    $expected = Invoke-NSGit (Join-Path $parent 'repo') @('rev-parse', '--show-toplevel')
    Expect-True ($realTarget -eq (Resolve-NSCanonicalPath $expected)) `
        "unstored resolve finds the real child (got $realTarget)"

    if ($linkCreated) {
        $beside = Join-Path $root 'beside'
        $null = New-Item -ItemType Directory -Path $beside -Force
        New-GitRepo (Join-Path $beside 'repo')
        $other = Join-Path $root 'other'
        New-GitRepo $other
        New-ReparseDirectory (Join-Path $beside 'decoy') $other
        $besideMode = Get-NSProposedWorkMode $beside
        Expect-True ($besideMode -eq 'repository') "real child beside decoy proposes repository (got $besideMode)"
        $besideTarget = Resolve-NSWorkTarget $beside
        $besideExpected = Invoke-NSGit (Join-Path $beside 'repo') @('rev-parse', '--show-toplevel')
        Expect-True ($besideTarget -eq (Resolve-NSCanonicalPath $besideExpected)) `
            "unstored resolve ignores a planted sibling (got $besideTarget)"
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "work-mode-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'work-mode-logic passed'
exit 0
