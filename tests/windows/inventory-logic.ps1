# Portable PowerShell coverage for inventory: the five fixture trees, the three tool states,
# and the canonical JSON the bash engine is held to.
# Run on macOS or Windows: pwsh -File tests/windows/inventory-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/inventory.ps1'
$fixtures = Join-Path $repository 'tests/fixtures/inventory'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function Expect-Equal {
    param([AllowNull()][object]$Expected, [AllowNull()][object]$Actual, [string]$Message)
    if ([string]$Expected -cne [string]$Actual) {
        $detail = "$Message (expected '$Expected', got '$Actual')"
        $failures.Add($detail)
        Write-Host "FAIL: $detail"
    }
}

function Invoke-Inventory {
    param([string[]]$Extra = @())
    $argList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $helper
    ) + $Extra
    $stdout = [Collections.Generic.List[string]]::new()
    $stderr = [Collections.Generic.List[string]]::new()
    $previousEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        foreach ($item in @(& $hostExecutable @argList 2>&1)) {
            if ($item -is [Management.Automation.ErrorRecord]) { $stderr.Add([string]$item) }
            else { $stdout.Add([string]$item) }
        }
    }
    finally {
        $ErrorActionPreference = $previousEap
    }
    $code = $LASTEXITCODE
    if ($null -eq $code) { $code = 1 }
    return [pscustomobject]@{
        ExitCode = [int]$code
        Lines = $stdout.ToArray()
        Text = ($stdout -join "`n")
        Stderr = ($stderr -join "`n")
    }
}

# The fixture carries `gitignore` because this repository cannot hold a live ignore file
# inside a fixture; the copy gets the real name.
function Copy-Fixture {
    param([string]$Name, [string]$Into, [switch]$AsRepository)
    $destination = Join-Path $Into $Name
    Copy-Item -LiteralPath (Join-Path $fixtures $Name) -Destination $destination -Recurse -Force
    $ignore = Join-Path $destination 'gitignore'
    if (Test-Path -LiteralPath $ignore -PathType Leaf) {
        Move-Item -LiteralPath $ignore -Destination (Join-Path $destination '.gitignore')
    }
    if ($AsRepository) {
        $null = & git -C $destination init --quiet
        $null = & git -C $destination config user.email 'dev@example.com'
        $null = & git -C $destination config user.name 'tester'
    }
    return $destination
}

function Get-Row {
    param($Result, [string]$Label)
    foreach ($line in $Result.Lines) {
        if ($line.StartsWith('| ' + $Label + ' | ', [StringComparison]::Ordinal)) {
            $parts = $line.Split('|')
            return $parts[2].Trim()
        }
    }
    return ''
}

$scratch = Join-Path ([IO.Path]::GetTempPath()) ('nightshift-inventory-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $scratch
try {
    # A single npm repository: manager, lockfile, scripts and configs, and .gitignore honoured.
    $npm = Copy-Fixture 'npm-single' $scratch -AsRepository
    $single = Invoke-Inventory @('-Project', $npm)
    Expect-Equal 0 $single.ExitCode "npm-single exits 0: $($single.Stderr)"
    Expect-True ($single.Lines[0] -cmatch '^inventory: 1 package in .+ \(git\)$') `
        'a single npm repository reports one package under git'
    Expect-Equal 'ci: .github/workflows/ci.yml' $single.Lines[1] 'the workflow file is the CI line'
    Expect-True ($single.Lines -ccontains '## . (node)') 'the root package is a node package'
    Expect-Equal 'npm' (Get-Row $single 'manager') 'the lockfile names the manager'
    Expect-Equal 'package-lock.json' (Get-Row $single 'lockfile') 'the lockfile is reported'
    Expect-Equal 'no' (Get-Row $single 'workspaces') 'a single package declares no workspaces'
    Expect-Equal 'test' (Get-Row $single 'script test') 'the test script is declared'
    Expect-Equal 'fmt' (Get-Row $single 'script format') 'fmt satisfies the format role'
    Expect-Equal '-' (Get-Row $single 'script typecheck') 'no typecheck script is declared'
    Expect-Equal '.eslintrc.json' (Get-Row $single 'config eslint') 'the eslint config is reported'
    Expect-Equal 'tsconfig.json' (Get-Row $single 'config tsconfig') 'the tsconfig is reported'
    Expect-True ($single.Text -cnotmatch 'ignored') 'a gitignored package stays out of the inventory'

    # A monorepo: every workspace package, with the root lockfile above it.
    $mono = Copy-Fixture 'pnpm-monorepo' $scratch
    $monoRun = Invoke-Inventory @('-Project', $mono, '-Json')
    Expect-Equal 0 $monoRun.ExitCode "pnpm-monorepo exits 0: $($monoRun.Stderr)"
    $report = ConvertFrom-Json $monoRun.Text
    Expect-Equal 3 @($report.packages).Count 'a monorepo reports the root and both packages'
    Expect-Equal '.' $report.packages[0].path 'the root sorts first'
    Expect-Equal 'yes' $report.packages[0].workspaces 'the root declares workspaces'
    Expect-Equal 'packages/api' $report.packages[1].path 'the api package is second'
    Expect-Equal 'pnpm-lock.yaml' $report.packages[1].lockfile 'a package inherits the root lockfile'
    Expect-Equal 'pnpm' $report.packages[1].manager 'the inherited lockfile names the manager'
    Expect-Equal 'type-check' $report.packages[2].scripts.typecheck 'type-check satisfies the role'
    Expect-True ($monoRun.Text -cnotmatch '"path":"dist"') 'a build directory is not a package'

    # A bin under node_modules/.bin reaches the package and its children.
    $null = New-Item -ItemType Directory -Path (Join-Path $mono 'node_modules/.bin') -Force
    [IO.File]::WriteAllText((Join-Path $mono 'node_modules/.bin/tsc'), "#!/bin/sh`nexit 0`n")
    $null = New-Item -ItemType Directory -Path (Join-Path $mono 'packages/api/node_modules/.bin') -Force
    [IO.File]::WriteAllText((Join-Path $mono 'packages/api/node_modules/.bin/biome'), "#!/bin/sh`nexit 0`n")
    $withBins = ConvertFrom-Json (Invoke-Inventory @('-Project', $mono, '-Json')).Text
    Expect-Equal 'runnable' $withBins.packages[0].tools.tsc 'a root bin is runnable at the root'
    Expect-Equal 'runnable' $withBins.packages[1].tools.tsc 'a root bin reaches a child package'
    Expect-Equal 'runnable' $withBins.packages[1].tools.biome 'a package bin is runnable there'
    Expect-Equal 'absent' $withBins.packages[2].tools.biome 'a sibling package does not borrow it'

    # A Python project reports the sections its manifests open.
    $python = Copy-Fixture 'python-project' $scratch
    $pythonRun = ConvertFrom-Json (Invoke-Inventory @('-Project', $python, '-Json')).Text
    Expect-Equal 'python' $pythonRun.packages[0].kind 'a pyproject tree is a python package'
    Expect-Equal 'pip' $pythonRun.packages[0].manager 'no lockfile leaves pip as the manager'
    Expect-Equal 'pyproject.toml' $pythonRun.packages[0].configs.ruff 'a pyproject section is a config'
    Expect-Equal 'pyproject.toml' $pythonRun.packages[0].configs.pytest 'pytest options are a config'
    Expect-Equal 'declared' $pythonRun.packages[0].tools.mypy 'a named tool with no bin is declared'

    # A Go module reports its checksum file and linter config.
    $go = Copy-Fixture 'go-module' $scratch
    $goRun = ConvertFrom-Json (Invoke-Inventory @('-Project', $go, '-Json')).Text
    Expect-Equal 'go' $goRun.packages[0].kind 'a go.mod tree is a go package'
    Expect-Equal 'go.sum' $goRun.packages[0].lockfile 'go.sum is the lockfile'
    Expect-Equal '.golangci.yml' $goRun.packages[0].configs.golangci 'the linter config is reported'
    Expect-Equal 'declared' $goRun.packages[0].tools.'golangci-lint' 'the linter is declared'
    Expect-Equal 'absent' $goRun.packages[0].tools.eslint 'an unrelated tool is absent'

    # Every state is one of the three words, and nothing else.
    $stateHolder = Join-Path $scratch 'states'
    $null = New-Item -ItemType Directory -Path $stateHolder
    foreach ($name in @('npm-single', 'pnpm-monorepo', 'python-project', 'go-module')) {
        $path = Copy-Fixture $name $stateHolder
        $parsed = ConvertFrom-Json (Invoke-Inventory @('-Project', $path, '-Json')).Text
        foreach ($package in @($parsed.packages)) {
            foreach ($property in $package.tools.PSObject.Properties) {
                Expect-True (@('declared', 'runnable', 'absent') -ccontains [string]$property.Value) `
                    "$name/$($package.path) reports $($property.Name) as $($property.Value)"
            }
        }
    }

    # A folder with no manifest is an inventory of nothing, not a failure.
    $empty = Copy-Fixture 'empty' $scratch
    $emptyRun = Invoke-Inventory @('-Project', $empty)
    Expect-Equal 0 $emptyRun.ExitCode 'an empty folder exits 0'
    Expect-True ($emptyRun.Lines[0] -cmatch '^inventory: 0 packages in .+ \(none\)$') `
        'an empty folder reports zero packages'
    Expect-Equal 'ci: none' $emptyRun.Lines[1] 'an empty folder has no CI files'

    # An unreadable target is unavailable, on one line.
    $absent = Invoke-Inventory @('-Project', (Join-Path $scratch 'no-such-tree'))
    Expect-Equal 3 $absent.ExitCode 'a missing target exits 3'
    Expect-Equal 'unavailable inventory: the work target is not a readable directory' `
        $absent.Text 'a missing target names the one reason'

    # A manifest that will not parse is unavailable, never a blank package.
    $brokenHolder = Join-Path $scratch 'broken-holder'
    $null = New-Item -ItemType Directory -Path $brokenHolder
    $broken = Copy-Fixture 'npm-single' $brokenHolder
    [IO.File]::WriteAllText((Join-Path $broken 'package.json'), "{ `"name`": `"single`",`n")
    $brokenRun = Invoke-Inventory @('-Project', $broken)
    Expect-Equal 3 $brokenRun.ExitCode 'an unparsable manifest exits 3'
    Expect-Equal 1 $brokenRun.Lines.Count 'an unparsable manifest prints one line'
    Expect-True ($brokenRun.Lines[0].StartsWith('unavailable inventory: ', [StringComparison]::Ordinal)) `
        'an unparsable manifest says why'

    # Canonical JSON: sorted keys everywhere, one line, version 1.
    $canonical = Invoke-Inventory @('-Project', $mono, '-Json')
    Expect-Equal 1 $canonical.Lines.Count 'the JSON report is one line'
    $parsedCanonical = ConvertFrom-Json $canonical.Text
    Expect-Equal 1 $parsedCanonical.version 'the report carries version 1'
    foreach ($node in @($parsedCanonical, $parsedCanonical.packages[0],
            $parsedCanonical.packages[0].configs, $parsedCanonical.packages[0].scripts,
            $parsedCanonical.packages[0].tools)) {
        $names = [string[]]@($node.PSObject.Properties | ForEach-Object { $_.Name })
        $sorted = [string[]]$names.Clone()
        [Array]::Sort($sorted, [StringComparer]::Ordinal)
        Expect-Equal ($sorted -join ',') ($names -join ',') 'the report sorts its keys'
    }

    # Read-only: the tree is byte-identical after a run, and no cache appears.
    $before = @(Get-ChildItem -LiteralPath $go -Recurse -Force | ForEach-Object { $_.FullName } |
            Sort-Object)
    $null = Invoke-Inventory @('-Project', $go)
    $null = Invoke-Inventory @('-Project', $go, '-Json')
    $after = @(Get-ChildItem -LiteralPath $go -Recurse -Force | ForEach-Object { $_.FullName } |
            Sort-Object)
    Expect-Equal ($before -join ';') ($after -join ';') 'the inventory writes nothing of its own'

    # The same tree always yields the same bytes.
    $first = Invoke-Inventory @('-Project', $python, '-Json')
    $second = Invoke-Inventory @('-Project', $python, '-Json')
    Expect-Equal $first.Text $second.Text 'two runs over one tree agree'
}
finally {
    Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "inventory logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'inventory logic passed'
exit 0
