[CmdletBinding(PositionalBinding = $false)]
param(
    [string]$Format = '',
    [string]$InputPath = '',
    [int]$Top = 10,
    [switch]$Json
)

# normalize-output.ps1 — the native Windows twin of runtime/normalize-output.sh.
#
#   normalize-output.ps1 -Format <fmt> -InputPath <file> [-Top N] [-Json]
#
# Same formats, same summary, same bytes: the parity test diffs both engines over
# every fixture. PowerShell reads JSON itself, so this side never needs jq.
#
# Exit: 0 summary · 1 usage · 3 unavailable

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

function Write-NOUsage {
    param([string]$Message)
    [Console]::Error.WriteLine("normalize-output: $Message")
    exit 1
}

if ([string]::IsNullOrWhiteSpace($Format)) {
    Write-NOUsage 'usage: normalize-output.ps1 -Format <fmt> -InputPath <file> [-Top N] [-Json]'
}
if ([string]::IsNullOrWhiteSpace($InputPath)) {
    Write-NOUsage 'usage: normalize-output.ps1 -Format <fmt> -InputPath <file> [-Top N] [-Json]'
}
if ($Top -lt 0) {
    Write-NOUsage '-Top takes a whole number'
}

if ($Format -ceq 'pytest-junit') { $Format = 'junit' }
$known = @('eslint-json', 'tsc', 'coverage-summary', 'sarif', 'npm-audit', 'junit', 'lcov')
if ($known -cnotcontains $Format) {
    Write-NOUsage "unknown format: $Format"
}

$script:Out = New-Object Text.StringBuilder

function Write-NOLine {
    param([string]$Text = '')
    [void]$script:Out.Append($Text)
    [void]$script:Out.Append("`n")
}

function Complete-NOOutput {
    [Console]::Out.Write($script:Out.ToString())
    [Console]::Out.Flush()
}

# The one line a caller reads when nothing was parsed. Never a zero-finding
# summary: a tool that did not report is not a tool that found nothing.
function Write-NOUnavailable {
    param([string]$Reason)
    [Console]::Out.Write("unavailable $Format" + ': ' + $Reason + "`n")
    [Console]::Out.Flush()
    exit 3
}

# --------------------------------------------------------------- shared shaping

function Get-NOSanitized {
    param([AllowEmptyString()][AllowNull()][string]$Text)
    if ($null -eq $Text) { $Text = '' }
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -ge 32 -and $code -le 126) { [void]$sb.Append($ch) }
        else { [void]$sb.Append(' ') }
    }
    $value = $sb.ToString()
    while ($value.Contains('  ')) { $value = $value.Replace('  ', ' ') }
    $value = $value.Trim([char]' ')
    if ($value.Length -gt 100) { $value = $value.Substring(0, 97) + '...' }
    if ($value -eq '') { $value = '-' }
    return $value
}

function Get-NOPathText {
    param([string]$Text)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int]$ch
        if ($code -ge 32 -and $code -le 126) { [void]$sb.Append($ch) }
        else { [void]$sb.Append(' ') }
    }
    $value = $sb.ToString()
    while ($value.Contains('  ')) { $value = $value.Replace('  ', ' ') }
    return $value.Trim([char]' ')
}

function Get-NORank {
    param([string]$Severity)
    switch -CaseSensitive ($Severity) {
        'critical' { return 5 }
        'error' { return 4 }
        'high' { return 4 }
        'warning' { return 3 }
        'moderate' { return 3 }
        'note' { return 2 }
        'low' { return 2 }
        'info' { return 1 }
        default { return 0 }
    }
}

function Get-NOJsonEscaped {
    param([string]$Text)
    $sb = New-Object Text.StringBuilder
    foreach ($ch in $Text.ToCharArray()) {
        if ($ch -eq '"') { [void]$sb.Append('\"') }
        elseif ($ch -eq '\') { [void]$sb.Append('\\') }
        else { [void]$sb.Append($ch) }
    }
    return $sb.ToString()
}

function Get-NOCellEscaped {
    param([string]$Text)
    return $Text.Replace('|', '\|')
}

# Basis points, integer arithmetic only, so both engines round the same way.
function Get-NOBasisPoints {
    param([long]$Covered, [long]$Total)
    if ($Total -le 0) { return 10000 }
    return [long][Math]::Floor(($Covered * 20000 + $Total) / (2 * $Total))
}

function Get-NOPercent {
    param([long]$Covered, [long]$Total)
    $bp = Get-NOBasisPoints $Covered $Total
    return ('{0}.{1:D2}' -f [long][Math]::Floor($bp / 100), ($bp % 100))
}

function Get-NOBand {
    param([long]$Covered, [long]$Total)
    $bp = Get-NOBasisPoints $Covered $Total
    if ($bp -lt 5000) { return 'error' }
    if ($bp -lt 8000) { return 'warning' }
    return 'note'
}

function Get-NOPlural {
    param([long]$Count, [string]$Word)
    if ($Count -eq 1) { return "$Count $Word" }
    return "$Count ${Word}s"
}

# --------------------------------------------------------------- JSON accessors

function Get-NOField {
    param($Map, [string]$Key)
    if ($null -eq $Map) { return $null }
    if (-not ($Map -is [Collections.IDictionary])) { return $null }
    if (-not $Map.Contains($Key)) { return $null }
    return $Map[$Key]
}

# A list value needs the comma: a bare return unrolls it, and a one-element list
# would then arrive as a scalar. Callers assign the result and never re-wrap it.
function Get-NOArray {
    param($Map, [string]$Key)
    $value = Get-NOField $Map $Key
    if ($null -eq $value) { return , ([object[]]@()) }
    if ($value -is [Array]) { return , ([object[]]$value) }
    return , ([object[]]@($value))
}

function Test-NOArrayValue {
    param($Map, [string]$Key)
    if ($null -eq $Map -or -not ($Map -is [Collections.IDictionary])) { return $false }
    if (-not $Map.Contains($Key)) { return $false }
    return ($Map[$Key] -is [Array])
}

function Get-NONumber {
    param($Map, [string]$Key)
    $value = Get-NOField $Map $Key
    if ($null -eq $value -or $value -is [bool]) { return [long]0 }
    try { return [long][Math]::Floor([double]$value) }
    catch { return [long]0 }
}

function Get-NOText {
    param($Value)
    if ($null -eq $Value) { return '-' }
    if ($Value -is [bool]) { if ($Value) { return 'true' } return 'false' }
    return [string]$Value
}

function Get-NOKeys {
    param($Map)
    if ($null -eq $Map -or -not ($Map -is [Collections.IDictionary])) { return @() }
    $keys = [string[]]@($Map.Keys)
    [Array]::Sort($keys, [StringComparer]::Ordinal)
    return $keys
}

# --------------------------------------------------------------- the input file

if ([IO.Path]::IsPathRooted($InputPath)) { $absolute = $InputPath }
else { $absolute = Join-Path ([string](Get-Location).ProviderPath) $InputPath }

if (-not (Test-Path -LiteralPath $absolute -PathType Leaf)) {
    Write-NOUnavailable 'the input is not a readable file'
}

try { $digest = Get-NSFileSha256 $absolute }
catch { Write-NOUnavailable 'no sha256 tool on this host, so the summary cannot be anchored' }

$script:Headline = '-'
$script:Counts = New-Object 'Collections.Generic.List[object]'
$script:Files = 0
$script:Items = New-Object 'Collections.Generic.List[object]'

function Add-NOCount {
    param([string]$Label, [long]$Value)
    [void]$script:Counts.Add([pscustomobject]@{ Label = $Label; Value = $Value })
}

function Add-NOItem {
    param(
        [string]$Severity,
        [AllowEmptyString()][string]$File,
        [long]$Line,
        [AllowEmptyString()][string]$Code,
        [AllowEmptyString()][string]$Detail
    )
    [void]$script:Items.Add([pscustomobject]@{
            Severity = $Severity; File = $File; Line = $Line; Code = $Code; Detail = $Detail
        })
}

function Read-NOJsonRoot {
    $text = [IO.File]::ReadAllText($absolute, (New-Object Text.UTF8Encoding($false)))
    $trimmed = $text.TrimStart(" `t`r`n")
    $kind = 'other'
    if ($trimmed.StartsWith('[', [StringComparison]::Ordinal)) { $kind = 'array' }
    elseif ($trimmed.StartsWith('{', [StringComparison]::Ordinal)) { $kind = 'object' }
    $parsed = $null
    try { $parsed = ConvertFrom-NSJsonText $text }
    catch { Write-NOUnavailable 'the input is not readable JSON' }
    return [pscustomobject]@{ Kind = $kind; Data = $parsed }
}

function Read-NOLines {
    $bytes = [IO.File]::ReadAllBytes($absolute)
    $latin = [Text.Encoding]::GetEncoding(28591)
    $text = $latin.GetString($bytes)
    return $text.Split("`n")
}

# --------------------------------------------------------------- eslint-json

function Read-NOEslint {
    $root = Read-NOJsonRoot
    if ($root.Kind -ne 'array') { Write-NOUnavailable 'the report is not a JSON array' }
    $rows = @()
    if ($null -ne $root.Data) { $rows = @($root.Data) }
    foreach ($row in $rows) {
        if (-not ($row -is [Collections.IDictionary]) -or -not $row.Contains('messages')) {
            Write-NOUnavailable 'the report is not eslint file results'
        }
        if (-not (Test-NOArrayValue $row 'messages')) {
            Write-NOUnavailable 'the report is not eslint file results'
        }
    }
    $errors = 0
    $warnings = 0
    $files = New-Object 'Collections.Generic.List[string]'
    foreach ($row in $rows) {
        $path = Get-NOText (Get-NOField $row 'filePath')
        $messages = Get-NOArray $row 'messages'
        if ($messages.Count -gt 0 -and -not $files.Contains($path)) { [void]$files.Add($path) }
        foreach ($message in $messages) {
            $severity = Get-NOField $message 'severity'
            $label = 'note'
            if ($null -ne $severity -and [string]$severity -ceq '2') { $label = 'error'; $errors++ }
            elseif ($null -ne $severity -and [string]$severity -ceq '1') { $label = 'warning'; $warnings++ }
            Add-NOItem $label $path (Get-NONumber $message 'line') `
            (Get-NOText (Get-NOField $message 'ruleId')) (Get-NOText (Get-NOField $message 'message'))
        }
    }
    $script:Files = $files.Count
    $script:Headline = 'eslint: ' + (Get-NOPlural $errors 'error') + ', ' +
        (Get-NOPlural $warnings 'warning') + ' in ' + (Get-NOPlural $files.Count 'file')
    Add-NOCount 'errors' $errors
    Add-NOCount 'warnings' $warnings
}

# --------------------------------------------------------------- coverage-summary

function Read-NOCoverage {
    $root = Read-NOJsonRoot
    if ($root.Kind -ne 'object') { Write-NOUnavailable 'the report is not a JSON object' }
    $data = $root.Data
    $total = Get-NOField $data 'total'
    if ($null -eq $total -or -not ($total -is [Collections.IDictionary]) -or -not $total.Contains('lines')) {
        Write-NOUnavailable 'the report has no total.lines block'
    }
    $metrics = @{}
    foreach ($name in @('lines', 'statements', 'functions', 'branches')) {
        $block = Get-NOField $total $name
        $metrics[$name] = @((Get-NONumber $block 'covered'), (Get-NONumber $block 'total'))
    }
    $files = @(Get-NOKeys $data | Where-Object { $_ -ne 'total' })
    $script:Files = $files.Count
    $script:Headline = 'coverage: lines ' + (Get-NOPercent $metrics['lines'][0] $metrics['lines'][1]) +
        '%, statements ' + (Get-NOPercent $metrics['statements'][0] $metrics['statements'][1]) +
        '%, functions ' + (Get-NOPercent $metrics['functions'][0] $metrics['functions'][1]) +
        '%, branches ' + (Get-NOPercent $metrics['branches'][0] $metrics['branches'][1]) +
        '% across ' + (Get-NOPlural $files.Count 'file')
    Add-NOCount 'branchesCovered' $metrics['branches'][0]
    Add-NOCount 'branchesTotal' $metrics['branches'][1]
    Add-NOCount 'functionsCovered' $metrics['functions'][0]
    Add-NOCount 'functionsTotal' $metrics['functions'][1]
    Add-NOCount 'linesCovered' $metrics['lines'][0]
    Add-NOCount 'linesTotal' $metrics['lines'][1]
    Add-NOCount 'statementsCovered' $metrics['statements'][0]
    Add-NOCount 'statementsTotal' $metrics['statements'][1]
    foreach ($name in $files) {
        $lines = Get-NOField (Get-NOField $data $name) 'lines'
        $covered = Get-NONumber $lines 'covered'
        $count = Get-NONumber $lines 'total'
        Add-NOItem (Get-NOBand $covered $count) $name 0 'lines' `
        ("$covered/$count lines covered (" + (Get-NOPercent $covered $count) + '%)')
    }
}

# --------------------------------------------------------------- sarif

function Get-NOSarifLevel {
    param($Value)
    if ($null -eq $Value) { return 'warning' }
    $level = [string]$Value
    if ($level -ceq 'error' -or $level -ceq 'warning' -or $level -ceq 'note') { return $level }
    return 'note'
}

function Read-NOSarif {
    $root = Read-NOJsonRoot
    if ($root.Kind -ne 'object') { Write-NOUnavailable 'the report is not a JSON object' }
    $data = $root.Data
    if (-not (Test-NOArrayValue $data 'runs')) {
        Write-NOUnavailable 'the report has no runs array'
    }
    $runs = Get-NOArray $data 'runs'
    if ($data.Contains('version') -and
        -not ([string](Get-NOField $data 'version')).StartsWith('2.1', [StringComparison]::Ordinal)) {
        Write-NOUnavailable 'the report is not SARIF 2.1'
    }
    $counts = @{ 'error' = [long]0; 'warning' = [long]0; 'note' = [long]0 }
    $files = New-Object 'Collections.Generic.List[string]'
    foreach ($run in $runs) {
        $results = Get-NOArray $run 'results'
        foreach ($result in $results) {
            if ($null -eq $result) { continue }
            $level = Get-NOSarifLevel (Get-NOField $result 'level')
            $counts[$level] = $counts[$level] + 1
            $uri = '-'
            $line = [long]0
            $locations = Get-NOArray $result 'locations'
            if ($locations.Count -gt 0 -and $null -ne $locations[0]) {
                $physical = Get-NOField $locations[0] 'physicalLocation'
                $artifact = Get-NOField $physical 'artifactLocation'
                $found = Get-NOField $artifact 'uri'
                if ($null -ne $found) { $uri = [string]$found }
                $line = Get-NONumber (Get-NOField $physical 'region') 'startLine'
            }
            if (-not $files.Contains((Get-NOSanitized $uri))) { [void]$files.Add((Get-NOSanitized $uri)) }
            $message = Get-NOField $result 'message'
            $text = Get-NOField $message 'text'
            if ($null -eq $text) { $text = Get-NOField $message 'markdown' }
            Add-NOItem $level $uri $line (Get-NOText (Get-NOField $result 'ruleId')) (Get-NOText $text)
        }
    }
    $script:Files = $files.Count
    $script:Headline = 'sarif: ' + (Get-NOPlural $counts['error'] 'error') + ', ' +
        (Get-NOPlural $counts['warning'] 'warning') + ', ' + (Get-NOPlural $counts['note'] 'note') +
        ' in ' + (Get-NOPlural $files.Count 'file')
    Add-NOCount 'errors' $counts['error']
    Add-NOCount 'notes' $counts['note']
    Add-NOCount 'warnings' $counts['warning']
}

# --------------------------------------------------------------- npm-audit

function Get-NOAuditSeverity {
    param($Value)
    if ($null -eq $Value) { return 'info' }
    $level = [string]$Value
    if (@('critical', 'high', 'moderate', 'low') -ccontains $level) { return $level }
    return 'info'
}

function Read-NOAudit {
    $root = Read-NOJsonRoot
    if ($root.Kind -ne 'object') { Write-NOUnavailable 'the report is not a JSON object' }
    $data = $root.Data
    if ($data.Contains('advisories') -and -not $data.Contains('auditReportVersion')) {
        Write-NOUnavailable 'the report predates npm audit version 7'
    }
    $vulnerabilities = Get-NOField $data 'vulnerabilities'
    if (-not $data.Contains('auditReportVersion') -or
        $null -eq $vulnerabilities -or -not ($vulnerabilities -is [Collections.IDictionary])) {
        Write-NOUnavailable 'the report has no npm audit vulnerabilities object'
    }
    $names = @(Get-NOKeys $vulnerabilities)
    $counts = @{ 'critical' = [long]0; 'high' = [long]0; 'moderate' = [long]0; 'low' = [long]0; 'info' = [long]0 }
    foreach ($name in $names) {
        $entry = Get-NOField $vulnerabilities $name
        $level = Get-NOAuditSeverity (Get-NOField $entry 'severity')
        $counts[$level] = $counts[$level] + 1
        $title = '-'
        $via = Get-NOArray $entry 'via'
        if ($via.Count -gt 0 -and $null -ne $via[0]) {
            if ($via[0] -is [Collections.IDictionary]) { $title = Get-NOText (Get-NOField $via[0] 'title') }
            else { $title = [string]$via[0] }
        }
        $fix = 'none'
        $available = Get-NOField $entry 'fixAvailable'
        if ($null -ne $available -and -not ($available -is [bool] -and -not [bool]$available)) {
            $fix = 'available'
        }
        Add-NOItem $level $name 0 (Get-NOText (Get-NOField $entry 'range')) "$title; fix: $fix"
    }
    $script:Files = $names.Count
    $script:Headline = 'npm-audit: ' + (Get-NOPlural $names.Count 'vulnerable package') + ': ' +
    "$($counts['critical']) critical, $($counts['high']) high, $($counts['moderate']) moderate, " +
    "$($counts['low']) low, $($counts['info']) info"
    Add-NOCount 'critical' $counts['critical']
    Add-NOCount 'high' $counts['high']
    Add-NOCount 'info' $counts['info']
    Add-NOCount 'low' $counts['low']
    Add-NOCount 'moderate' $counts['moderate']
    Add-NOCount 'total' $names.Count
}

# --------------------------------------------------------------- tsc

function Read-NOTsc {
    $errors = [long]0
    $warnings = [long]0
    $noise = 0
    $seen = New-Object 'Collections.Generic.List[string]'
    foreach ($raw in Read-NOLines) {
        $line = $raw
        if ($line.EndsWith("`r", [StringComparison]::Ordinal)) { $line = $line.Substring(0, $line.Length - 1) }
        if ($line -cmatch '^[ \t]*$') { continue }
        $p = $line.IndexOf('): ')
        $head = ''
        $rest = ''
        if ($p -ge 0) {
            $head = $line.Substring(0, $p + 1)
            $rest = $line.Substring($p + 3)
        }
        if ($p -ge 0 -and $head -cmatch '\([0-9]+,[0-9]+\)$' -and $rest -cmatch '^(error|warning) TS[0-9]+: ') {
            $q = $head.LastIndexOf('(')
            $file = $head.Substring(0, $q)
            $lc = $head.Substring($q + 1, $head.Length - $q - 2)
            $number = [long]0
            $parts = $lc.Split(',')
            if ($parts.Count -gt 0) { $number = [long]$parts[0] }
            $emitted = Split-NOTscDiagnostic $rest $file $number
            if ($emitted -eq 'error') { $errors++ } else { $warnings++ }
            if (-not $seen.Contains($file)) { [void]$seen.Add($file) }
            continue
        }
        if ($line -cmatch '^(error|warning) TS[0-9]+: ') {
            $emitted = Split-NOTscDiagnostic $line '-' 0
            if ($emitted -eq 'error') { $errors++ } else { $warnings++ }
            continue
        }
        if ($line -cmatch '^Found [0-9]+ error') { continue }
        if ($line -cmatch '^[ \t]') { continue }
        $noise++
    }
    if ($script:Items.Count -eq 0 -and $noise -gt 0) {
        Write-NOUnavailable 'the input holds no TypeScript diagnostics'
    }
    $script:Files = $seen.Count
    $script:Headline = 'tsc: ' + (Get-NOPlural $errors 'error') + ', ' +
        (Get-NOPlural $warnings 'warning') + ' in ' + (Get-NOPlural $seen.Count 'file')
    Add-NOCount 'errors' $errors
    Add-NOCount 'warnings' $warnings
}

function Split-NOTscDiagnostic {
    param([string]$Rest, [string]$File, [long]$Line)
    $s1 = $Rest.IndexOf(' ')
    $severity = $Rest.Substring(0, $s1)
    $tail = $Rest.Substring($s1 + 1)
    $s2 = $tail.IndexOf(' ')
    $code = $tail.Substring(0, $s2 - 1)
    $detail = $tail.Substring($s2 + 1)
    Add-NOItem $severity $File $Line $code $detail
    return $severity
}

# --------------------------------------------------------------- lcov

function Read-NOLcov {
    $sf = ''
    $lf = [long]0
    $lh = [long]0
    $have = $false
    $files = 0
    $totalLf = [long]0
    $totalLh = [long]0
    foreach ($raw in Read-NOLines) {
        $line = $raw
        if ($line.EndsWith("`r", [StringComparison]::Ordinal)) { $line = $line.Substring(0, $line.Length - 1) }
        if ($line -cmatch '^[ \t]*$') { continue }
        if ($line.StartsWith('SF:', [StringComparison]::Ordinal)) {
            $sf = $line.Substring(3); $lf = 0; $lh = 0; $have = $true; continue
        }
        if ($line.StartsWith('LF:', [StringComparison]::Ordinal)) {
            $lf = [long]($line.Substring(3) -as [double]); continue
        }
        if ($line.StartsWith('LH:', [StringComparison]::Ordinal)) {
            $lh = [long]($line.Substring(3) -as [double]); continue
        }
        if ($line -ceq 'end_of_record') {
            if ($have) {
                $files++
                $totalLf += $lf
                $totalLh += $lh
                Add-NOItem (Get-NOBand $lh $lf) $sf 0 'lines' `
                ("$lh/$lf lines covered (" + (Get-NOPercent $lh $lf) + '%)')
                $have = $false
            }
            continue
        }
    }
    if ($have) {
        $files++
        $totalLf += $lf
        $totalLh += $lh
        Add-NOItem (Get-NOBand $lh $lf) $sf 0 'lines' `
        ("$lh/$lf lines covered (" + (Get-NOPercent $lh $lf) + '%)')
    }
    if ($files -eq 0) { Write-NOUnavailable 'the input holds no lcov SF records' }
    $script:Files = $files
    $script:Headline = 'lcov: ' + (Get-NOPercent $totalLh $totalLf) + '% lines covered, ' +
    "$totalLh/$totalLf in " + (Get-NOPlural $files 'file')
    Add-NOCount 'linesCovered' $totalLh
    Add-NOCount 'linesTotal' $totalLf
}

# --------------------------------------------------------------- junit

function Get-NOUnentity {
    param([string]$Text)
    $value = $Text.Replace('&lt;', '<')
    $value = $value.Replace('&gt;', '>')
    $value = $value.Replace('&quot;', '"')
    $value = $value.Replace('&apos;', "'")
    return $value.Replace('&amp;', '&')
}

function Get-NOAttribute {
    param([string]$Record, [string]$Key)
    $match = [regex]::Match($Record, "[ `t`r`n]" + [regex]::Escape($Key) + "=[""']")
    if (-not $match.Success) { return '' }
    $quote = $Record.Substring($match.Index + $match.Length - 1, 1)
    $tail = $Record.Substring($match.Index + $match.Length)
    $end = $tail.IndexOf($quote)
    if ($end -lt 0) { return '' }
    return (Get-NOUnentity $tail.Substring(0, $end))
}

function Get-NOAttributeNumber {
    param([string]$Record, [string]$Key)
    $value = Get-NOAttribute $Record $Key
    if ($value -eq '') { return [long]0 }
    $number = $value -as [double]
    if ($null -eq $number) { return [long]0 }
    return [long][Math]::Floor($number)
}

function Read-NOJunit {
    $bytes = [IO.File]::ReadAllBytes($absolute)
    $text = [Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $suites = [long]0
    $tests = [long]0
    $failures = [long]0
    $errors = [long]0
    $skipped = [long]0
    $saw = $false
    $className = '-'
    $caseName = '-'
    foreach ($record in $text.Split('<')) {
        if ($record -eq '') { continue }
        $name = $record
        $cut = $name.IndexOfAny([char[]]@(' ', "`t", "`r", "`n", '>', '/'))
        if ($cut -ge 0) { $name = $name.Substring(0, $cut) }
        if ($name -ceq 'testsuite') {
            $suites++
            $tests += Get-NOAttributeNumber $record 'tests'
            $failures += Get-NOAttributeNumber $record 'failures'
            $errors += Get-NOAttributeNumber $record 'errors'
            $skipped += Get-NOAttributeNumber $record 'skipped'
            $saw = $true
            continue
        }
        if ($name -ceq 'testcase') {
            $className = Get-NOAttribute $record 'classname'
            $caseName = Get-NOAttribute $record 'name'
            if ($className -eq '') { $className = '-' }
            if ($caseName -eq '') { $caseName = '-' }
            continue
        }
        if ($name -ceq 'failure' -or $name -ceq 'error') {
            $type = Get-NOAttribute $record 'type'
            $detail = $caseName
            if ($type -ne '') { $detail = "$caseName ($type)" }
            Add-NOItem 'error' $className 0 $name $detail
            continue
        }
    }
    if (-not $saw) { Write-NOUnavailable 'the input holds no JUnit testsuite element' }
    $script:Files = $suites
    $script:Headline = 'junit: ' + (Get-NOPlural $tests 'test') + ', ' +
        (Get-NOPlural $failures 'failure') + ', ' + (Get-NOPlural $errors 'error') +
    ", $skipped skipped in " + (Get-NOPlural $suites 'suite')
    Add-NOCount 'errors' $errors
    Add-NOCount 'failures' $failures
    Add-NOCount 'skipped' $skipped
    Add-NOCount 'tests' $tests
}

# --------------------------------------------------------------- run and render

switch -CaseSensitive ($Format) {
    'eslint-json' { Read-NOEslint }
    'coverage-summary' { Read-NOCoverage }
    'sarif' { Read-NOSarif }
    'npm-audit' { Read-NOAudit }
    'tsc' { Read-NOTsc }
    'lcov' { Read-NOLcov }
    'junit' { Read-NOJunit }
}

# Every row becomes one sortable line: severity rank descending first, then file,
# line, code and detail ascending. A byte sort over that key is the whole order,
# which is why the two engines agree without either sorting objects.
$keys = New-Object 'Collections.Generic.List[string]'
foreach ($item in $script:Items) {
    $severity = Get-NOSanitized $item.Severity
    [void]$keys.Add(
        ('{0}' -f (5 - (Get-NORank $severity))) + "`t" +
        (Get-NOSanitized $item.File) + "`t" +
        ('{0:D9}' -f [long]$item.Line) + "`t" +
        (Get-NOSanitized $item.Code) + "`t" +
        (Get-NOSanitized $item.Detail) + "`t" + $severity)
}
$sorted = [string[]]$keys.ToArray()
[Array]::Sort($sorted, [StringComparer]::Ordinal)

$total = $sorted.Count
$shown = [Math]::Min($Top, $total)
$rows = New-Object 'Collections.Generic.List[object]'
for ($i = 0; $i -lt $shown; $i++) {
    $parts = $sorted[$i].Split("`t")
    [void]$rows.Add([pscustomobject]@{
            Severity = $parts[5]; File = $parts[1]; Line = [long]$parts[2]
            Code = $parts[3]; Detail = $parts[4]
        })
}

$countLabels = [string[]]@($script:Counts | ForEach-Object { $_.Label })
[Array]::Sort($countLabels, [StringComparer]::Ordinal)
$countValues = @{}
foreach ($entry in $script:Counts) { $countValues[$entry.Label] = $entry.Value }

$displayPath = Get-NOPathText $InputPath

if ($Json) {
    $text = '{"counts":{'
    for ($i = 0; $i -lt $countLabels.Count; $i++) {
        if ($i -gt 0) { $text += ',' }
        $text += '"' + (Get-NOJsonEscaped $countLabels[$i]) + '":' + [string]$countValues[$countLabels[$i]]
    }
    $text += '},"digest":"' + (Get-NOJsonEscaped $digest) + '","files":' + [string]$script:Files
    $text += ',"format":"' + (Get-NOJsonEscaped $Format) + '","headline":"' +
        (Get-NOJsonEscaped $script:Headline) + '"'
    $text += ',"input":"' + (Get-NOJsonEscaped $displayPath) + '","items":['
    for ($i = 0; $i -lt $rows.Count; $i++) {
        if ($i -gt 0) { $text += ',' }
        $line = 'null'
        if ($rows[$i].Line -ne 0) { $line = [string]$rows[$i].Line }
        $text += '{"code":"' + (Get-NOJsonEscaped $rows[$i].Code) + '","file":"' +
            (Get-NOJsonEscaped $rows[$i].File) + '","line":' + $line + ',"message":"' +
            (Get-NOJsonEscaped $rows[$i].Detail) + '","severity":"' +
            (Get-NOJsonEscaped $rows[$i].Severity) + '"}'
    }
    $text += '],"shown":' + [string]$rows.Count + ',"total":' + [string]$total + ',"version":1}'
    Write-NOLine $text
    Complete-NOOutput
    exit 0
}

Write-NOLine $script:Headline
Write-NOLine ''
if ($rows.Count -gt 0) {
    Write-NOLine '| severity | file | line | code | detail |'
    Write-NOLine '| --- | --- | --- | --- | --- |'
    foreach ($row in $rows) {
        $line = '-'
        if ($row.Line -ne 0) { $line = [string]$row.Line }
        Write-NOLine ('| ' + (Get-NOCellEscaped $row.Severity) + ' | ' + (Get-NOCellEscaped $row.File) +
            ' | ' + $line + ' | ' + (Get-NOCellEscaped $row.Code) + ' | ' +
            (Get-NOCellEscaped $row.Detail) + ' |')
    }
    Write-NOLine ''
}
Write-NOLine ("showing {0} of {1} items" -f $rows.Count, $total)
Write-NOLine ("source: {0} sha256:{1}" -f $displayPath, $digest)
Complete-NOOutput
exit 0
