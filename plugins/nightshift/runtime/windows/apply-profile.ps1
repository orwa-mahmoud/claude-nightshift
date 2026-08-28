param(
    [string]$Project = [Environment]::CurrentDirectory,
    [string]$Profile = '',
    [ValidateSet('', 'replace', 'fill')][string]$Mode = '',
    [switch]$List,
    [switch]$Apply
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

$profilesDir = Join-Path $pluginRoot 'skills/nightshift/references/profiles'
$schemaPath = Join-Path $pluginRoot 'skills/nightshift/references/nightshift-rules.schema.json'
$templatePath = Join-Path $pluginRoot 'skills/nightshift/references/nightshift-rules-template.json'

try {
    $hostPath = Resolve-NSCanonicalPath $Project
}
catch {
    [Console]::Error.WriteLine("apply-profile: cannot cd to $Project")
    exit 1
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostPath
}
catch {
    [Console]::Error.WriteLine('apply-profile: invalid .nightshift-link')
    exit 2
}

$ns = Join-Path $workspace '.nightshift'
$rulesPath = Join-Path $ns 'rules.json'

if ($List) {
    Write-Output 'Nightshift rule profiles (local copies, not a subscription)'
    foreach ($file in @(Get-ChildItem -LiteralPath $profilesDir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try {
            $parsed = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json -ErrorAction Stop
            Write-Output ("  {0}  risk={1}  v{2}  {3}" -f $parsed.name, $parsed.risk, $parsed.version, $parsed.use)
        }
        catch {
            Write-Output ("  {0}" -f $file.Name)
        }
    }
    exit 0
}

if ($Mode -notin @('replace', 'fill')) {
    [Console]::Error.WriteLine('apply-profile: -Mode must be replace or fill')
    exit 1
}
if ([string]::IsNullOrEmpty($Profile) -or $Profile -notmatch '^[A-Za-z0-9_-]+$') {
    [Console]::Error.WriteLine("apply-profile: unknown profile $Profile")
    exit 1
}

$src = Join-Path $profilesDir "$Profile.json"
if (-not (Test-Path -LiteralPath $src -PathType Leaf)) {
    [Console]::Error.WriteLine("apply-profile: unknown profile $Profile")
    exit 1
}

try {
    $profileObj = Get-Content -LiteralPath $src -Raw | ConvertFrom-Json -ErrorAction Stop
    $schema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    [Console]::Error.WriteLine('apply-profile: profile is malformed or not version 1')
    exit 2
}

$nameProp = $profileObj.PSObject.Properties['name']
$versionProp = $profileObj.PSObject.Properties['version']
$rulesProp = $profileObj.PSObject.Properties['rules']
if ($null -eq $nameProp -or $null -eq $versionProp -or [string]$versionProp.Value -ne '1' `
    -or $null -eq $rulesProp -or $null -eq $rulesProp.Value `
    -or $rulesProp.Value -is [Array] -or $rulesProp.Value -is [string] -or $rulesProp.Value -is [ValueType]) {
    [Console]::Error.WriteLine('apply-profile: profile is malformed or not version 1')
    exit 2
}

$schemaKeys = @{}
foreach ($property in $schema.properties.PSObject.Properties) {
    $schemaKeys[$property.Name] = $true
}
$unknown = New-Object Collections.Generic.List[string]
foreach ($property in $profileObj.rules.PSObject.Properties) {
    if (-not $schemaKeys.ContainsKey($property.Name) -or $property.Name -eq '$schema') {
        $null = $unknown.Add($property.Name)
    }
}
if ($unknown.Count -gt 0) {
    [Console]::Error.WriteLine("apply-profile: profile has unsupported keys: $($unknown -join ' ')")
    exit 2
}

if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
    [Console]::Error.WriteLine('apply-profile: no .nightshift/ - run setup first')
    exit 2
}

if ($Apply -and (Test-Path -LiteralPath (Join-Path $ns '.shift-armed') -PathType Leaf)) {
    [Console]::Error.WriteLine('apply-profile: refuse to write rules while the shift is armed')
    exit 2
}

$current = [pscustomobject]@{}
if (Test-Path -LiteralPath $rulesPath -PathType Leaf) {
    try {
        $parsedCurrent = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if ($null -ne $parsedCurrent -and $parsedCurrent -isnot [Array] -and $parsedCurrent -isnot [string] -and $parsedCurrent -isnot [ValueType]) {
            $current = $parsedCurrent
        }
    }
    catch {
        $current = [pscustomobject]@{}
    }
}

function Copy-NSJsonObject {
    param($Object)
    if ($null -eq $Object) {
        return [pscustomobject]@{}
    }
    return ($Object | ConvertTo-Json -Depth 20 | ConvertFrom-Json)
}

function Get-NSJsonPropertyValue {
    param($Object, [string]$Name)
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

if ($Mode -eq 'fill') {
    $proposed = Copy-NSJsonObject $current
    foreach ($property in $profileObj.rules.PSObject.Properties) {
        if ($null -eq $proposed.PSObject.Properties[$property.Name]) {
            $proposed | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
    }
}
else {
    $proposed = Copy-NSJsonObject $template
    foreach ($property in $profileObj.rules.PSObject.Properties) {
        if ($null -eq $proposed.PSObject.Properties[$property.Name]) {
            $proposed | Add-Member -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
        else {
            $proposed.($property.Name) = $property.Value
        }
    }
    $schemaValue = Get-NSJsonPropertyValue $current '$schema'
    if ($schemaValue -is [string] -and -not [string]::IsNullOrEmpty($schemaValue)) {
        if ($null -eq $proposed.PSObject.Properties['$schema']) {
            $proposed | Add-Member -NotePropertyName '$schema' -NotePropertyValue $schemaValue
        }
        else {
            $proposed.'$schema' = $schemaValue
        }
    }
}

$toolDeny = Get-NSJsonPropertyValue $proposed 'toolDeny'
$ask = Get-NSJsonPropertyValue $toolDeny 'AskUserQuestion'
$request = Get-NSJsonPropertyValue $toolDeny 'request_user_input'
if ($null -eq $toolDeny -or $toolDeny -is [Array] -or $toolDeny -is [string] -or $toolDeny -is [ValueType] `
    -or $null -eq $toolDeny.PSObject.Properties['AskUserQuestion'] `
    -or $null -eq $toolDeny.PSObject.Properties['request_user_input'] `
    -or $ask -isnot [string] -or $request -isnot [string]) {
    [Console]::Error.WriteLine('apply-profile: proposed rules lack an explicit native question policy - re-run setup first')
    exit 2
}

Write-Output ("Profile: {0}" -f $profileObj.name)
Write-Output ("Risk:    {0}" -f $profileObj.risk)
Write-Output ("Use:     {0}" -f $profileObj.use)
Write-Output ("Mode:    {0}" -f $Mode)
Write-Output 'Rules the profile sets:'
foreach ($property in $profileObj.rules.PSObject.Properties) {
    $json = $property.Value | ConvertTo-Json -Compress -Depth 5
    Write-Output ("  {0}={1}" -f $property.Name, $json)
}
Write-Output ''
Write-Output 'Proposed rules.json'
Write-Output ($proposed | ConvertTo-Json -Depth 20)

if (-not $Apply) {
    Write-Output ''
    Write-Output 'Dry run. Re-run with -Apply after explicit confirmation.'
    exit 0
}

$json = ($proposed | ConvertTo-Json -Depth 20)
if (-not $json.EndsWith("`n")) {
    $json += [Environment]::NewLine
}
$tmp = Join-Path $ns ('.rules.json.{0}' -f $PID)
try {
    [IO.File]::WriteAllText($tmp, $json, (New-Object Text.UTF8Encoding $false))
    Move-Item -LiteralPath $tmp -Destination $rulesPath -Force
}
catch {
    if (Test-Path -LiteralPath $tmp -PathType Leaf) {
        Remove-NSFile $tmp
    }
    exit 2
}
Write-Output "Wrote $rulesPath"
exit 0
