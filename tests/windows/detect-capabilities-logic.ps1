# Portable PowerShell coverage for the Windows native capability detector.
# Run on macOS or Windows: pwsh -File tests/windows/detect-capabilities-logic.ps1
#
# Behavioural spec: plugins/nightshift/runtime/detect-capabilities.py. The native
# detector at plugins/nightshift/runtime/windows/detect-capabilities.ps1 must be
# byte-identical to that spec for the same arguments/PATH/fixture. This suite
# builds fixtures, shells out to the detector like a real caller would, and
# checks exit codes, JSON shape, exact byte formatting, and python3 parity.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$plugin = Join-Path $repository 'plugins/nightshift'
$detectorScript = Join-Path $plugin 'runtime/windows/detect-capabilities.ps1'
$pythonScript = Join-Path $plugin 'runtime/detect-capabilities.py'
$jsRepoSource = Join-Path $repository 'evals/fixtures/v1/repo-js'
$hostExecutable = (Get-Process -Id $PID).Path
$onWin32 = [Environment]::OSVersion.Platform -eq 'Win32NT'
$failures = New-Object 'System.Collections.Generic.List[string]'

# The companion native detector is being built in a parallel lane and is not
# expected to exist yet in this worktree. Fail fast, precisely, and quietly:
# nothing else in this file should run or print until it lands.
if (-not (Test-Path -LiteralPath $detectorScript -PathType Leaf)) {
    [Console]::Error.WriteLine('detector script not found')
    exit 1
}

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function New-FakeTool {
    param(
        [Parameter(Mandatory = $true)][string]$Dir,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$VersionText,
        [int]$ExitCode = 0
    )
    $null = New-Item -ItemType Directory -Path $Dir -Force
    if ($onWin32) {
        $path = Join-Path $Dir ($Name + '.cmd')
        $body = "@echo off`r`necho $VersionText`r`nexit /b $ExitCode`r`n"
        [IO.File]::WriteAllText($path, $body)
    }
    else {
        $path = Join-Path $Dir $Name
        $body = "#!/bin/sh`necho '$VersionText'`nexit $ExitCode`n"
        [IO.File]::WriteAllText($path, $body)
        & chmod +x $path
    }
    return $path
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

function Get-NSTreeStamp {
    # Recursive file-hash snapshot that never descends into reparse points
    # (symlinks/junctions), mirroring what the detector itself must skip.
    param([Parameter(Mandatory = $true)][string]$Path)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $stack = New-Object 'System.Collections.Generic.Stack[string]'
    $stack.Push($Path)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        $entries = Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue
        foreach ($entry in $entries) {
            $isReparse = [bool]($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)
            if ($entry.PSIsContainer) {
                if (-not $isReparse) {
                    $stack.Push($entry.FullName)
                }
            }
            elseif (-not $isReparse) {
                $rel = $entry.FullName.Substring($Path.Length).TrimStart('\', '/')
                $hash = (Get-FileHash -LiteralPath $entry.FullName -Algorithm SHA256).Hash
                $null = $lines.Add("$hash $rel")
            }
        }
    }
    return (($lines | Sort-Object) -join "`n")
}

function Invoke-ProcessBytes {
    # Captures a child process's stdout/stderr as raw bytes via .NET Process,
    # never through PowerShell's native-command pipeline (which splits output
    # into lines and discards the exact newline/encoding evidence we need to
    # verify LF-only, single-trailing-newline, ASCII-only output).
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$PathOverride
    )
    $psi = [Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $FileName
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    foreach ($a in $Arguments) {
        $null = $psi.ArgumentList.Add($a)
    }
    if ($PSBoundParameters.ContainsKey('PathOverride')) {
        foreach ($k in @($psi.EnvironmentVariables.Keys)) {
            if ($k -ieq 'PATH') {
                $null = $psi.EnvironmentVariables.Remove($k)
            }
        }
        $psi.EnvironmentVariables.Add('PATH', $PathOverride)
    }
    $proc = [Diagnostics.Process]::new()
    $proc.StartInfo = $psi
    $null = $proc.Start()
    $stdoutStream = New-Object IO.MemoryStream
    $stderrStream = New-Object IO.MemoryStream
    $outTask = $proc.StandardOutput.BaseStream.CopyToAsync($stdoutStream)
    $errTask = $proc.StandardError.BaseStream.CopyToAsync($stderrStream)
    $proc.WaitForExit()
    $null = $outTask.GetAwaiter().GetResult()
    $null = $errTask.GetAwaiter().GetResult()
    return [pscustomobject]@{
        ExitCode = $proc.ExitCode
        StdoutBytes = $stdoutStream.ToArray()
        StderrText = [Text.Encoding]::UTF8.GetString($stderrStream.ToArray())
    }
}

function Invoke-Detector {
    param(
        [string]$ProjectPath,
        [string]$HostName = 'claude',
        [switch]$Normalize,
        [string]$PathOverride,
        [string[]]$RawArguments
    )
    if ($PSBoundParameters.ContainsKey('RawArguments')) {
        $detectorArgs = $RawArguments
    }
    else {
        if ([string]::IsNullOrEmpty($ProjectPath)) {
            throw 'Invoke-Detector requires -ProjectPath or -RawArguments'
        }
        $detectorArgs = @('-Project', $ProjectPath, '-HostName', $HostName)
        if ($Normalize) {
            $detectorArgs += '-Normalize'
        }
    }
    $full = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $detectorScript) + $detectorArgs
    if ($PSBoundParameters.ContainsKey('PathOverride')) {
        return Invoke-ProcessBytes -FileName $hostExecutable -Arguments $full -PathOverride $PathOverride
    }
    return Invoke-ProcessBytes -FileName $hostExecutable -Arguments $full
}

function Invoke-PythonReference {
    param(
        [Parameter(Mandatory = $true)][string]$PythonPath,
        [Parameter(Mandatory = $true)][string]$ProjectPath,
        [string]$HostName = 'claude',
        [switch]$Normalize,
        [string]$PathOverride
    )
    $pyArgs = @($pythonScript, '--project', $ProjectPath, '--host', $HostName)
    if ($Normalize) {
        $pyArgs += '--normalize'
    }
    if ($PSBoundParameters.ContainsKey('PathOverride')) {
        return Invoke-ProcessBytes -FileName $PythonPath -Arguments $pyArgs -PathOverride $PathOverride
    }
    return Invoke-ProcessBytes -FileName $PythonPath -Arguments $pyArgs
}

function Get-NSTopLevelKeys {
    # The serializer indents 2 spaces per level, so a line with exactly two
    # leading spaces before the opening quote is a top-level key.
    param([byte[]]$Bytes)
    $text = [Text.Encoding]::UTF8.GetString($Bytes)
    $keys = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in ($text -split "`n")) {
        if ($line -match '^  "([^"]+)":') {
            $null = $keys.Add($Matches[1])
        }
    }
    return $keys
}

function Test-NSNoCarriageReturn {
    param([byte[]]$Bytes)
    foreach ($b in $Bytes) {
        if ($b -eq 13) {
            return $false
        }
    }
    return $true
}

function Test-NSSingleTrailingNewline {
    param([byte[]]$Bytes)
    if ($Bytes.Length -eq 0) {
        return $false
    }
    if ($Bytes[$Bytes.Length - 1] -ne 10) {
        return $false
    }
    if ($Bytes.Length -ge 2 -and $Bytes[$Bytes.Length - 2] -eq 10) {
        return $false
    }
    return $true
}

function Test-NSAsciiOnly {
    param([byte[]]$Bytes)
    foreach ($b in $Bytes) {
        if ($b -ge 128) {
            return $false
        }
    }
    return $true
}

function Test-NSBytesEqual {
    param([byte[]]$Left, [byte[]]$Right)
    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($i = 0; $i -lt $Left.Length; $i++) {
        if ($Left[$i] -ne $Right[$i]) {
            return $false
        }
    }
    return $true
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-detect-capabilities-logic-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root -Force
$pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue
try {
    $emptyBin = Join-Path $root 'bin/empty'
    $null = New-Item -ItemType Directory -Path $emptyBin -Force
    $nodeBin = Join-Path $root 'bin/node-only'
    $null = New-FakeTool -Dir $nodeBin -Name 'node' -VersionText 'v20.0.0' -ExitCode 0
    $cargoBin = Join-Path $root 'bin/cargo-broken'
    $null = New-FakeTool -Dir $cargoBin -Name 'cargo' -VersionText 'cargo 1.70.0' -ExitCode 7

    # --- 1. JS repo fixture: general format, key order, -Normalize, python3 parity ---
    $jsRepo = Join-Path $root 'js-repo'
    Copy-Item -LiteralPath $jsRepoSource -Destination $jsRepo -Recurse -Force

    $jsBefore = Get-NSTreeStamp $jsRepo
    $jsRun = Invoke-Detector -ProjectPath $jsRepo -PathOverride $nodeBin
    $jsAfter = Get-NSTreeStamp $jsRepo
    Expect-True ($jsRun.ExitCode -eq 0) "js-repo detector exits 0 (got $($jsRun.ExitCode) $($jsRun.StderrText))"
    Expect-True (Test-NSNoCarriageReturn $jsRun.StdoutBytes) 'js-repo output has no CR bytes (LF only)'
    Expect-True (Test-NSSingleTrailingNewline $jsRun.StdoutBytes) 'js-repo output ends with exactly one LF'
    Expect-True (Test-NSAsciiOnly $jsRun.StdoutBytes) 'js-repo output contains no non-ASCII bytes'
    Expect-True ($jsAfter -eq $jsBefore) 'detector wrote nothing into the js-repo fixture'

    $jsText = [Text.Encoding]::UTF8.GetString($jsRun.StdoutBytes)
    $jsDoc = $null
    try {
        $jsDoc = $jsText | ConvertFrom-Json
    }
    catch {
        $jsDoc = $null
    }
    Expect-True ($null -ne $jsDoc) 'js-repo output parses as valid JSON'

    $expectedKeys = @('capabilities', 'contracts', 'host', 'provisioningDefault', 'schemaVersion', 'topology', 'workMode', 'workTarget')
    $actualKeys = @(Get-NSTopLevelKeys $jsRun.StdoutBytes)
    Expect-True (($actualKeys -join ',') -eq ($expectedKeys -join ',')) `
        "top-level keys appear sorted in the raw text (got $($actualKeys -join ','))"
    Expect-True ($jsText -match '(?m)^  "schemaVersion":') 'a top-level key is indented by exactly 2 spaces'
    Expect-True ($jsText -match '(?m)^    "[a-zA-Z-]+": ') 'a second-level key is indented by exactly 4 spaces'

    $jsNorm = Invoke-Detector -ProjectPath $jsRepo -PathOverride $nodeBin -Normalize
    Expect-True ($jsNorm.ExitCode -eq 0) "js-repo -Normalize exits 0 (got $($jsNorm.ExitCode) $($jsNorm.StderrText))"
    $jsNormKeys = @(Get-NSTopLevelKeys $jsNorm.StdoutBytes)
    Expect-True (-not ($jsNormKeys -contains 'host')) '-Normalize drops host from the top-level keys'
    Expect-True ($jsNormKeys -contains 'workMode') '-Normalize keeps the remaining top-level keys'

    if ($null -ne $pythonCommand) {
        $pyRun = Invoke-PythonReference -PythonPath $pythonCommand.Source -ProjectPath $jsRepo -PathOverride $nodeBin
        Expect-True ($pyRun.ExitCode -eq 0) "python3 reference exits 0 (got $($pyRun.ExitCode) $($pyRun.StderrText))"
        Expect-True (Test-NSBytesEqual $pyRun.StdoutBytes $jsRun.StdoutBytes) `
            'the PowerShell detector is byte-identical to the python3 reference on the same fixture and PATH'
    }
    else {
        Write-Host 'skip: python3 not found on PATH; parity leg not run'
    }

    # --- 2. Artifact mode fixture ---
    $artifactRoot = Join-Path $root 'artifact-notes'
    $null = New-Item -ItemType Directory -Path $artifactRoot -Force
    [IO.File]::WriteAllText((Join-Path $artifactRoot 'notes.md'), "# notes`n")
    $artifactNs = Join-Path $artifactRoot '.nightshift'
    $null = New-Item -ItemType Directory -Path $artifactNs -Force
    [IO.File]::WriteAllText((Join-Path $artifactNs 'work-mode'), "artifact`n")
    $artifactRun = Invoke-Detector -ProjectPath $artifactRoot -PathOverride $emptyBin
    Expect-True ($artifactRun.ExitCode -eq 0) "artifact-mode detector exits 0 (got $($artifactRun.ExitCode) $($artifactRun.StderrText))"
    $artifactDoc = [Text.Encoding]::UTF8.GetString($artifactRun.StdoutBytes) | ConvertFrom-Json
    Expect-True ($artifactDoc.capabilities.'local-markdown'.status -eq 'available-and-verified') `
        "artifact mode verifies local-markdown (got $($artifactDoc.capabilities.'local-markdown'.status))"
    Expect-True ($artifactDoc.capabilities.test.status -eq 'unavailable') `
        "artifact mode marks test unavailable (got $($artifactDoc.capabilities.test.status))"
    Expect-True ([string]$artifactDoc.capabilities.test.reason -match 'artifact mode') `
        "artifact mode's unavailable reason names artifact mode (got $($artifactDoc.capabilities.test.reason))"
    Expect-True ($artifactDoc.topology.monorepo -eq $false) 'artifact mode topology is not a monorepo'
    Expect-True (@($artifactDoc.topology.stacks).Count -eq 0) 'artifact mode topology has no stacks'

    # --- 3. Named-dependency-only fixture: a dependency name alone is not a verified tool ---
    $namedDepRoot = Join-Path $root 'named-dep-only'
    $null = New-Item -ItemType Directory -Path $namedDepRoot -Force
    [IO.File]::WriteAllText((Join-Path $namedDepRoot 'package.json'), @'
{
  "name": "named-dep-only",
  "private": true,
  "dependencies": { "eslint": "^8.0.0" }
}
'@)
    $namedDepRun = Invoke-Detector -ProjectPath $namedDepRoot -PathOverride $emptyBin
    Expect-True ($namedDepRun.ExitCode -eq 0) "named-dep-only detector exits 0 (got $($namedDepRun.ExitCode) $($namedDepRun.StderrText))"
    $namedDepDoc = [Text.Encoding]::UTF8.GetString($namedDepRun.StdoutBytes) | ConvertFrom-Json
    Expect-True ($namedDepDoc.capabilities.lint.status -eq 'unavailable') `
        "a package.json dependency name alone does not verify lint (got $($namedDepDoc.capabilities.lint.status))"

    # --- 4. Broken tool fixture: an on-PATH binary that fails is available-but-failing ---
    $brokenRoot = Join-Path $root 'broken-tool'
    $null = New-Item -ItemType Directory -Path $brokenRoot -Force
    [IO.File]::WriteAllText((Join-Path $brokenRoot 'Cargo.toml'), "[package]`nname = ""broken""`nversion = ""0.1.0""`n")
    $brokenRun = Invoke-Detector -ProjectPath $brokenRoot -PathOverride $cargoBin
    Expect-True ($brokenRun.ExitCode -eq 0) "broken-tool detector exits 0 (got $($brokenRun.ExitCode) $($brokenRun.StderrText))"
    $brokenDoc = [Text.Encoding]::UTF8.GetString($brokenRun.StdoutBytes) | ConvertFrom-Json
    Expect-True ($brokenDoc.capabilities.build.status -eq 'available-but-failing') `
        "a failing on-PATH tool reports available-but-failing (got $($brokenDoc.capabilities.build.status))"
    Expect-True ([string]$brokenDoc.capabilities.build.reason -match 'exit 7') `
        "the failing reason names the exit code (got $($brokenDoc.capabilities.build.reason))"

    # --- 5. Empty repo fixture: baseline sanity ---
    $emptyRepo = Join-Path $root 'empty-repo'
    $null = New-Item -ItemType Directory -Path $emptyRepo -Force
    $emptyRun = Invoke-Detector -ProjectPath $emptyRepo -PathOverride $emptyBin
    Expect-True ($emptyRun.ExitCode -eq 0) "empty-repo detector exits 0 (got $($emptyRun.ExitCode) $($emptyRun.StderrText))"
    $emptyDoc = $null
    try {
        $emptyDoc = [Text.Encoding]::UTF8.GetString($emptyRun.StdoutBytes) | ConvertFrom-Json
    }
    catch {
        $emptyDoc = $null
    }
    Expect-True ($null -ne $emptyDoc) 'empty-repo output parses as valid JSON'
    Expect-True ($emptyDoc.topology.monorepo -eq $false) 'empty-repo topology is not a monorepo'
    Expect-True (@($emptyDoc.topology.packages).Count -eq 1) 'empty-repo topology has exactly the root package'

    # --- 6. Monorepo fixture: packages, stacks, scripts, and file-signal capabilities ---
    $monoRoot = Join-Path $root 'monorepo'
    $null = New-Item -ItemType Directory -Path $monoRoot -Force
    [IO.File]::WriteAllText((Join-Path $monoRoot 'Makefile'), "build:`n`t@echo build`n`ntest:`n`t@echo test`n")
    $monoCi = Join-Path $monoRoot '.github/workflows'
    $null = New-Item -ItemType Directory -Path $monoCi -Force
    [IO.File]::WriteAllText((Join-Path $monoCi 'ci.yml'), "name: CI`non: [push]`njobs: {}`n")
    [IO.File]::WriteAllText((Join-Path $monoRoot 'openapi.yaml'), "openapi: 3.0.0`ninfo:`n  title: test`n  version: '1.0'`npaths: {}`n")
    $monoLocales = Join-Path $monoRoot 'locales'
    $null = New-Item -ItemType Directory -Path $monoLocales -Force
    [IO.File]::WriteAllText((Join-Path $monoLocales 'en.json'), "{}`n")
    $monoReports = Join-Path $monoRoot 'reports'
    $null = New-Item -ItemType Directory -Path $monoReports -Force
    [IO.File]::WriteAllText((Join-Path $monoReports 'junit.xml'), "<?xml version=""1.0""?>`n<testsuite tests=""0""></testsuite>`n")
    $monoA = Join-Path $monoRoot 'a'
    $null = New-Item -ItemType Directory -Path $monoA -Force
    [IO.File]::WriteAllText((Join-Path $monoA 'package.json'), "{`n  ""name"": ""pkg-a"",`n  ""private"": true`n}`n")
    $monoB = Join-Path $monoRoot 'b'
    $null = New-Item -ItemType Directory -Path $monoB -Force
    [IO.File]::WriteAllText((Join-Path $monoB 'pyproject.toml'), "[project]`nname = ""pkg-b""`n")

    $linkTarget = Join-Path $root 'monorepo-link-target'
    $null = New-Item -ItemType Directory -Path $linkTarget -Force
    [IO.File]::WriteAllText((Join-Path $linkTarget 'package.json'), "{`n  ""name"": ""pkg-c-decoy"",`n  ""private"": true`n}`n")
    $linkCreated = $true
    try {
        New-ReparseDirectory (Join-Path $monoRoot 'c') $linkTarget
    }
    catch {
        if ($onWin32) {
            $linkCreated = $false
        }
        else {
            throw
        }
    }

    $monoBefore = Get-NSTreeStamp $monoRoot
    $monoRun = Invoke-Detector -ProjectPath $monoRoot -PathOverride $emptyBin
    $monoAfter = Get-NSTreeStamp $monoRoot
    Expect-True ($monoRun.ExitCode -eq 0) "monorepo detector exits 0 (got $($monoRun.ExitCode) $($monoRun.StderrText))"
    Expect-True ($monoAfter -eq $monoBefore) 'detector wrote nothing into the monorepo fixture'
    $monoDoc = [Text.Encoding]::UTF8.GetString($monoRun.StdoutBytes) | ConvertFrom-Json
    Expect-True ($monoDoc.topology.monorepo -eq $true) 'monorepo topology reports monorepo=true'
    Expect-True (@($monoDoc.topology.packages).Count -eq 3) `
        "monorepo has exactly 3 packages: root, a, b (got $(@($monoDoc.topology.packages).Count))"
    $monoStacks = @($monoDoc.topology.stacks)
    Expect-True ($monoStacks -contains 'javascript-typescript') 'monorepo stacks include javascript-typescript'
    Expect-True ($monoStacks -contains 'python') 'monorepo stacks include python'
    Expect-True ($monoStacks -contains 'make') 'monorepo stacks include make'
    $scriptsReason = [string]$monoDoc.capabilities.scripts.reason
    Expect-True ($scriptsReason -match 'make:build') "scripts reason lists make:build (got $scriptsReason)"
    Expect-True ($scriptsReason -match 'make:test') "scripts reason lists make:test (got $scriptsReason)"
    Expect-True ($monoDoc.capabilities.'api-schema'.status -eq 'available-and-verified') `
        "api-schema is verified (got $($monoDoc.capabilities.'api-schema'.status))"
    Expect-True ($monoDoc.capabilities.localization.status -eq 'available-and-verified') `
        "localization is verified (got $($monoDoc.capabilities.localization.status))"
    Expect-True ($monoDoc.capabilities.ci.status -eq 'available-and-verified') `
        "ci is verified (got $($monoDoc.capabilities.ci.status))"
    Expect-True ($monoDoc.capabilities.'structured-results'.status -eq 'available-and-verified') `
        "structured-results is verified (got $($monoDoc.capabilities.'structured-results'.status))"
    if ($linkCreated) {
        $packagePaths = @($monoDoc.topology.packages) | ForEach-Object { [string]$_ }
        $hasDecoy = $false
        foreach ($p in $packagePaths) {
            if ($p -match '[\\/]c$') {
                $hasDecoy = $true
            }
        }
        Expect-True (-not $hasDecoy) 'the reparse-point/symlink child is skipped from packages'
    }
    else {
        Write-Host 'skip: could not create a reparse point/symlink on this host'
    }

    # --- 7. Usage errors ---
    $missingProject = Invoke-Detector -RawArguments @('-HostName', 'claude')
    Expect-True ($missingProject.ExitCode -eq 1) `
        "missing -Project exits 1 (got $($missingProject.ExitCode))"

    $notADir = Join-Path $root 'not-a-directory.txt'
    [IO.File]::WriteAllText($notADir, "placeholder`n")
    $notADirRun = Invoke-Detector -ProjectPath $notADir -PathOverride $emptyBin
    Expect-True ($notADirRun.ExitCode -eq 1) `
        "a non-directory -Project exits 1 (got $($notADirRun.ExitCode))"
    Expect-True ($notADirRun.StderrText -match 'not a directory') `
        "a non-directory -Project names 'not a directory' on stderr (got $($notADirRun.StderrText))"
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "detect-capabilities-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'detect-capabilities-logic passed'
exit 0
