Set-StrictMode -Version 2.0

$script:NSStateVersion = 1
$script:NSUtf8NoBom = New-Object System.Text.UTF8Encoding($false)
$script:NSRulesCacheStamp = ''
$script:NSRulesCache = $null

function Test-NSWindows {
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

# Windows PowerShell 5.1's [Console]::In is the console host, not redirected
# stdin. With -File the host often parks the pipe on $input instead. Read both.
function Get-NSStdinText {
    param([AllowEmptyString()][string]$Piped = '')
    $text = $Piped
    if ([string]::IsNullOrWhiteSpace($text)) {
        $utf8 = New-Object Text.UTF8Encoding $false
        try {
            [Console]::InputEncoding = $utf8
        }
        catch {
        }
        try {
            $stream = [Console]::OpenStandardInput()
            if ($null -ne $stream) {
                $reader = New-Object IO.StreamReader($stream, $utf8, $true)
                try {
                    $text = $reader.ReadToEnd()
                }
                finally {
                    $reader.Dispose()
                }
            }
        }
        catch {
            $text = ''
        }
    }
    if (-not [string]::IsNullOrEmpty($text) -and [int][char]$text[0] -eq 0xFEFF) {
        $text = $text.Substring(1)
    }
    return $text
}

function Test-NSPathEntry {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $null = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

# rm -f: delete a file, succeed if it is already gone, never prompt. Remove-Item
# on a non-empty directory asks for confirmation; a headless host then throws
# NullReferenceException from ShouldContinue.
function Remove-NSFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return
    }
    try {
        [IO.File]::Delete($Path)
    }
    catch {
    }
}

function Test-NSReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
    }
    catch {
        return $false
    }
}

function Resolve-NSCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return [IO.Path]::GetFullPath($resolved.ProviderPath)
}

function Test-NSScratchPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $normalized = $Path.TrimEnd('\', '/').Replace('\', '/')
    return [bool]($normalized -match '^/workspace/scratch(?:/|$)')
}

function Get-NSWorkMode {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $record = Join-Path $Workspace '.nightshift/work-mode'
    if (Test-NSReparsePoint $record) {
        throw 'work mode is malformed'
    }
    if (-not (Test-Path -LiteralPath $record -PathType Leaf)) {
        return 'repository'
    }
    $lines = [IO.File]::ReadAllLines($record)
    if ($lines.Count -lt 1) {
        throw 'work mode is unreadable'
    }
    $mode = $lines[0].Trim()
    if ($mode -notin @('repository', 'artifact')) {
        throw 'work mode is malformed'
    }
    return $mode
}

function Write-NSWorkMode {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][ValidateSet('repository', 'artifact')][string]$Mode
    )
    $ns = Join-Path $Workspace '.nightshift'
    $null = New-Item -ItemType Directory -Path $ns -Force
    $null = Write-NSAtomicLines -Path (Join-Path $ns 'work-mode') -Lines @($Mode)
}

function Get-NSProposedWorkMode {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $project = Resolve-NSCanonicalPath $Workspace
    if (Test-NSScratchPath $project) {
        throw 'disposable scratch workspaces are refused'
    }
    $top = Invoke-NSGit $project @('rev-parse', '--show-toplevel')
    if (-not [string]::IsNullOrWhiteSpace($top)) {
        return 'repository'
    }
    foreach ($child in Get-ChildItem -LiteralPath $project -Directory -Force -ErrorAction SilentlyContinue) {
        if ($child.Name.StartsWith('.')) {
            continue
        }
        if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            continue
        }
        $candidate = Invoke-NSGit $child.FullName @('rev-parse', '--show-toplevel')
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return 'repository'
        }
    }
    return 'artifact'
}

function Resolve-NSWorkspaceRoot {
    param([Parameter(Mandatory = $true)][string]$HostRoot)

    $hostPath = Resolve-NSCanonicalPath $HostRoot
    $link = Join-Path $hostPath '.nightshift-link'
    if (-not (Test-NSPathEntry $link)) {
        return $hostPath
    }
    if ((Test-NSReparsePoint $link) -or -not (Test-Path -LiteralPath $link -PathType Leaf)) {
        throw 'invalid .nightshift-link'
    }

    $lines = [IO.File]::ReadAllLines($link)
    if ($lines.Count -ne 1 -or [string]::IsNullOrWhiteSpace($lines[0])) {
        throw 'invalid .nightshift-link'
    }
    $target = $lines[0]
    if (-not [IO.Path]::IsPathRooted($target)) {
        throw 'invalid .nightshift-link'
    }

    $workspace = Resolve-NSCanonicalPath $target
    if (-not (Test-Path -LiteralPath (Join-Path $workspace '.nightshift') -PathType Container)) {
        throw 'invalid .nightshift-link'
    }
    return $workspace
}

# Windows PowerShell 5.1 turns redirected native stderr into ErrorRecords. With
# $ErrorActionPreference=Stop, `git ... 2>$null` then aborts - including CRLF
# warnings and "unknown revision 'HEAD'" on an unborn branch.
function Invoke-NSGitCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments
    )
    $previous = $ErrorActionPreference
    $hadNative = Test-Path Variable:PSNativeCommandUseErrorActionPreference
    $previousNative = $false
    if ($hadNative) {
        $previousNative = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }
    $ErrorActionPreference = 'Continue'
    try {
        $output = & git -C $Directory @Arguments 2>&1
        $code = $LASTEXITCODE
        if ($null -eq $code) {
            $code = 1
        }
        $lines = [Collections.Generic.List[string]]::new()
        foreach ($item in @($output)) {
            if ($null -eq $item) {
                continue
            }
            $text = [string]$item
            if (-not [string]::IsNullOrEmpty($text)) {
                $lines.Add($text)
            }
        }
        return [pscustomobject]@{
            ExitCode = [int]$code
            Text     = ($lines -join "`n")
            Lines    = $lines.ToArray()
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = 127
            Text     = [string]$_.Exception.Message
            Lines    = @()
        }
    }
    finally {
        $ErrorActionPreference = $previous
        if ($hadNative) {
            $PSNativeCommandUseErrorActionPreference = $previousNative
        }
    }
}

function Invoke-NSGit {
    param(
        [Parameter(Mandatory = $true)][string]$Directory,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $result = Invoke-NSGitCommand $Directory $Arguments
    if ($result.ExitCode -ne 0) {
        return $null
    }
    return (($result.Lines | Select-Object -First 1) -as [string]).Trim()
}

function Get-NSGitDiffText {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )
    $result = Invoke-NSGitCommand $Repository $Arguments
    if ($result.ExitCode -eq 0) {
        return [string]$result.Text
    }
    return $null
}

function Resolve-NSWorkTarget {
    param([Parameter(Mandatory = $true)][string]$Workspace)

    $project = Resolve-NSCanonicalPath $Workspace
    $mode = Get-NSWorkMode $project
    $record = Join-Path $project '.nightshift/work-target'
    if (Test-NSReparsePoint $record) {
        throw 'work target is unreadable'
    }
    if (Test-Path -LiteralPath $record -PathType Leaf) {
        $lines = [IO.File]::ReadAllLines($record)
        if ($lines.Count -lt 1 -or [string]::IsNullOrWhiteSpace($lines[0])) {
            throw 'work target is unreadable'
        }
        $target = $lines[0]
        if (-not [IO.Path]::IsPathRooted($target)) {
            $target = Join-Path $project $target
        }
        $folder = Resolve-NSCanonicalPath $target
        if (Test-NSScratchPath $folder) {
            throw 'work target is a disposable scratch workspace'
        }
        if ($mode -eq 'artifact') {
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                throw 'work target is not a directory'
            }
            return $folder
        }
        $top = Invoke-NSGit $target @('rev-parse', '--show-toplevel')
        if ([string]::IsNullOrWhiteSpace($top)) {
            throw 'work target is not a Git repository'
        }
        return (Resolve-NSCanonicalPath $top)
    }

    if ($mode -eq 'artifact') {
        if (Test-NSScratchPath $project) {
            throw 'work target is a disposable scratch workspace'
        }
        return $project
    }

    $top = Invoke-NSGit $project @('rev-parse', '--show-toplevel')
    if (-not [string]::IsNullOrWhiteSpace($top)) {
        return (Resolve-NSCanonicalPath $top)
    }

    $found = $null
    foreach ($child in Get-ChildItem -LiteralPath $project -Directory -Force -ErrorAction SilentlyContinue) {
        if ($child.Name.StartsWith('.')) {
            continue
        }
        if ($child.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            continue
        }
        $candidate = Invoke-NSGit $child.FullName @('rev-parse', '--show-toplevel')
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $candidate = Resolve-NSCanonicalPath $candidate
        if ($null -ne $found -and $found -ne $candidate) {
            throw 'several child repositories require an explicit work target'
        }
        $found = $candidate
    }
    if ($null -eq $found) {
        throw 'no Git work target found'
    }
    return $found
}

function Write-NSWorkTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Repository,
        [ValidateSet('repository', 'artifact')][string]$Mode = 'repository'
    )
    $top = $null
    if ($Mode -eq 'artifact') {
        $top = Resolve-NSCanonicalPath $Repository
        if (-not (Test-Path -LiteralPath $top -PathType Container)) {
            throw 'work target is not a directory'
        }
        if (Test-NSScratchPath $top) {
            throw 'work target is a disposable scratch workspace'
        }
    }
    else {
        $gitTop = Invoke-NSGit $Repository @('rev-parse', '--show-toplevel')
        if ([string]::IsNullOrWhiteSpace($gitTop)) {
            throw 'work target is not a Git repository'
        }
        $top = Resolve-NSCanonicalPath $gitTop
        if (Test-NSScratchPath $top) {
            throw 'work target is a disposable scratch workspace'
        }
    }
    $ns = Join-Path $Workspace '.nightshift'
    $null = New-Item -ItemType Directory -Path $ns -Force
    Write-NSWorkMode $Workspace $Mode
    $null = Write-NSAtomicLines -Path (Join-Path $ns 'work-target') -Lines @($top)
}

function Get-NSReceiptsDir {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    return (Join-Path $Workspace '.nightshift/receipts')
}

function Test-NSUsableReceiptsDir {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $dir = Get-NSReceiptsDir $Workspace
    return ((Test-Path -LiteralPath $dir -PathType Container) -and -not (Test-NSReparsePoint $dir))
}

function Get-NSFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-NSReceiptSlug {
    param([AllowEmptyString()][string]$Text)
    $s = ([string]$Text).ToLowerInvariant() -replace '[^a-z0-9]+', '-'
    $s = $s.Trim('-')
    if ($s.Length -gt 40) {
        $s = $s.Substring(0, 40).TrimEnd('-')
    }
    if ([string]::IsNullOrEmpty($s)) {
        $s = 'item'
    }
    return $s
}

function Get-NSReceiptsCount {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $dir = Get-NSReceiptsDir $Workspace
    if (-not (Test-NSUsableReceiptsDir $Workspace)) {
        return 0
    }
    return @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            -not $_.Name.StartsWith('.') -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        }).Count
}

function Get-NSLatestReceipt {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $dir = Get-NSReceiptsDir $Workspace
    if (-not (Test-NSUsableReceiptsDir $Workspace)) {
        return $null
    }
    $files = @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            -not $_.Name.StartsWith('.') -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        })
    if ($files.Count -eq 0) {
        return $null
    }
    # LastWriteTime first. Same-second uniqueness suffixes (`stamp-slug-n.md`)
    # sort before `stamp-slug.md` by name (`-` < `.`); map `.md` -> `-0.md` so
    # the unsuffixed sibling sorts first and `-n` wins the tie.
    $latest = @($files | Sort-Object @{
            Expression = { $_.LastWriteTimeUtc.Ticks }
        }, @{
            Expression = {
                if ($_.Name -like '*.md') {
                    $_.Name.Substring(0, $_.Name.Length - 3) + '-0.md'
                }
                else {
                    $_.Name
                }
            }
        })[-1]
    return $latest.FullName
}

function Get-NSReceiptsFingerprint {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $dir = Get-NSReceiptsDir $Workspace
    if (-not (Test-NSUsableReceiptsDir $Workspace)) {
        return 'none'
    }
    $files = @(Get-ChildItem -LiteralPath $dir -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            -not $_.Name.StartsWith('.') -and
            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint)
        } |
        Sort-Object { $_.FullName })
    if ($files.Count -eq 0) {
        return 'none'
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $utf8 = New-Object Text.UTF8Encoding $false
        foreach ($file in $files) {
            $line = '{0} {1}{2}' -f (Get-NSFileSha256 $file.FullName), $file.Name, "`n"
            $bytes = $utf8.GetBytes($line)
            [void]$sha.TransformBlock($bytes, 0, $bytes.Length, $null, 0)
        }
        [void]$sha.TransformFinalBlock([byte[]]@(), 0, 0)
        return (([BitConverter]::ToString($sha.Hash)) -replace '-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-NSWorkTargetHead {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    try {
        $target = Resolve-NSWorkTarget $Workspace
        $head = Invoke-NSGit $target @('rev-parse', 'HEAD')
        if (-not [string]::IsNullOrWhiteSpace($head)) {
            return $head
        }
    }
    catch {
    }
    return 'nohead'
}

function Get-NSProgressToken {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $mode = 'repository'
    try {
        $mode = Get-NSWorkMode $Workspace
    }
    catch {
        $mode = 'repository'
    }
    if ($mode -eq 'artifact') {
        return Get-NSReceiptsFingerprint $Workspace
    }
    return Get-NSWorkTargetHead $Workspace
}

function Get-NSStateKind {
    param([Parameter(Mandatory = $true)][string]$Workspace)

    $ns = Join-Path $Workspace '.nightshift'
    if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
        return 'absent'
    }
    $marker = Join-Path $ns 'state-version'
    if (-not (Test-NSPathEntry $marker)) {
        return 'legacy'
    }
    if ((Test-NSReparsePoint $marker) -or -not (Test-Path -LiteralPath $marker -PathType Leaf)) {
        return 'malformed'
    }
    try {
        $lines = [IO.File]::ReadAllLines($marker)
    }
    catch {
        return 'malformed'
    }
    if ($lines.Count -ne 1 -or $lines[0] -notmatch '^(0|[1-9][0-9]{0,7})$') {
        return 'malformed'
    }
    $version = [int]$lines[0]
    if ($version -gt $script:NSStateVersion) {
        return 'future'
    }
    if ($version -eq $script:NSStateVersion) {
        return 'current'
    }
    return 'legacy'
}

function Get-NSStateRefuseMessage {
    param([Parameter(Mandatory = $true)][string]$Kind)
    if ($Kind -eq 'future') {
        return "Nightshift state-version is newer than this plugin supports (supported: $script:NSStateVersion). Upgrade Nightshift; never rewrite or downgrade the marker."
    }
    if ($Kind -eq 'malformed') {
        return 'Nightshift state-version is malformed. Inspect it only while unarmed; never guess a version.'
    }
    return 'Nightshift state-version is unsupported.'
}

function Get-NSRulesObject {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $path = Join-Path $Workspace '.nightshift/rules.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        $script:NSRulesCacheStamp = ''
        $script:NSRulesCache = $null
        return $null
    }
    try {
        $item = Get-Item -LiteralPath $path -ErrorAction Stop
        $stamp = '{0}:{1}:{2}' -f $item.FullName, $item.Length, $item.LastWriteTimeUtc.Ticks
        if ($script:NSRulesCacheStamp -eq $stamp) {
            return $script:NSRulesCache
        }
        $parsed = Get-Content -LiteralPath $path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $script:NSRulesCacheStamp = $stamp
        $script:NSRulesCache = $parsed
        return $parsed
    }
    catch {
        $script:NSRulesCacheStamp = ''
        $script:NSRulesCache = $null
        return $null
    }
}

function Get-NSRule {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Key,
        [AllowEmptyString()][string]$Override = ''
    )
    if (-not [string]::IsNullOrEmpty($Override)) {
        return $Override
    }
    $rules = Get-NSRulesObject $Workspace
    if ($null -eq $rules) {
        return ''
    }
    $property = $rules.PSObject.Properties[$Key]
    if ($null -eq $property -or $null -eq $property.Value) {
        return ''
    }
    if ($property.Value -is [string] -or $property.Value -is [ValueType]) {
        return [string]$property.Value
    }
    return ($property.Value | ConvertTo-Json -Compress -Depth 20)
}

function Get-NSToolRules {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [AllowEmptyString()][string]$Override = ''
    )
    try {
        if (-not [string]::IsNullOrEmpty($Override)) {
            $map = $Override | ConvertFrom-Json -ErrorAction Stop
        }
        else {
            $rules = Get-NSRulesObject $Workspace
            if ($null -eq $rules) {
                return $null
            }
            $property = $rules.PSObject.Properties['toolDeny']
            if ($null -eq $property) {
                return [pscustomobject]@{}
            }
            $map = $property.Value
        }
        if ($null -eq $map -or $map -is [Array] -or $map -is [string] -or $map -is [ValueType]) {
            throw 'invalid toolDeny'
        }
        foreach ($property in $map.PSObject.Properties) {
            if ($property.Value -isnot [string]) {
                throw 'invalid toolDeny'
            }
        }
        return $map
    }
    catch {
        throw 'toolDeny is not a JSON object of string values'
    }
}

function Get-NSBoxCounts {
    param([Parameter(Mandatory = $true)][string]$PunchList)
    $open = 0
    $ticked = 0
    $inItems = $false
    if (Test-Path -LiteralPath $PunchList -PathType Leaf) {
        foreach ($line in [IO.File]::ReadLines($PunchList)) {
            if (-not $inItems) {
                if ($line -match '^## Items\s*$') {
                    $inItems = $true
                }
                continue
            }
            if ($line -match '^\s*-\s*\[\s\]') {
                $open++
            }
            elseif ($line -match '^\s*-\s*\[[xX]\]') {
                $ticked++
            }
        }
    }
    return [pscustomobject]@{ Open = $open; Ticked = $ticked; Total = ($open + $ticked) }
}

function Get-NSOpenBoxesInFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    $open = 0
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in [IO.File]::ReadLines($Path)) {
            if ($line -match '^\s*-\s*\[\s\]') {
                $open++
            }
        }
    }
    return $open
}

function Get-NSOpenDrafts {
    param([Parameter(Mandatory = $true)][string]$Path)
    $open = 0
    $seenRule = $false
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        foreach ($line in [IO.File]::ReadLines($Path)) {
            if (-not $seenRule) {
                if ($line -match '^---\s*$') {
                    $seenRule = $true
                }
                continue
            }
            if ($line -match '^\s*-\s*\[\s\]') {
                $open++
            }
        }
    }
    return $open
}

function Get-NSCodexIdentityKind {
    param([AllowEmptyString()][string]$SessionId)
    if ([string]::IsNullOrEmpty($SessionId)) {
        return 'missing'
    }
    if ($SessionId -match '[\s/\\$`;|&<>*]') {
        return 'malformed'
    }
    if ($SessionId -match '^(thread_|conv_|chatgpt-|rollout-|task_|scratch_)' `
        -or $SessionId -in @('local', 'unknown')) {
        return 'unsupported'
    }
    if ($SessionId -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' `
        -or $SessionId -match '^[0-9a-fA-F]{32,}$') {
        return 'resumable'
    }
    return 'unsupported'
}

function New-NSPrivateFileSecurity {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::LocalSystemSid,
        $null
    )
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetOwner($identity)
    $acl.SetAccessRuleProtection($true, $false)
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $rights = [Security.AccessControl.FileSystemRights]::FullControl
    $null = $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($identity, $rights, $allow))
    $null = $acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($system, $rights, $allow))
    return $acl
}

function Protect-NSPrivateFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-NSWindows)) {
        return
    }
    $acl = New-NSPrivateFileSecurity
    Set-Acl -LiteralPath $Path -AclObject $acl -ErrorAction Stop
}

function Write-NSAtomicLines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [switch]$Private,
        [switch]$CreateOnly
    )
    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        throw 'destination directory does not exist'
    }
    $leaf = Split-Path -Leaf $Path
    $tempLeaf = if ($leaf.StartsWith('.')) {
        '{0}.tmp.{1}.{2}' -f $leaf, $PID, [guid]::NewGuid().ToString('N')
    }
    else {
        '.{0}.tmp.{1}.{2}' -f $leaf, $PID, [guid]::NewGuid().ToString('N')
    }
    $temp = $null
    if (-not $CreateOnly) {
        $temp = Join-Path $directory $tempLeaf
    }
    $writePath = if ($CreateOnly) { $Path } else { $temp }
    if ($CreateOnly -and (Test-NSPathEntry $Path)) {
        return $false
    }
    $encoding = New-Object System.Text.UTF8Encoding $false
    $createdHere = $false
    try {
        $stream = $null
        $writer = $null
        try {
            $stream = [IO.FileStream]::new(
                $writePath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None
            )
            $createdHere = $true
            $writer = [IO.StreamWriter]::new($stream, $encoding)
            foreach ($line in $Lines) {
                $writer.WriteLine($line)
            }
            $writer.Flush()
        }
        catch [IO.IOException] {
            if ($CreateOnly -and -not $createdHere -and (Test-NSPathEntry $Path)) {
                return $false
            }
            throw
        }
        finally {
            if ($null -ne $writer) {
                $writer.Dispose()
            }
            elseif ($null -ne $stream) {
                $stream.Dispose()
            }
        }
        if ($Private) {
            try {
                Protect-NSPrivateFile $writePath
            }
            catch {
            }
        }
        if ($CreateOnly) {
            return $true
        }
        if (Test-NSPathEntry $Path) {
            if (Test-NSReparsePoint $Path) {
                throw 'refusing to replace a reparse point'
            }
            # .NET Core File.Replace rejects a null backup path; delete the spare after the swap.
            $backup = Join-Path $directory ('{0}.bak.{1}' -f $tempLeaf, [guid]::NewGuid().ToString('N'))
            [IO.File]::Replace($temp, $Path, $backup)
            Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        }
        else {
            [IO.File]::Move($temp, $Path)
        }
        $temp = $null
        return $true
    }
    catch {
        if ($CreateOnly -and $createdHere -and (Test-NSPathEntry $Path)) {
            Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        }
        throw
    }
    finally {
        if ($null -ne $temp -and (Test-Path -LiteralPath $temp -PathType Leaf)) {
            Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-NSProcessStart {
    param([Parameter(Mandatory = $true)][int]$ProcessId)
    try {
        $process = Get-Process -Id $ProcessId -ErrorAction Stop
        return $process.StartTime.ToUniversalTime().ToString('o')
    }
    catch {
        return ''
    }
}

function Test-NSRecordedProcess {
    param(
        [AllowEmptyString()][string]$ProcessId,
        [AllowEmptyString()][string]$Start = ''
    )
    if ($ProcessId -notmatch '^[1-9][0-9]*$') {
        return 'Malformed'
    }
    try {
        $process = Get-Process -Id ([int]$ProcessId) -ErrorAction Stop
    }
    catch [Microsoft.PowerShell.Commands.ProcessCommandException] {
        return 'Dead'
    }
    catch {
        return 'Unavailable'
    }
    if (-not [string]::IsNullOrEmpty($Start)) {
        try {
            $current = $process.StartTime.ToUniversalTime().ToString('o')
        }
        catch {
            return 'Unavailable'
        }
        if ($current -ne $Start) {
            return 'Dead'
        }
    }
    return 'Alive'
}

function Get-NSHostProcess {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [int]$StartingProcessId = $PID
    )
    try {
        $records = @(Get-CimInstance Win32_Process -Property ProcessId, ParentProcessId, Name -ErrorAction Stop)
    }
    catch {
        return $null
    }
    $byId = @{}
    foreach ($record in $records) {
        $byId[[int]$record.ProcessId] = $record
    }
    $current = $StartingProcessId
    for ($i = 0; $i -lt 8; $i++) {
        if ($current -le 1) {
            break
        }
        $record = $byId[$current]
        if ($null -eq $record) {
            return $null
        }
        $name = [IO.Path]::GetFileNameWithoutExtension([string]$record.Name)
        if ($name -ieq $HostName) {
            return [pscustomobject]@{
                Id = [string]$record.ProcessId
                Start = Get-NSProcessStart ([int]$record.ProcessId)
            }
        }
        $current = [int]$record.ParentProcessId
    }
    return $null
}

function Protect-NSMutexScopeReceipt {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)

    $receiptGit = Join-Path $NightshiftDir '.git'
    if (-not (Test-Path -LiteralPath $receiptGit -PathType Container)) {
        return $true
    }
    $exclude = Join-Path $receiptGit 'info/exclude'
    if ((Test-NSPathEntry $exclude) -and
        ((Test-NSReparsePoint $exclude) -or -not (Test-Path -LiteralPath $exclude -PathType Leaf))) {
        return $false
    }
    try {
        $lines = [Collections.Generic.List[string]]::new()
        if (Test-Path -LiteralPath $exclude -PathType Leaf) {
            $lines.AddRange([string[]][IO.File]::ReadAllLines($exclude))
        }
        $changed = $false
        foreach ($entry in @('.mutex-scope', '.mutex-scope.tmp.*')) {
            if (-not $lines.Contains($entry)) {
                $lines.Add($entry)
                $changed = $true
            }
        }
        if ($changed) {
            $null = Write-NSAtomicLines -Path $exclude -Lines $lines.ToArray()
        }
        $removed = Invoke-NSGitCommand $NightshiftDir @(
            'rm', '-r', '--cached', '--quiet', '--force', '--ignore-unmatch', '--',
            '.mutex-scope', '.mutex-scope.tmp.*'
        )
        return $removed.ExitCode -eq 0
    }
    catch {
        return $false
    }
}

function Get-NSMutexScope {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)

    if (-not (Protect-NSMutexScopeReceipt $NightshiftDir)) {
        return ''
    }
    $path = Join-Path $NightshiftDir '.mutex-scope'
    if (-not (Test-NSPathEntry $path)) {
        $bytes = New-Object byte[] 16
        $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
        try {
            $rng.GetBytes($bytes)
        }
        finally {
            $rng.Dispose()
        }
        $candidate = ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
        try {
            $null = Write-NSAtomicLines -Path $path -Lines @($candidate) -Private -CreateOnly
        }
        catch {
            return ''
        }
    }
    if ((Test-NSReparsePoint $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ''
    }
    try {
        try {
            Protect-NSPrivateFile $path
        }
        catch {
        }
        $lines = [IO.File]::ReadAllLines($path)
    }
    catch {
        return ''
    }
    if ($lines.Count -ne 1 -or $lines[0] -notmatch '^[a-f0-9]{32}$') {
        return ''
    }
    return $lines[0]
}

function New-NSMutexSecurity {
    $acl = New-Object Security.AccessControl.MutexSecurity
    $acl.SetAccessRuleProtection($true, $false)
    $allow = [Security.AccessControl.AccessControlType]::Allow
    $rights = [Security.AccessControl.MutexRights]::FullControl
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $system = [Security.Principal.SecurityIdentifier]::new(
        [Security.Principal.WellKnownSidType]::LocalSystemSid,
        $null
    )
    $null = $acl.AddAccessRule([Security.AccessControl.MutexAccessRule]::new($identity, $rights, $allow))
    $null = $acl.AddAccessRule([Security.AccessControl.MutexAccessRule]::new($system, $rights, $allow))
    return $acl
}

function Enter-NSMutex {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][string]$Name,
        [ValidateRange(0, 30000)][int]$TimeoutMilliseconds = 2000
    )
    $workspaceScope = Get-NSMutexScope $NightshiftDir
    if ([string]::IsNullOrEmpty($workspaceScope)) {
        return $null
    }
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $scope = $workspaceScope + '|' + $Name
        $digest = $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($scope))
        $suffix = ([BitConverter]::ToString($digest, 0, 16)).Replace('-', '')
    }
    finally {
        $sha.Dispose()
    }
    $mutex = $null
    try {
        $created = $false
        $mutexSecurity = New-NSMutexSecurity
        if ($PSVersionTable.PSVersion.Major -lt 6) {
            $mutex = [Threading.Mutex]::new(
                $false,
                "Global\Nightshift-$suffix",
                [ref]$created,
                $mutexSecurity
            )
        }
        else {
            $mutex = [Threading.MutexAcl]::Create(
                $false,
                "Global\Nightshift-$suffix",
                [ref]$created,
                $mutexSecurity
            )
        }
        try {
            $acquired = $mutex.WaitOne($TimeoutMilliseconds)
        }
        catch [Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) {
            $mutex.Dispose()
            return $null
        }
        return $mutex
    }
    catch {
        if ($null -ne $mutex) {
            $mutex.Dispose()
        }
        return $null
    }
}

function Exit-NSMutex {
    param([AllowNull()][Threading.Mutex]$Mutex)
    if ($null -eq $Mutex) {
        return
    }
    try {
        $Mutex.ReleaseMutex()
    }
    finally {
        $Mutex.Dispose()
    }
}

function Test-NSSafeLine {
    param([AllowEmptyString()][string]$Value)
    return $Value.IndexOfAny([char[]]"`r`n") -lt 0
}

function Claim-NSSession {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [AllowEmptyString()][string]$Transcript = '',
        [AllowEmptyString()][string]$ProcessId = '',
        [AllowEmptyString()][string]$Start = '',
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName
    )
    if ([string]::IsNullOrEmpty($SessionId)) {
        return $false
    }
    foreach ($value in @($SessionId, $Transcript, $ProcessId, $Start)) {
        if (-not (Test-NSSafeLine $value)) {
            return $false
        }
    }
    if ($ProcessId -notmatch '^[0-9]*$') {
        return $false
    }
    try {
        $path = Join-Path $NightshiftDir '.shift-session'
        if (Test-NSReparsePoint $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
        return Write-NSAtomicLines -Path $path `
            -Lines @($SessionId, $Transcript, $ProcessId, $Start, $HostName) -Private -CreateOnly
    }
    catch {
        return $false
    }
}

function Read-NSSession {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $path = Join-Path $NightshiftDir '.shift-session'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-NSReparsePoint $path)) {
        return $null
    }
    try {
        $lines = [IO.File]::ReadAllLines($path)
    }
    catch {
        return $null
    }
    if ($lines.Count -lt 1 -or $lines.Count -gt 5 -or [string]::IsNullOrEmpty($lines[0])) {
        return $null
    }
    $values = @('', '', '', '', 'claude')
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $values[$i] = $lines[$i]
    }
    if ($values[2] -notmatch '^[0-9]*$' -or $values[4] -notin @('claude', 'codex', 'cursor')) {
        return $null
    }
    return [pscustomobject]@{
        SessionId = $values[0]
        Transcript = $values[1]
        ProcessId = $values[2]
        Start = $values[3]
        HostName = $values[4]
    }
}

function Test-NSClaudeForeignCursorSurface {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [AllowEmptyString()][string]$Transcript = ''
    )
    if ($Transcript -match '[/\\]\.cursor([/\\]|$)') {
        return $true
    }
    $session = Read-NSSession $NightshiftDir
    return ($null -ne $session -and $session.HostName -eq 'cursor')
}

function Write-NSSession {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [AllowEmptyString()][string]$Transcript = '',
        [AllowEmptyString()][string]$ProcessId = '',
        [AllowEmptyString()][string]$Start = '',
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName
    )
    foreach ($value in @($SessionId, $Transcript, $ProcessId, $Start)) {
        if (-not (Test-NSSafeLine $value)) {
            return $false
        }
    }
    if ([string]::IsNullOrEmpty($SessionId) -or $ProcessId -notmatch '^[0-9]*$') {
        return $false
    }
    try {
        $path = Join-Path $NightshiftDir '.shift-session'
        if (Test-NSReparsePoint $path) {
            Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
        }
        return Write-NSAtomicLines -Path $path `
            -Lines @($SessionId, $Transcript, $ProcessId, $Start, $HostName) -Private
    }
    catch {
        return $false
    }
}

function Read-NSLease {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $path = Join-Path $NightshiftDir '.shift-lease'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-NSReparsePoint $path)) {
        return $null
    }
    try {
        $lines = [IO.File]::ReadAllLines($path)
    }
    catch {
        return $null
    }
    if ($lines.Count -ne 6) {
        return $null
    }
    foreach ($line in $lines) {
        if (-not (Test-NSSafeLine $line)) {
            return $null
        }
    }
    if ($lines[1] -notin @('claude', 'codex', 'cursor') -or $lines[2] -notmatch '^[1-9][0-9]*$' `
        -or $lines[3] -notmatch '^[A-Za-z0-9._-]*$' -or $lines[4] -notmatch '^[0-9]*$') {
        return $null
    }
    if ([string]::IsNullOrEmpty($lines[4]) -and -not [string]::IsNullOrEmpty($lines[5])) {
        return $null
    }
    if ([string]::IsNullOrEmpty($lines[0]) -and [string]::IsNullOrEmpty($lines[3])) {
        return $null
    }
    return [pscustomobject]@{
        SessionId = $lines[0]
        HostName = $lines[1]
        Generation = [int]$lines[2]
        Nonce = $lines[3]
        ProcessId = $lines[4]
        Start = $lines[5]
    }
}

function Write-NSLease {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [AllowEmptyString()][string]$SessionId,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Generation,
        [AllowEmptyString()][string]$Nonce,
        [AllowEmptyString()][string]$ProcessId,
        [AllowEmptyString()][string]$Start
    )
    if ($Generation -lt 1 -or $Nonce -notmatch '^[A-Za-z0-9._-]*$' -or $ProcessId -notmatch '^[0-9]*$') {
        return $false
    }
    foreach ($value in @($SessionId, $Start)) {
        if (-not (Test-NSSafeLine $value)) {
            return $false
        }
    }
    if ([string]::IsNullOrEmpty($SessionId) -and [string]::IsNullOrEmpty($Nonce)) {
        return $false
    }
    if ([string]::IsNullOrEmpty($ProcessId) -and -not [string]::IsNullOrEmpty($Start)) {
        return $false
    }
    try {
        return Write-NSAtomicLines -Path (Join-Path $NightshiftDir '.shift-lease') `
            -Lines @($SessionId, $HostName, [string]$Generation, $Nonce, $ProcessId, $Start) -Private
    }
    catch {
        return $false
    }
}

function Claim-NSInitialLease {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [AllowEmptyString()][string]$ProcessId = '',
        [AllowEmptyString()][string]$Start = ''
    )
    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return $false
    }
    try {
        $path = Join-Path $NightshiftDir '.shift-lease'
        if (Test-NSPathEntry $path) {
            return $null -ne (Read-NSLease $NightshiftDir)
        }
        return Write-NSLease $NightshiftDir $SessionId $HostName 1 '' $ProcessId $Start
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function New-NSLeaseNonce {
    param(
        [Parameter(Mandatory = $true)][string]$HostName,
        [Parameter(Mandatory = $true)][int]$Generation
    )
    $bytes = New-Object byte[] 18
    $rng = New-Object Security.Cryptography.RNGCryptoServiceProvider
    try {
        $rng.GetBytes($bytes)
    }
    finally {
        $rng.Dispose()
    }
    $random = [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    return "$HostName.$Generation.$PID.$random"
}

function Takeover-NSLease {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [AllowEmptyString()][string]$SessionId = '',
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName
    )
    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return $null
    }
    try {
        $generation = 0
        $path = Join-Path $NightshiftDir '.shift-lease'
        if (Test-NSPathEntry $path) {
            $lease = Read-NSLease $NightshiftDir
            if ($null -eq $lease) {
                return $null
            }
            if (-not [string]::IsNullOrEmpty($lease.SessionId)) {
                $SessionId = $lease.SessionId
            }
            $generation = $lease.Generation
        }
        $generation++
        $nonce = New-NSLeaseNonce $HostName $generation
        if (-not (Write-NSLease $NightshiftDir $SessionId $HostName $generation $nonce '' '')) {
            return $null
        }
        return [pscustomobject]@{ Generation = $generation; Nonce = $nonce }
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function Test-NSLeaseNonce {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [AllowEmptyString()][string]$Nonce,
        [AllowEmptyString()][string]$Generation
    )
    if ([string]::IsNullOrEmpty($Nonce) -or $Generation -notmatch '^[1-9][0-9]*$') {
        return $false
    }
    $lease = Read-NSLease $NightshiftDir
    return $null -ne $lease -and $lease.HostName -eq $HostName `
        -and $lease.Generation -eq [int]$Generation -and $lease.Nonce -eq $Nonce
}

function Bind-NSLeaseSession {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [Parameter(Mandatory = $true)][string]$Nonce,
        [Parameter(Mandatory = $true)][string]$Generation
    )
    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return $false
    }
    try {
        if (-not (Test-NSLeaseNonce $NightshiftDir $HostName $Nonce $Generation)) {
            return $false
        }
        $lease = Read-NSLease $NightshiftDir
        $scope = $lease.SessionId
        if ([string]::IsNullOrEmpty($scope)) {
            $scope = $SessionId
        }
        return Write-NSLease $NightshiftDir $scope $HostName $lease.Generation $lease.Nonce $lease.ProcessId $lease.Start
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function Attach-NSLeaseProcess {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [Parameter(Mandatory = $true)][string]$Nonce,
        [Parameter(Mandatory = $true)][string]$Generation,
        [Parameter(Mandatory = $true)][string]$ProcessId,
        [AllowEmptyString()][string]$Start = ''
    )
    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return $false
    }
    try {
        if (-not (Test-NSLeaseNonce $NightshiftDir $HostName $Nonce $Generation)) {
            return $false
        }
        $lease = Read-NSLease $NightshiftDir
        return Write-NSLease $NightshiftDir $lease.SessionId $HostName $lease.Generation $lease.Nonce $ProcessId $Start
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function Restore-NSLeaseInteractive {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return $false
    }
    try {
        $lease = Read-NSLease $NightshiftDir
        if ($null -eq $lease) {
            return $false
        }
        if ([string]::IsNullOrEmpty($lease.Nonce)) {
            return $true
        }
        if (-not [string]::IsNullOrEmpty($lease.ProcessId)) {
            if ((Test-NSRecordedProcess $lease.ProcessId $lease.Start) -ne 'Dead') {
                return $false
            }
        }
        if ([string]::IsNullOrEmpty($lease.SessionId)) {
            $path = Join-Path $NightshiftDir '.shift-lease'
            Remove-NSFile $path
            return -not (Test-NSPathEntry $path)
        }
        # Empty pid: the recorded session id may reclaim. Copying a still-live
        # recorded pid would fence that conversation's next tool process.
        return Write-NSLease $NightshiftDir $lease.SessionId $lease.HostName ($lease.Generation + 1) '' '' ''
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function Test-NSLeaseAllows {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [AllowEmptyString()][string]$SessionId,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [AllowEmptyString()][string]$ProcessId = '',
        [AllowEmptyString()][string]$Start = '',
        [AllowEmptyString()][string]$Nonce = '',
        [AllowEmptyString()][string]$Generation = ''
    )
    $lease = Read-NSLease $NightshiftDir
    if ($null -eq $lease) {
        return 'Invalid'
    }
    if ($lease.HostName -ne $HostName) {
        return 'Deny'
    }
    if (-not [string]::IsNullOrEmpty($lease.Nonce)) {
        if ($lease.Nonce -eq $Nonce -and [string]$lease.Generation -eq $Generation) {
            return 'Allow'
        }
        return 'Deny'
    }
    if ($lease.SessionId -ne $SessionId -or -not [string]::IsNullOrEmpty($Nonce) `
        -or -not [string]::IsNullOrEmpty($Generation)) {
        return 'Deny'
    }
    if ([string]::IsNullOrEmpty($lease.ProcessId)) {
        return 'Allow'
    }
    if ($lease.ProcessId -eq $ProcessId -and (Test-NSRecordedProcess $lease.ProcessId $lease.Start) -eq 'Alive') {
        return 'Allow'
    }
    if ([string]::IsNullOrEmpty($ProcessId) -or (Test-NSRecordedProcess $lease.ProcessId $lease.Start) -ne 'Dead') {
        return 'Deny'
    }

    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return 'Deny'
    }
    try {
        $current = Read-NSLease $NightshiftDir
        if ($null -eq $current -or $current.SessionId -ne $SessionId -or $current.HostName -ne $HostName `
            -or $current.Generation -ne $lease.Generation -or -not [string]::IsNullOrEmpty($current.Nonce) `
            -or (Test-NSRecordedProcess $current.ProcessId $current.Start) -ne 'Dead') {
            return 'Deny'
        }
        if (Write-NSLease $NightshiftDir $SessionId $HostName ($current.Generation + 1) '' $ProcessId $Start) {
            return 'Allow'
        }
        return 'Deny'
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function Release-NSLease {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return $false
    }
    try {
        $path = Join-Path $NightshiftDir '.shift-lease'
        Remove-NSFile $path
        return -not (Test-NSPathEntry $path)
    }
    catch {
        return $false
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function Reset-NSStaleLease {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $mutex = Enter-NSMutex $NightshiftDir '.lease-lock.d'
    if ($null -eq $mutex) {
        return $false
    }
    try {
        Remove-NSFile (Join-Path $NightshiftDir '.shift-lease')
        Get-ChildItem -LiteralPath $NightshiftDir -Filter '.shift-lease.tmp.*' -Force -ErrorAction SilentlyContinue |
            Remove-Item -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $NightshiftDir '.lease-lock.d') -Recurse -Force -ErrorAction SilentlyContinue
        return $true
    }
    finally {
        Exit-NSMutex $mutex
    }
}

function Remove-NSPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-NSReparsePoint $Path) {
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return
    }
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        return
    }
    Remove-NSFile $Path
}

function Resolve-NSControlWorkspace {
    param([Parameter(Mandatory = $true)][string]$Project)
    $hostPath = Resolve-NSCanonicalPath $Project
    $workspace = Resolve-NSWorkspaceRoot $hostPath
    $ns = Join-Path $workspace '.nightshift'
    return [pscustomobject]@{
        HostRoot = $hostPath
        Workspace = $workspace
        NightshiftDir = $ns
    }
}

function Test-NSBroadWorkspace {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $ws = $Workspace.TrimEnd('\', '/')
    if ([string]::IsNullOrEmpty($ws)) { return $true }
    if ($ws -in @('/', '\', 'C:', 'C:\')) { return $true }
    $root = ''
    try { $root = [IO.Path]::GetPathRoot($ws).TrimEnd('\', '/') } catch { $root = '' }
    if (-not [string]::IsNullOrEmpty($root) -and $ws.Equals($root, [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $home = ''
    if (-not [string]::IsNullOrEmpty($env:USERPROFILE)) {
        try { $home = Resolve-NSCanonicalPath $env:USERPROFILE } catch { $home = '' }
    }
    if ([string]::IsNullOrEmpty($home) -and -not [string]::IsNullOrEmpty($env:HOME)) {
        try { $home = Resolve-NSCanonicalPath $env:HOME } catch { $home = '' }
    }
    if (-not [string]::IsNullOrEmpty($home) -and $ws.Equals($home.TrimEnd('\', '/'), [StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }
    $forbidden = @()
    if (-not [string]::IsNullOrEmpty($root)) {
        $forbidden += (Join-Path $root 'Users')
        $forbidden += (Join-Path $root 'Windows')
        $forbidden += (Join-Path $root 'Program Files')
        $forbidden += (Join-Path $root 'Program Files (x86)')
    }
    foreach ($item in $forbidden) {
        $candidate = $item.TrimEnd('\', '/')
        if ($ws.Equals($candidate, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Read-NSControlLink {
    param([Parameter(Mandatory = $true)][string]$HostRoot)
    $link = Join-Path $HostRoot '.nightshift-link'
    if (-not (Test-NSPathEntry $link)) { return $null }
    if ((Test-NSReparsePoint $link) -or -not (Test-Path -LiteralPath $link -PathType Leaf)) {
        throw 'invalid .nightshift-link'
    }
    $lines = [IO.File]::ReadAllLines($link)
    if ($lines.Count -ne 1 -or [string]::IsNullOrWhiteSpace($lines[0])) {
        throw 'invalid .nightshift-link'
    }
    $target = $lines[0]
    if (-not [IO.Path]::IsPathRooted($target)) {
        throw 'invalid .nightshift-link'
    }
    try {
        return Resolve-NSCanonicalPath $target
    }
    catch {
        $parent = Split-Path -Parent $target
        return (Join-Path (Resolve-NSCanonicalPath $parent) (Split-Path -Leaf $target))
    }
}

function Get-NSControlStartRefuseReason {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $stop = Join-Path $NightshiftDir 'STOP'
    $ended = Join-Path $NightshiftDir '.ended'
    if (-not (Test-Path -LiteralPath $stop -PathType Leaf)) { return '' }
    if ((Test-Path -LiteralPath $ended -PathType Leaf) -and -not (Test-NSReparsePoint $ended)) { return '' }
    $deadline = Join-Path $NightshiftDir 'deadline'
    if (-not (Test-Path -LiteralPath $deadline -PathType Leaf) -or (Test-NSReparsePoint $deadline)) {
        return ''
    }
    $raw = ([IO.File]::ReadAllText($deadline)).Trim()
    if ($raw -notmatch '^[0-9]+$') { return '' }
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if ($now -lt [long]$raw) { return '' }
    return "paused shift deadline has expired - write a new UNIX epoch to $NightshiftDir/deadline, or run Reset then Start; refusing to invent a time budget"
}

function Stop-NSWatchman {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $pidFile = Join-Path $NightshiftDir '.watchman'
    $tick = Join-Path $NightshiftDir '.watchman-tick'
    if (Test-NSReparsePoint $pidFile) {
        Remove-NSPath $pidFile
        Remove-NSPath $tick
        return 'stopped'
    }
    if (-not (Test-Path -LiteralPath $pidFile -PathType Leaf)) {
        Remove-NSPath $tick
        return 'absent'
    }
    $lines = @([IO.File]::ReadAllLines($pidFile))
    $pid = if ($lines.Count -gt 0) { $lines[0].Trim() } else { '' }
    $start = if ($lines.Count -gt 1) { [string]$lines[1] } else { '' }
    $state = Test-NSRecordedProcess $pid $start
    if ($state -in @('Dead', 'Malformed')) {
        Remove-NSPath $pidFile
        Remove-NSPath $tick
        return 'absent'
    }
    if ($state -ne 'Alive') {
        return 'unverified'
    }
    if ([string]::IsNullOrEmpty($start)) {
        $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
        $blob = ''
        if ($null -ne $proc) {
            $blob = [string]$proc.ProcessName + ' ' + [string]$proc.Path
        }
        if ($blob -notmatch 'watchman\.ps1|watchman\.sh|start-watchman') {
            return 'unverified'
        }
    }
    Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue
    Remove-NSPath $pidFile
    Remove-NSPath $tick
    return 'stopped'
}

function Clear-NSRuntimeMarkers {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    foreach ($name in @('.shift-armed', '.ended', '.session-end', '.shift-pulse', '.mint-failed', '.shift-session', '.stall', '.notified', '.watchman-tick', '.mutex-scope')) {
        Remove-NSPath (Join-Path $NightshiftDir $name)
    }
    Get-ChildItem -LiteralPath $NightshiftDir -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '.shift-session.tmp.*' -or $_.Name -like '.mutex-scope.tmp.*' } |
        ForEach-Object { Remove-NSPath $_.FullName }
    Remove-NSPath (Join-Path $NightshiftDir '.lock.d')
    $null = Reset-NSStaleLease $NightshiftDir
}

function Write-NSControlLog {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][string]$Line
    )
    $log = Join-Path $NightshiftDir 'shift-log.md'
    $stamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    Add-Content -LiteralPath $log -Value "$stamp · $Line" -Encoding utf8
}

function Stop-NSShift {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [string]$Reason = 'stopped by owner'
    )
    $ctx = Resolve-NSControlWorkspace $Project
    $ns = $ctx.NightshiftDir
    if (Test-NSReparsePoint $ns) { throw 'stop-shift: .nightshift path is not a usable directory' }
    if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
        throw "stop-shift: no .nightshift/ at $($ctx.Workspace)"
    }
    if ([string]::IsNullOrEmpty($Reason)) { $Reason = 'stopped by owner' }
    $ts = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    Remove-NSPath (Join-Path $ns 'STOP')
    [IO.File]::WriteAllText((Join-Path $ns 'STOP'), "$Reason · $ts`n")
    $watch = Stop-NSWatchman $ns
    Clear-NSRuntimeMarkers $ns
    $null = Write-NSReason $ns 'owner-stop'
    Write-NSControlLog $ns 'stopped by owner'
    $open = 0
    $punch = Join-Path $ns 'punch-list.md'
    if (Test-Path -LiteralPath $punch -PathType Leaf) {
        $open = (Get-NSBoxCounts $punch).Open
    }
    Write-Output "stopped $ns"
    Write-Output "workspace $($ctx.Workspace)"
    if ($ctx.HostRoot -ne $ctx.Workspace) { Write-Output "host $($ctx.HostRoot)" }
    Write-Output "watchman $watch"
    Write-Output "open-items $open"
    Write-Output 'deadline preserved'
}

function Reset-NSShift {
    param([Parameter(Mandatory = $true)][string]$Project)
    Stop-NSShift -Project $Project -Reason 'reset by owner'
    $ctx = Resolve-NSControlWorkspace $Project
    Remove-NSPath (Join-Path $ctx.NightshiftDir 'STOP')
    Remove-NSPath (Join-Path $ctx.NightshiftDir 'deadline')
    Remove-NSPath (Join-Path $ctx.NightshiftDir '.watch-reason')
    Write-NSControlLog $ctx.NightshiftDir 'reset by owner - runtime markers and deadline cleared'
    Write-Output "reset $($ctx.NightshiftDir)"
    Write-Output 'deadline removed'
}

function Remove-NSNightshiftWorkspace {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$ConfirmPath
    )
    $hostPath = Resolve-NSCanonicalPath $Project
    $workspace = $hostPath
    $link = Join-Path $hostPath '.nightshift-link'
    if (Test-NSPathEntry $link) {
        $workspace = Read-NSControlLink $hostPath
    }
    $nsCanon = Join-Path $workspace '.nightshift'
    if ((Test-Path -LiteralPath $nsCanon -PathType Container) -and -not (Test-NSReparsePoint $nsCanon)) {
        $nsCanon = Resolve-NSCanonicalPath $nsCanon
    }
    else {
        try { $nsCanon = Resolve-NSCanonicalPath $nsCanon } catch {
            $parent = Split-Path -Parent $nsCanon
            $nsCanon = Join-Path (Resolve-NSCanonicalPath $parent) (Split-Path -Leaf $nsCanon)
        }
    }
    $confirm = $ConfirmPath.TrimEnd('\', '/')
    try { $confirm = Resolve-NSCanonicalPath $ConfirmPath } catch {
        $parent = Split-Path -Parent $ConfirmPath
        $confirm = Join-Path (Resolve-NSCanonicalPath $parent) (Split-Path -Leaf $ConfirmPath)
    }
    $confirm = $confirm.TrimEnd('\', '/')
    $nsCanon = $nsCanon.TrimEnd('\', '/')
    if ($confirm -ne $nsCanon) {
        throw "purge-workspace: --confirm-path must be exactly $nsCanon"
    }
    if ((Test-NSBroadWorkspace $workspace) -or (Test-NSReparsePoint $nsCanon)) {
        throw "purge-workspace: refusing to delete $nsCanon"
    }
    if ((Test-Path -LiteralPath $nsCanon -PathType Container) -and -not (Test-NSReparsePoint $nsCanon)) {
        Reset-NSShift -Project $Project
    }
    if (Test-NSReparsePoint $nsCanon) {
        throw 'purge-workspace: .nightshift path is a symlink'
    }
    if (Test-Path -LiteralPath $nsCanon) {
        Remove-Item -LiteralPath $nsCanon -Recurse -Force
    }
    if (Test-NSPathEntry $link) {
        Remove-NSPath $link
    }
    Write-Output "purged $nsCanon"
    Write-Output 'plugin install was not touched'
}

function Test-NSTrustedShiftControl {
    param(
        [AllowEmptyString()][string]$Command,
        [Parameter(Mandatory = $true)][string]$PluginRoot,
        [Parameter(Mandatory = $true)][string]$Workspace
    )
    if ([string]::IsNullOrWhiteSpace($Command)) { return $false }
    if ($Command.Contains('$')) { return $false }
    if ($Command -match "[\r\n;|&``<>]") { return $false }
    $pluginRoot = Resolve-NSCanonicalPath $PluginRoot
    $workspace = Resolve-NSCanonicalPath $Workspace
    $normalized = $Command.Trim()
    foreach ($prefix in @('powershell.exe ', 'pwsh ', 'pwsh.exe ', '& ')) {
        if ($normalized.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $normalized = $normalized.Substring($prefix.Length).Trim()
        }
    }
    $normalized = $normalized -replace "^'", '' -replace "'$", '' -replace '^"', '' -replace '"$', ''
    # @() keeps a single regex hit as a one-element array; StrictMode rejects .Count on a bare string.
    $tokens = @([regex]::Matches($normalized, '(?:[^\s"]+|"[^"]*"|''[^'']*'')') | ForEach-Object { $_.Value.Trim("'`"") })
    if ($tokens.Count -lt 3) { return $false }
    $idx = 0
    if ($tokens[0] -in @('powershell', 'powershell.exe', 'pwsh', 'pwsh.exe', 'bash') -and $tokens.Count -ge 4) {
        if ($tokens[1] -in @('-File', '-Command', '--')) { $idx = 2 } else { $idx = 1 }
    }
    $script = $tokens[$idx]
    try { $script = Resolve-NSCanonicalPath $script } catch { return $false }
    $helpers = @(
        (Join-Path $pluginRoot 'runtime/windows/stop-shift.ps1'),
        (Join-Path $pluginRoot 'runtime/windows/reset-shift.ps1'),
        (Join-Path $pluginRoot 'runtime/windows/purge-workspace.ps1'),
        (Join-Path $pluginRoot 'runtime/stop-shift.sh'),
        (Join-Path $pluginRoot 'runtime/reset-shift.sh'),
        (Join-Path $pluginRoot 'runtime/purge-workspace.sh')
    )
    $ok = $false
    foreach ($h in $helpers) {
        try {
            if ((Resolve-NSCanonicalPath $h) -eq $script) { $ok = $true; break }
        }
        catch { }
    }
    if (-not $ok) { return $false }
    $project = ''
    $confirm = ''
    for ($i = $idx + 1; $i -lt $tokens.Count; $i++) {
        if ($tokens[$i] -in @('--project', '-Project') -and ($i + 1) -lt $tokens.Count) {
            $project = $tokens[$i + 1]
            $i++
            continue
        }
        if ($tokens[$i] -in @('--confirm-path', '-ConfirmPath') -and ($i + 1) -lt $tokens.Count) {
            $confirm = $tokens[$i + 1]
            $i++
            continue
        }
        if ($tokens[$i] -in @('--reason', '-Reason') -and ($i + 1) -lt $tokens.Count) {
            $i++
            continue
        }
        return $false
    }
    if ([string]::IsNullOrEmpty($project)) { return $false }
    if (-not [IO.Path]::IsPathRooted($project)) { return $false }
    try {
        $resolved = (Resolve-NSControlWorkspace $project).Workspace
    }
    catch { return $false }
    if ($resolved -ne $workspace) { return $false }
    $leaf = Split-Path -Leaf $script
    if ($leaf -like 'purge-workspace.*' -and [string]::IsNullOrEmpty($confirm)) { return $false }
    return $true
}

function New-NSShiftDecision {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Continue', 'Pass', 'Fail')][string]$Status,
        [AllowEmptyString()][string]$Message = '',
        $Session = $null
    )
    return [pscustomobject]@{
        Status  = $Status
        Message = $Message
        Session = $Session
    }
}

function Resolve-NSShiftUnbound {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [AllowEmptyString()][string]$Nonce = '',
        [AllowEmptyString()][string]$Generation = '',
        [bool]$Revival = $false,
        [Parameter(Mandatory = $true)][ValidateSet('hardhat', 'gate')][string]$Mode
    )
    $session = Read-NSSession $NightshiftDir
    $lease = Read-NSLease $NightshiftDir
    if ($null -eq $session -and $null -ne $lease -and -not [string]::IsNullOrEmpty($lease.Nonce)) {
        if (-not $Revival -or -not (Test-NSLeaseNonce $NightshiftDir $HostName $Nonce $Generation)) {
            if ($Mode -eq 'hardhat') {
                return New-NSShiftDecision -Status Fail -Message 'BLOCKED: this shift is being recovered before its new conversation is bound. Reopen the recorded conversation and retry after recovery.'
            }
            return New-NSShiftDecision -Status Pass
        }
    }
    return New-NSShiftDecision -Status Continue -Session $session
}

function Resolve-NSShiftRebind {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [AllowEmptyString()][string]$SessionId = '',
        [AllowEmptyString()][string]$Transcript = '',
        [AllowEmptyString()][string]$ProcessId = '',
        [AllowEmptyString()][string]$ProcessStart = '',
        [AllowEmptyString()][string]$Nonce = '',
        [AllowEmptyString()][string]$Generation = '',
        [bool]$Revival = $false,
        [Parameter(Mandatory = $true)][ValidateSet('hardhat', 'gate')][string]$Mode
    )
    $session = Read-NSSession $NightshiftDir
    if (-not $Revival) {
        return New-NSShiftDecision -Status Continue -Session $session
    }
    if (-not (Test-NSLeaseNonce $NightshiftDir $HostName $Nonce $Generation)) {
        if ($Mode -eq 'hardhat') {
            return New-NSShiftDecision -Status Fail -Message 'BLOCKED: this recovered worker no longer owns the shift. Reopen the recorded conversation instead of continuing an older process.'
        }
        return New-NSShiftDecision -Status Pass
    }
    if ([string]::IsNullOrEmpty($SessionId)) {
        return New-NSShiftDecision -Status Continue -Session $session
    }
    $lease = Read-NSLease $NightshiftDir
    if ($null -ne $lease -and [string]::IsNullOrEmpty($lease.SessionId) `
        -and -not (Bind-NSLeaseSession $NightshiftDir $SessionId $HostName $Nonce $Generation)) {
        if ($Mode -eq 'hardhat') {
            return New-NSShiftDecision -Status Fail -Message 'BLOCKED: the shift process lease could not bind the recovered conversation. Issue STOP from another session, then run Start again.'
        }
        return New-NSShiftDecision -Status Pass
    }
    if ($null -eq $session -or $session.SessionId -ne $SessionId -or $session.ProcessId -ne $ProcessId) {
        $oldTranscript = if ([string]::IsNullOrEmpty($Transcript) -and $null -ne $session) { $session.Transcript } else { $Transcript }
        if (-not (Write-NSSession $NightshiftDir $SessionId $oldTranscript $ProcessId $ProcessStart $HostName)) {
            if ($Mode -eq 'hardhat') {
                return New-NSShiftDecision -Status Fail -Message 'BLOCKED: the recovered conversation could not update .shift-session. Issue STOP from another session, then run Start again.'
            }
            return New-NSShiftDecision -Status Pass
        }
    }
    $lease = Read-NSLease $NightshiftDir
    if ($null -ne $lease -and -not [string]::IsNullOrEmpty($ProcessId) -and $lease.ProcessId -ne $ProcessId `
        -and -not (Attach-NSLeaseProcess $NightshiftDir $HostName $Nonce $Generation $ProcessId $ProcessStart)) {
        if ($Mode -eq 'hardhat') {
            return New-NSShiftDecision -Status Fail -Message 'BLOCKED: the recovered process could not refresh its shift lease. Reopen the recorded conversation.'
        }
        return New-NSShiftDecision -Status Pass
    }
    return New-NSShiftDecision -Status Continue -Session (Read-NSSession $NightshiftDir)
}

function Resolve-NSShiftAuthorize {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [AllowEmptyString()][string]$SessionId = '',
        [AllowEmptyString()][string]$ProcessId = '',
        [AllowEmptyString()][string]$ProcessStart = '',
        [AllowEmptyString()][string]$Nonce = '',
        [AllowEmptyString()][string]$Generation = '',
        [bool]$Revival = $false,
        [Parameter(Mandatory = $true)][ValidateSet('hardhat', 'gate')][string]$Mode,
        $Session = $null
    )
    if ($null -eq $Session) {
        $Session = Read-NSSession $NightshiftDir
    }
    $lease = Read-NSLease $NightshiftDir
    $leaseScope = if ($null -eq $lease) { '' } else { $lease.SessionId }
    if ($null -ne $Session -and -not [string]::IsNullOrEmpty($SessionId) `
        -and $SessionId -ne $Session.SessionId -and $SessionId -ne $leaseScope -and -not $Revival) {
        return New-NSShiftDecision -Status Pass -Session $Session
    }
    if ($null -eq $Session) {
        return New-NSShiftDecision -Status Continue
    }
    $leasePath = Join-Path $NightshiftDir '.shift-lease'
    if (-not (Test-NSPathEntry $leasePath) `
        -and -not (Claim-NSInitialLease $NightshiftDir $Session.SessionId $HostName $ProcessId $ProcessStart)) {
        if ($Mode -eq 'hardhat') {
            return New-NSShiftDecision -Status Fail -Session $Session -Message 'BLOCKED: the shift process lease could not be created. Issue STOP from another session, then run Start again.'
        }
        return New-NSShiftDecision -Status Fail -Session $Session -Message 'DO NOT STOP - the shift process lease is unreadable. Issue STOP from another session, then run Start again.'
    }
    elseif ($HostName -eq 'cursor') {
        $contaminated = Read-NSLease $NightshiftDir
        if ($null -ne $contaminated `
            -and $contaminated.HostName -eq 'claude' `
            -and $contaminated.SessionId -eq $Session.SessionId `
            -and [string]::IsNullOrEmpty($contaminated.Nonce) `
            -and [string]::IsNullOrEmpty($Nonce)) {
            if (-not (Write-NSLease $NightshiftDir $Session.SessionId 'cursor' 1 '' $ProcessId $ProcessStart)) {
                if ($Mode -eq 'hardhat') {
                    return New-NSShiftDecision -Status Fail -Session $Session -Message 'BLOCKED: the shift process lease could not be reclaimed for Cursor. Issue STOP from another session, then run Start again.'
                }
                return New-NSShiftDecision -Status Fail -Session $Session -Message 'DO NOT STOP - the shift process lease could not be reclaimed for Cursor. Issue STOP from another session, then run Start again.'
            }
        }
    }
    $checkSession = if ([string]::IsNullOrEmpty($SessionId)) { $Session.SessionId } else { $SessionId }
    $allow = Test-NSLeaseAllows $NightshiftDir $checkSession $HostName $ProcessId $ProcessStart $Nonce $Generation
    if ($allow -eq 'Deny') {
        if ($Mode -eq 'hardhat') {
            $held = Read-NSLease $NightshiftDir
            if ($null -ne $held -and -not [string]::IsNullOrEmpty($held.Nonce) `
                -and -not [string]::IsNullOrEmpty($held.ProcessId) `
                -and (Test-NSRecordedProcess $held.ProcessId $held.Start) -eq 'Alive') {
                return New-NSShiftDecision -Status Fail -Session $Session -Message 'BLOCKED: this shift is being recovered in another process. Wait or issue STOP from a separate session; reopening the recorded conversation stays blocked while that worker holds the lease.'
            }
            return New-NSShiftDecision -Status Fail -Session $Session -Message 'BLOCKED: this shift continued in a recovered process. Reopen the recorded conversation before using tools here.'
        }
        return New-NSShiftDecision -Status Pass -Session $Session
    }
    if ($allow -ne 'Allow') {
        if ($Mode -eq 'hardhat') {
            return New-NSShiftDecision -Status Fail -Session $Session -Message 'BLOCKED: this shift continued in a recovered process. Reopen the recorded conversation before using tools here.'
        }
        return New-NSShiftDecision -Status Fail -Session $Session -Message 'DO NOT STOP - the shift process lease is unreadable. Issue STOP from another session, then run Start again.'
    }
    if (-not $Revival -and -not [string]::IsNullOrEmpty($ProcessId)) {
        $lease = Read-NSLease $NightshiftDir
        if ($null -ne $lease -and $lease.ProcessId -eq $ProcessId -and $Session.ProcessId -ne $ProcessId) {
            if (-not (Write-NSSession $NightshiftDir $Session.SessionId $Session.Transcript $ProcessId $ProcessStart $HostName)) {
                if ($Mode -eq 'hardhat') {
                    return New-NSShiftDecision -Status Fail -Session $Session -Message 'BLOCKED: the reclaimed interactive process could not refresh .shift-session. Issue STOP from another session, then run Start again.'
                }
                return New-NSShiftDecision -Status Fail -Session $Session -Message 'DO NOT STOP - the reclaimed process could not refresh .shift-session. Issue STOP from another session, then run Start again.'
            }
            $Session = Read-NSSession $NightshiftDir
        }
    }
    return New-NSShiftDecision -Status Continue -Session $Session
}

function Resolve-NSShiftOwnership {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][ValidateSet('claude', 'codex', 'cursor')][string]$HostName,
        [AllowEmptyString()][string]$SessionId = '',
        [AllowEmptyString()][string]$Transcript = '',
        [AllowEmptyString()][string]$ProcessId = '',
        [AllowEmptyString()][string]$ProcessStart = '',
        [AllowEmptyString()][string]$Nonce = '',
        [AllowEmptyString()][string]$Generation = '',
        [bool]$Revival = $false,
        [Parameter(Mandatory = $true)][ValidateSet('hardhat', 'gate')][string]$Mode
    )
    $rebind = Resolve-NSShiftRebind -NightshiftDir $NightshiftDir -HostName $HostName `
        -SessionId $SessionId -Transcript $Transcript -ProcessId $ProcessId `
        -ProcessStart $ProcessStart -Nonce $Nonce -Generation $Generation `
        -Revival $Revival -Mode $Mode
    if ($rebind.Status -ne 'Continue') {
        return $rebind
    }
    return Resolve-NSShiftAuthorize -NightshiftDir $NightshiftDir -HostName $HostName `
        -SessionId $SessionId -ProcessId $ProcessId -ProcessStart $ProcessStart `
        -Nonce $Nonce -Generation $Generation -Revival $Revival -Mode $Mode `
        -Session $rebind.Session
}

function Write-NSReason {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][string]$Code,
        [AllowEmptyString()][string]$Detail = ''
    )
    $allowed = @(
        'completed', 'owner-stop', 'stale-pid', 'invalid-session', 'exhausted-retry',
        'unknown-wedge', 'revived', 'stand-down', 'wrong-host', 'deadline',
        'clean-session-end', 'esc-standby', 'silent-standby', 'non-resumable-session',
        'unreadable-rules', 'fresh-fallback', 'unsupported-state', 'process-evidence-unavailable',
        'clock-out-failed'
    )
    if ($Code -notin $allowed) {
        $Code = 'stand-down'
    }
    $Detail = ($Detail -replace '[\x00-\x1f]', '').TrimEnd()
    $null = Write-NSAtomicLines -Path (Join-Path $NightshiftDir '.watch-reason') -Lines @($Code, $Detail)
}

function Get-NSUnixTime {
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Get-NSPulseEpoch {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $path = Join-Path $NightshiftDir '.shift-pulse'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-NSReparsePoint $path)) {
        return $null
    }
    try {
        $line = ([IO.File]::ReadAllLines($path) | Select-Object -First 1)
    }
    catch {
        return $null
    }
    if ([string]::IsNullOrWhiteSpace($line)) {
        return $null
    }
    $epoch = ($line -split ' ', 2)[0]
    if ($epoch -notmatch '^[0-9]+$') {
        return $null
    }
    return [long]$epoch
}

function Test-NSPulseFresh {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][int]$IntervalMinutes
    )
    $epoch = Get-NSPulseEpoch $NightshiftDir
    if ($null -eq $epoch) {
        return $false
    }
    $window = [long]$IntervalMinutes * 120
    return ((Get-NSUnixTime) - $epoch) -lt $window
}

function Test-NSPulseStale {
    param(
        [Parameter(Mandatory = $true)][string]$NightshiftDir,
        [Parameter(Mandatory = $true)][int]$IntervalMinutes,
        [long]$Clock = 0
    )
    $window = [long]$IntervalMinutes * 120
    $now = Get-NSUnixTime
    $epoch = Get-NSPulseEpoch $NightshiftDir
    if ($null -ne $epoch) {
        return ($now - $epoch) -ge $window
    }
    $armed = Join-Path $NightshiftDir '.shift-armed'
    if ((Test-Path -LiteralPath $armed -PathType Leaf) -and -not (Test-NSReparsePoint $armed)) {
        try {
            $Clock = [DateTimeOffset]::new((Get-Item -LiteralPath $armed).LastWriteTimeUtc).ToUnixTimeSeconds()
        }
        catch {
        }
    }
    if ($Clock -le 0) {
        $Clock = $now
    }
    return ($now - $Clock) -ge $window
}

function Test-NSLeasePidLive {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $lease = Read-NSLease $NightshiftDir
    if ($null -eq $lease -or [string]::IsNullOrEmpty([string]$lease.ProcessId)) {
        return $false
    }
    return (Test-NSRecordedProcess $lease.ProcessId $lease.Start) -eq 'Alive'
}


function Get-NSStateVersion {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $kind = Get-NSStateKind $Workspace
    switch ($kind) {
        'absent' { return '' }
        'legacy' { return '0' }
        'current' { return [string]$script:NSStateVersion }
        'future' {
            try {
                $raw = ([IO.File]::ReadAllLines((Join-Path $Workspace '.nightshift/state-version')) | Select-Object -First 1)
                return ([string]$raw).Trim()
            }
            catch {
                return ''
            }
        }
        default { return '' }
    }
}

function Invoke-NSMigrateState {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $kind = Get-NSStateKind $Workspace
    if ($kind -eq 'current') {
        return 0
    }
    if ($kind -ne 'legacy') {
        return 2
    }
    if (Test-Path -LiteralPath (Join-Path $Workspace '.nightshift/.shift-armed') -PathType Leaf) {
        return 1
    }
    try {
        $null = Write-NSAtomicLines -Path (Join-Path $Workspace '.nightshift/state-version') `
            -Lines @([string]$script:NSStateVersion)
        return 0
    }
    catch {
        return 3
    }
}

function Get-NSReasonCode {
    param([Parameter(Mandatory = $true)][string]$NightshiftDir)
    $path = Join-Path $NightshiftDir '.watch-reason'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return ''
    }
    try {
        $line = ([IO.File]::ReadAllLines($path) | Select-Object -First 1)
        return (([string]$line) -replace '\s', '')
    }
    catch {
        return ''
    }
}

function Get-NSReasonLabel {
    param([AllowEmptyString()][string]$Code)
    switch ($Code) {
        'completed' { return 'shift completed' }
        'owner-stop' { return 'owner stop-work order' }
        'stale-pid' { return 'recorded process is stale' }
        'invalid-session' { return 'session identity is missing or unreadable' }
        'exhausted-retry' { return 'revival retries exhausted this wake' }
        'unknown-wedge' { return 'session looks wedged without a verified error signature' }
        'revived' { return 'session revived into its own conversation' }
        'stand-down' { return 'watchman stood down' }
        'wrong-host' { return 'watchman stood down - shift belongs to another host' }
        'deadline' { return 'quitting time passed' }
        'clean-session-end' { return 'owner closed the session' }
        'esc-standby' { return 'standing by - owner interrupt in the transcript' }
        'silent-standby' { return 'standing by - session alive and quiet' }
        'non-resumable-session' { return 'recorded Codex identity cannot be resumed' }
        'unreadable-rules' { return 'rules file missing or incomplete' }
        'fresh-fallback' { return 'fresh session - punch list is the handover' }
        'unsupported-state' { return 'workspace state-version is unsupported' }
        'process-evidence-unavailable' { return 'process evidence is unavailable' }
        'clock-out-failed' { return 'terminal clock-out failed without releasing the shift' }
        default { return 'unknown watchman outcome' }
    }
}

function Get-NSRetentionDays {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][ValidateSet('runtimeLogDays', 'archiveDays')][string]$Key
    )
    $envName = if ($Key -eq 'runtimeLogDays') {
        'NIGHTSHIFT_RETENTION_RUNTIME_LOG_DAYS'
    }
    else {
        'NIGHTSHIFT_RETENTION_ARCHIVE_DAYS'
    }
    $override = [Environment]::GetEnvironmentVariable($envName)
    if ($override -match '^[0-9]+$') {
        return [int]$override
    }
    $rules = Get-NSRulesObject $Workspace
    if ($null -eq $rules) {
        return 0
    }
    $retention = $rules.PSObject.Properties['retention']
    if ($null -eq $retention -or $null -eq $retention.Value) {
        return 0
    }
    $property = $retention.Value.PSObject.Properties[$Key]
    if ($null -eq $property -or $null -eq $property.Value) {
        return 0
    }
    $raw = [string]$property.Value
    if ($raw -notmatch '^[0-9]+$') {
        return 0
    }
    return [int]$raw
}

function Resolve-NSUnderNightshift {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Relative
    )
    if ([string]::IsNullOrEmpty($Relative) -or $Relative.Contains('..') `
        -or [IO.Path]::IsPathRooted($Relative)) {
        return $null
    }
    $ns = Join-Path $Workspace '.nightshift'
    try {
        $root = Resolve-NSCanonicalPath $ns
    }
    catch {
        return $null
    }
    $candidate = Join-Path $ns ($Relative -replace '/', [string][IO.Path]::DirectorySeparatorChar)
    if (-not (Test-NSPathEntry $candidate) -or (Test-NSReparsePoint $candidate)) {
        return $null
    }
    try {
        $canon = Resolve-NSCanonicalPath $candidate
    }
    catch {
        return $null
    }
    $prefix = $root.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($canon.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        return $canon
    }
    return $null
}

function Test-NSArchiveHasOpenWork {
    param([Parameter(Mandatory = $true)][string]$Directory)
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $false
    }
    $armed = Join-Path $Directory '.shift-armed'
    if ((Test-NSPathEntry $armed)) {
        return $true
    }
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Force -ErrorAction SilentlyContinue)) {
        if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            continue
        }
        if ($file.Name -in @('punch-list.md', 'shipped.md')) {
            $counts = Get-NSBoxCounts $file.FullName
            if ($counts.Open -gt 0) {
                return $true
            }
        }
    }
    return $false
}

function Get-NSRetentionEligible {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $ns = Join-Path $Workspace '.nightshift'
    $rows = [Collections.Generic.List[psobject]]::new()
    if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
        return @($rows)
    }
    $now = [DateTime]::UtcNow
    $logDays = Get-NSRetentionDays $Workspace 'runtimeLogDays'
    $archDays = Get-NSRetentionDays $Workspace 'archiveDays'

    if ($logDays -gt 0) {
        $logPath = Resolve-NSUnderNightshift $Workspace 'scheduled.log'
        if (-not [string]::IsNullOrEmpty($logPath) -and (Test-Path -LiteralPath $logPath -PathType Leaf)) {
            $age = [int](($now - (Get-Item -LiteralPath $logPath).LastWriteTimeUtc).TotalDays)
            if ($age -ge $logDays) {
                $null = $rows.Add([pscustomobject]@{ Kind = 'runtime-log'; Rel = 'scheduled.log'; Age = $age; Days = $logDays })
            }
        }
    }

    if ($archDays -le 0) {
        return @($rows)
    }
    $archiveRoot = Join-Path $ns 'archive'
    if (-not (Test-Path -LiteralPath $archiveRoot -PathType Container) -or (Test-NSReparsePoint $archiveRoot)) {
        return @($rows)
    }
    foreach ($dir in @(Get-ChildItem -LiteralPath $archiveRoot -Directory -ErrorAction SilentlyContinue)) {
        if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            continue
        }
        if ($dir.Name -notmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') {
            continue
        }
        $rel = 'archive/' + $dir.Name
        $path = Resolve-NSUnderNightshift $Workspace $rel
        if ([string]::IsNullOrEmpty($path)) {
            continue
        }
        if (Test-NSArchiveHasOpenWork $path) {
            continue
        }
        $age = [int](($now - (Get-Item -LiteralPath $path).LastWriteTimeUtc).TotalDays)
        if ($age -ge $archDays) {
            $null = $rows.Add([pscustomobject]@{ Kind = 'archive'; Rel = $rel; Age = $age; Days = $archDays })
        }
    }
    return @($rows)
}

function Invoke-NSRetentionApply {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $ns = Join-Path $Workspace '.nightshift'
    if (-not (Test-Path -LiteralPath $ns -PathType Container)) {
        return 2
    }
    if (Test-Path -LiteralPath (Join-Path $ns '.shift-armed') -PathType Leaf) {
        return 1
    }
    foreach ($row in @(Get-NSRetentionEligible $Workspace)) {
        $path = Resolve-NSUnderNightshift $Workspace $row.Rel
        if ([string]::IsNullOrEmpty($path)) {
            return 2
        }
        if ($row.Kind -eq 'runtime-log') {
            if (-not (Test-Path -LiteralPath $path -PathType Leaf) -or (Test-NSReparsePoint $path)) {
                return 2
            }
            Remove-NSFile $path
        }
        elseif ($row.Kind -eq 'archive') {
            if (-not (Test-Path -LiteralPath $path -PathType Container) -or (Test-NSReparsePoint $path)) {
                return 2
            }
            if (Test-NSArchiveHasOpenWork $path) {
                return 2
            }
            try {
                Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
            }
            catch {
                return 2
            }
        }
        else {
            return 2
        }
    }
    return 0
}

function Test-NSSecretLine {
    param([AllowEmptyString()][string]$Text)
    if ($Text -match '(?i)(password|passwd|secret|token|api[_-]?key|authorization|bearer|credential)\s*[=:]') {
        return $true
    }
    if ($Text -match '://[^/@\s]+:[^/@\s]+@') {
        return $true
    }
    if ($Text -match '(?i)[?&](token|key|secret|password|auth|access_token)=') {
        return $true
    }
    return $false
}

function Convert-NSTokenizedText {
    param(
        [AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$HomeRoot = '',
        [AllowEmptyString()][string]$Workspace = '',
        [AllowEmptyString()][string]$Target = ''
    )
    $out = $Text
    foreach ($pair in @(
            @{ From = $Target; To = '$WORK_TARGET' },
            @{ From = $Workspace; To = '$WORKSPACE' },
            @{ From = $HomeRoot; To = '$HOME' }
        )) {
        if ([string]::IsNullOrEmpty($pair.From)) {
            continue
        }
        $out = $out.Replace($pair.From, $pair.To)
        $slash = $pair.From.Replace('\', '/')
        if ($slash -ne $pair.From) {
            $out = $out.Replace($slash, $pair.To)
        }
    }
    if ($out -match '(^|[\s=])(/|file://|[A-Za-z]:[\\/])') {
        return $null
    }
    return $out
}

function Convert-NSSanitizedLine {
    param(
        [AllowEmptyString()][string]$Text,
        [AllowEmptyString()][string]$HomeRoot = '',
        [AllowEmptyString()][string]$Workspace = '',
        [AllowEmptyString()][string]$Target = ''
    )
    if (Test-NSSecretLine $Text) {
        return $null
    }
    return Convert-NSTokenizedText $Text $HomeRoot $Workspace $Target
}

function Expand-NSInjectedPaths {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [AllowEmptyString()][string]$Text
    )
    if ([string]::IsNullOrEmpty($Text)) {
        return $Text
    }
    $text = $Text.Replace('$NIGHTSHIFT_WORKSPACE', $Workspace)
    $nsRoot = $Workspace.TrimEnd('\', '/') + '/.nightshift'
    $text = $text.Replace('$NS', $nsRoot)
    $root = $Workspace.TrimEnd('\', '/')
    $builder = New-Object Text.StringBuilder
    $i = 0
    while ($i -lt $text.Length) {
        $idx = $text.IndexOf('.nightshift', $i, [StringComparison]::Ordinal)
        if ($idx -lt 0) {
            $null = $builder.Append($text.Substring($i))
            break
        }
        $after = if (($idx + 11) -lt $text.Length) { $text[$idx + 11] } else { [char]0 }
        $sepOk = ($after -eq [char]'/' -or $after -eq [char]'\')
        $prev = if ($idx -gt 0) { $text[$idx - 1] } else { [char]0 }
        $already = ($prev -eq [char]'/' -or $prev -eq [char]'\')
        $null = $builder.Append($text.Substring($i, $idx - $i))
        if ($sepOk -and -not $already) {
            $null = $builder.Append($root)
            $null = $builder.Append('/')
            $null = $builder.Append('.nightshift')
            $null = $builder.Append($after)
            $i = $idx + 12
        }
        else {
            $null = $builder.Append('.nightshift')
            $i = $idx + 11
        }
    }
    return $builder.ToString()
}

function Copy-NSOwnerTemplate {
    param(
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][string]$Destination,
        [Parameter(Mandatory = $true)][string]$Workspace
    )
    $text = [IO.File]::ReadAllText($Source)
    $text = $text.Replace('$NIGHTSHIFT_WORKSPACE', $Workspace)
    $ns = Join-Path $Workspace.TrimEnd('\', '/') '.nightshift'
    $text = $text.Replace('$NS', $ns)
    [IO.File]::WriteAllText($Destination, $text, $script:NSUtf8NoBom)
}

Export-ModuleMember -Function *
