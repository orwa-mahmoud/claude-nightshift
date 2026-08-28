# Portable PowerShell coverage for work-mode discovery skips of reparse children.
# Run on macOS or Windows: pwsh -File tests/windows/work-mode-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $repository 'plugins/nightshift/lib/Nightshift.psm1') -Force -DisableNameChecking
$setup = Join-Path $repository 'plugins/nightshift/runtime/windows/setup.ps1'
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

function Invoke-Setup {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [string[]]$Extra = @()
    )
    $argList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $setup, '-Project', $Project
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

    $unsetNotes = Join-Path $root 'setup-notes'
    $null = New-Item -ItemType Directory -Path (Join-Path $unsetNotes 'research') -Force
    [IO.File]::WriteAllText((Join-Path $unsetNotes 'research/topic.md'), "notes`n")
    $defaultSetup = Invoke-Setup $unsetNotes
    Expect-True ($defaultSetup.ExitCode -ne 0) `
        "default setup on a notes folder exits non-zero (got $($defaultSetup.ExitCode))"
    Expect-True (($defaultSetup.Stderr + $defaultSetup.Stdout) -match 'pass -Mode artifact for a notes folder') `
        "default setup names -Mode artifact (got $($defaultSetup.Stderr) $($defaultSetup.Stdout))"
    Expect-True (-not (Test-Path -LiteralPath (Join-Path $unsetNotes '.nightshift'))) `
        'failed default setup creates no Nightshift directory'

    $artifactNotes = Join-Path $root 'setup-artifact'
    $null = New-Item -ItemType Directory -Path (Join-Path $artifactNotes 'research') -Force
    [IO.File]::WriteAllText((Join-Path $artifactNotes 'research/topic.md'), "notes`n")
    $artifactSetup = Invoke-Setup $artifactNotes @('-Mode', 'artifact')
    Expect-True ($artifactSetup.ExitCode -eq 0) `
        "artifact setup on a notes folder exits 0 (got $($artifactSetup.ExitCode) $($artifactSetup.Stderr))"
    Expect-True ((Get-NSWorkMode $artifactNotes) -eq 'artifact') 'artifact setup persists artifact mode'

    $parentSetup = Invoke-Setup $parent
    Expect-True ($parentSetup.ExitCode -eq 0) `
        "default setup on a parent with a real child exits 0 (got $($parentSetup.ExitCode) $($parentSetup.Stderr))"
    Expect-True ((Get-NSWorkMode $parent) -eq 'repository') 'parent setup persists repository mode'

    $linkRoot = Join-Path $root 'mode-link'
    $linkNs = Join-Path $linkRoot '.nightshift'
    $null = New-Item -ItemType Directory -Path $linkNs -Force
    $plant = Join-Path $linkNs 'mode-plant'
    [IO.File]::WriteAllText($plant, "artifact`n")
    $modeLink = Join-Path $linkNs 'work-mode'
    try {
        $null = New-Item -ItemType SymbolicLink -Path $modeLink -Target $plant -ErrorAction Stop
    }
    catch {
        if ($onWin32) {
            Write-Host 'skip symlink work-mode (cannot create)'
        }
        else {
            throw
        }
    }
    if (Test-Path -LiteralPath $modeLink) {
        $threw = $false
        try {
            $null = Get-NSWorkMode $linkRoot
        }
        catch {
            $threw = $_.Exception.Message -match 'malformed'
        }
        Expect-True $threw 'symlink work-mode is malformed'
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
