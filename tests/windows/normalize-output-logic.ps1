# Portable PowerShell coverage for normalize-output: every format, every fixture, against the
# same golden summaries the bash engine is held to.
# Run on macOS or Windows: pwsh -File tests/windows/normalize-output-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/normalize-output.ps1'
$fixtures = Join-Path $repository 'tests/fixtures/normalize'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'

$formats = @('eslint-json', 'tsc', 'coverage-summary', 'sarif', 'npm-audit', 'junit', 'lcov')
$cases = @('sample', 'edge', 'broken')
# Every format carries the three shared cases; a format whose parser has a shape of its
# own carries more, and both engines are held to the same goldens over all of them.
$extraCases = @{
    'eslint-json' = @('strings')
    'tsc' = @('continuation')
    'coverage-summary' = @('unmeasured')
    'sarif' = @('wide')
    'junit' = @('nested', 'cdata')
    'lcov' = @('unmeasured')
}

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

function Test-NSNoCarriageReturn {
    param([byte[]]$Bytes)
    foreach ($b in $Bytes) { if ($b -eq 13) { return $false } }
    return $true
}

function Test-NSSingleTrailingNewline {
    param([byte[]]$Bytes)
    if ($Bytes.Length -eq 0) { return $false }
    if ($Bytes[$Bytes.Length - 1] -ne 10) { return $false }
    if ($Bytes.Length -ge 2 -and $Bytes[$Bytes.Length - 2] -eq 10) { return $false }
    return $true
}

function Test-NSAsciiOnly {
    param([byte[]]$Bytes)
    foreach ($b in $Bytes) { if ($b -ge 128) { return $false } }
    return $true
}

function Test-NSHasBom {
    param([byte[]]$Bytes)
    if ($Bytes.Length -lt 3) { return $false }
    return ($Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)
}

function Test-NSKeysSorted {
    param($Node)
    if ($null -eq $Node) { return $true }
    if ($Node -is [Array]) {
        foreach ($item in $Node) { if (-not (Test-NSKeysSorted $item)) { return $false } }
        return $true
    }
    if ($Node -is [Management.Automation.PSCustomObject]) {
        $names = [string[]]@($Node.PSObject.Properties | ForEach-Object { $_.Name })
        for ($i = 1; $i -lt $names.Count; $i++) {
            if ([string]::CompareOrdinal($names[$i - 1], $names[$i]) -ge 0) { return $false }
        }
        foreach ($property in $Node.PSObject.Properties) {
            if (-not (Test-NSKeysSorted $property.Value)) { return $false }
        }
    }
    return $true
}

function Invoke-Normalize {
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
    $text = ''
    if ($stdout.Count -gt 0) { $text = ($stdout -join "`n") + "`n" }
    return [pscustomobject]@{
        ExitCode = [int]$code
        Text = $text
        Lines = $stdout.ToArray()
        Stderr = ($stderr -join "`n")
    }
}

# The fixture input beside its goldens: one file per case that is not an expectation.
function Get-FixtureInput {
    param([string]$Format, [string]$Case)
    foreach ($file in @(Get-ChildItem -LiteralPath (Join-Path $fixtures $Format) -File |
                Sort-Object -Property Name)) {
        if ($file.Name -clike "$Case.*" -and $file.Name -cnotlike '*.expected.*') {
            return "tests/fixtures/normalize/$Format/$($file.Name)"
        }
    }
    throw "no fixture input for $Format/$Case"
}

Push-Location $repository
try {
    foreach ($format in $formats) {
        $formatCases = @($cases)
        if ($extraCases.ContainsKey($format)) { $formatCases += $extraCases[$format] }
        foreach ($case in $formatCases) {
            $fixtureInput = Get-FixtureInput $format $case
            # The exit code a case is held to, read from its own golden: an unavailable
            # summary is one line and exit 3, anything else is a summary and exit 0.
            $goldenFirst = [IO.File]::ReadAllLines((Join-Path $fixtures "$format/$case.expected.md"))[0]
            $expectedCode = 0
            if ($goldenFirst.StartsWith('unavailable ', [StringComparison]::Ordinal)) {
                $expectedCode = 3
            }

            $markdown = Invoke-Normalize @('-Format', $format, '-InputPath', $fixtureInput)
            Expect-Equal $expectedCode $markdown.ExitCode "$format/$case markdown exit code"
            $goldenMd = Join-Path $fixtures "$format/$case.expected.md"
            Expect-Equal ([IO.File]::ReadAllText($goldenMd)) $markdown.Text `
                "$format/$case renders the golden markdown summary"

            $json = Invoke-Normalize @('-Format', $format, '-InputPath', $fixtureInput, '-Json')
            Expect-Equal $expectedCode $json.ExitCode "$format/$case JSON exit code"
            $goldenJson = Join-Path $fixtures "$format/$case.expected.json"
            Expect-Equal ([IO.File]::ReadAllText($goldenJson)) $json.Text `
                "$format/$case renders the golden JSON summary"

            $bytes = [Text.Encoding]::UTF8.GetBytes($markdown.Text)
            Expect-True (Test-NSNoCarriageReturn $bytes) "$format/$case summary is LF-only"
            Expect-True (Test-NSSingleTrailingNewline $bytes) "$format/$case summary ends with one newline"
            Expect-True (Test-NSAsciiOnly $bytes) "$format/$case summary is ASCII only"
            Expect-True (-not (Test-NSHasBom $bytes)) "$format/$case summary has no BOM"

            if ($expectedCode -eq 3) {
                Expect-Equal 1 $markdown.Lines.Count "$format/$case prints exactly one unavailable line"
                Expect-True ($markdown.Lines[0].StartsWith("unavailable $format" + ': ',
                        [StringComparison]::Ordinal)) "$format/$case names the format it could not read"
            }
            else {
                Expect-True (Test-NSKeysSorted (ConvertFrom-Json $json.Text)) `
                    "$format/$case JSON keys are sorted"
            }
        }
    }

    # A nested report counts its leaf suites once, never the outer suite as well.
    $nested = Invoke-Normalize @('-Format', 'junit', '-InputPath',
        (Get-FixtureInput 'junit' 'nested'), '-Json')
    $nestedReport = ConvertFrom-Json $nested.Text
    Expect-Equal 5 $nestedReport.counts.tests 'a nested report counts every test once'
    Expect-Equal 2 $nestedReport.files 'a nested report counts its leaf suites'

    # A quoted suite element inside a payload is prose, not markup.
    $cdata = Invoke-Normalize @('-Format', 'junit', '-InputPath',
        (Get-FixtureInput 'junit' 'cdata'), '-Json')
    Expect-Equal 2 (ConvertFrom-Json $cdata.Text).counts.tests 'a CDATA payload adds no tests'
    Expect-True ($cdata.Text -cnotmatch 'phantom') 'a CDATA payload adds no rows'

    # A percentage of nothing reads unmeasured on every surface.
    $unmeasured = Invoke-Normalize @('-Format', 'coverage-summary', '-InputPath',
        (Get-FixtureInput 'coverage-summary' 'unmeasured'))
    Expect-True ($unmeasured.Lines[0] -cmatch 'lines unmeasured') `
        'a zero denominator reads unmeasured in the headline'
    Expect-True ($unmeasured.Lines -ccontains
        '| info | src/generated/schema.ts | - | lines | 0/0 lines covered (unmeasured) |') `
        'a file with no lines block reads unmeasured in the table'
    Expect-True ($unmeasured.Lines[0] -cmatch 'branches unmeasured') `
        'a second zero denominator reads unmeasured too'
    Expect-True ($unmeasured.Lines[0] -cnotmatch 'lines 100') 'a zero denominator is never 100%'
    $lcovUnmeasured = Invoke-Normalize @('-Format', 'lcov', '-InputPath',
        (Get-FixtureInput 'lcov' 'unmeasured'))
    Expect-True ($lcovUnmeasured.Lines -ccontains
        '| info | src/generated/schema.js | - | lines | 0/0 lines covered (unmeasured) |') `
        'an LF:0 record reads unmeasured'

    # Two uris that differ only outside ASCII are two files.
    $wide = ConvertFrom-Json (Invoke-Normalize @('-Format', 'sarif', '-InputPath',
            (Get-FixtureInput 'sarif' 'wide'), '-Json')).Text
    Expect-Equal 2 $wide.files 'the file count uniques the uri the report gave'
    Expect-Equal 2 $wide.counts.warnings 'both accented paths are reported'

    # A severity written as a string is the same level as the number.
    $strings = ConvertFrom-Json (Invoke-Normalize @('-Format', 'eslint-json', '-InputPath',
            (Get-FixtureInput 'eslint-json' 'strings'), '-Json')).Text
    Expect-Equal 1 $strings.counts.errors 'severity "2" is an error'
    Expect-Equal 1 $strings.counts.warnings 'severity "1" is a warning'

    # An input of nothing but continuation lines is unavailable, not a clean compile.
    $continuation = Invoke-Normalize @('-Format', 'tsc', '-InputPath',
        (Get-FixtureInput 'tsc' 'continuation'))
    Expect-Equal 3 $continuation.ExitCode 'continuation lines alone exit 3'
    Expect-Equal 'unavailable tsc: the input holds no TypeScript diagnostics' `
        $continuation.Text.TrimEnd("`n") 'continuation lines alone name the one reason'

    # The result digest follows the counts, and the source digest follows the bytes.
    $sampleRun = ConvertFrom-Json (Invoke-Normalize @('-Format', 'lcov', '-InputPath',
            (Get-FixtureInput 'lcov' 'sample'), '-Json')).Text
    Expect-True ($sampleRun.digest -cne $sampleRun.source) `
        'the result digest is not the file digest'
    Expect-Equal 'sample.info' $sampleRun.input 'the JSON body names the file, not the path'

    # pytest-junit is an alias, not a second parser.
    $alias = Invoke-Normalize @('-Format', 'pytest-junit', '-InputPath',
        (Get-FixtureInput 'junit' 'sample'))
    Expect-Equal ([IO.File]::ReadAllText((Join-Path $fixtures 'junit/sample.expected.md'))) `
        $alias.Text 'pytest-junit renders the junit summary'

    # -Top bounds the table without hiding the total.
    $top = Invoke-Normalize @('-Format', 'eslint-json', '-InputPath',
        (Get-FixtureInput 'eslint-json' 'sample'), '-Top', '2')
    Expect-Equal 0 $top.ExitCode 'a bounded table still succeeds'
    Expect-True ($top.Lines -ccontains 'showing 2 of 6 items') '-Top 2 shows two of six rows'
    $none = Invoke-Normalize @('-Format', 'eslint-json', '-InputPath',
        (Get-FixtureInput 'eslint-json' 'sample'), '-Top', '0')
    Expect-True ($none.Lines -ccontains 'showing 0 of 6 items') '-Top 0 shows no rows'
    Expect-True ($none.Lines -cnotcontains '| severity | file | line | code | detail |') `
        '-Top 0 omits the table'

    # Rows sort by severity descending, then file, line, code and detail ascending.
    $sorted = Invoke-Normalize @('-Format', 'eslint-json', '-InputPath',
        (Get-FixtureInput 'eslint-json' 'sample'))
    $rows = @($sorted.Lines | Where-Object { $_ -cmatch '^\| (error|warning|note|critical) ' })
    Expect-Equal 6 $rows.Count 'every eslint message becomes a row'
    Expect-True ($rows[0].StartsWith('| error | src/app.js | 12 |', [StringComparison]::Ordinal)) `
        'the highest severity and lowest file sort first'
    Expect-True ($rows[5].StartsWith('| warning | src/lib/parse.js | 90 |', [StringComparison]::Ordinal)) `
        'the lowest severity sorts last'

    # A missing input is unavailable; a format nobody parses is a usage error.
    $absent = Invoke-Normalize @('-Format', 'tsc', '-InputPath', 'tests/fixtures/normalize/tsc/absent.txt')
    Expect-Equal 3 $absent.ExitCode 'a missing input exits 3'
    Expect-Equal "unavailable tsc: the input is not a readable file`n" $absent.Text `
        'a missing input names the one reason'
    $unknown = Invoke-Normalize @('-Format', 'made-up', '-InputPath', (Get-FixtureInput 'tsc' 'sample'))
    Expect-Equal 1 $unknown.ExitCode 'an unknown format exits 1'
    Expect-True ($unknown.Stderr -clike '*unknown format: made-up*') 'an unknown format says so'
    $noFormat = Invoke-Normalize @('-InputPath', (Get-FixtureInput 'tsc' 'sample'))
    Expect-Equal 1 $noFormat.ExitCode 'a missing -Format exits 1'
    $noInput = Invoke-Normalize @('-Format', 'tsc')
    Expect-Equal 1 $noInput.ExitCode 'a missing -InputPath exits 1'

    # Carriage returns, tabs and non-ASCII bytes reduce to the same row.
    $scratch = Join-Path ([IO.Path]::GetTempPath()) ('nightshift-normalize-' + [Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $scratch
    try {
        $crlf = Join-Path $scratch 'crlf.txt'
        [IO.File]::WriteAllText($crlf, "src/a.ts(1,2): error TS1000: bad.`r`nFound 1 error.`r`n")
        $crlfRun = Invoke-Normalize @('-Format', 'tsc', '-InputPath', $crlf)
        Expect-Equal 0 $crlfRun.ExitCode 'a CRLF report still parses'
        Expect-True ($crlfRun.Lines -ccontains '| error | src/a.ts | 1 | TS1000 | bad. |') `
            'a carriage return never reaches the table'

        $wide = Join-Path $scratch 'wide.txt'
        # Windows PowerShell 5.1 has no `u{} escape, so the char comes from its code point.
        $eacute = [string][char]0x00E9
        [IO.File]::WriteAllBytes($wide, [Text.Encoding]::UTF8.GetBytes(
                "src/x.ts(3,1): error TS2322: caf$eacute  keeps`tone space.`n"))
        $wideRun = Invoke-Normalize @('-Format', 'tsc', '-InputPath', $wide)
        Expect-True ($wideRun.Lines -ccontains '| error | src/x.ts | 3 | TS2322 | caf keeps one space. |') `
            'non-ASCII bytes, tabs and double spaces collapse to one space'

        # The helper reads its input and writes nothing beside it.
        $before = @(Get-ChildItem -LiteralPath $scratch -File | ForEach-Object { $_.Name })
        $null = Invoke-Normalize @('-Format', 'tsc', '-InputPath', $crlf, '-Json')
        $after = @(Get-ChildItem -LiteralPath $scratch -File | ForEach-Object { $_.Name })
        Expect-Equal $before.Count $after.Count 'the helper writes no file of its own'
    }
    finally {
        Remove-Item -LiteralPath $scratch -Recurse -Force -ErrorAction SilentlyContinue
    }
}
finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    Write-Host "normalize-output logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'normalize-output logic passed'
exit 0
