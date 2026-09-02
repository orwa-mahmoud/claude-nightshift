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
    # shift-defaults.json (remembered convenience) and rules.json (permanent boundaries) survive
    # a reset exactly like the punch list and parking lot do; only tonight's snapshot goes.
    Remove-NSPath (Join-Path $ctx.NightshiftDir 'shift-policy.json')
    Write-NSControlLog $ctx.NightshiftDir 'reset by owner - runtime markers, deadline, and shift policy cleared'
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

# --- capability detection -------------------------------------------------
# Native mirror of runtime/detect-capabilities.sh. Read-only: nothing below
# creates, moves, or deletes anything inside a scanned project.

function Sort-NSOrdinal {
    param([AllowNull()][AllowEmptyCollection()][string[]]$Items)
    $sorted = New-Object Collections.Generic.List[string]
    if ($null -ne $Items) {
        foreach ($item in $Items) {
            $sorted.Add($item)
        }
    }
    $sorted.Sort([StringComparer]::Ordinal)
    return , $sorted.ToArray()
}

function Get-NSAbsolutePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $candidate = $Path
    if (-not [IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path (Get-Location).ProviderPath $candidate
    }
    $full = [IO.Path]::GetFullPath($candidate)
    $sep = [IO.Path]::DirectorySeparatorChar
    while ($full.Length -gt 1 -and $full[$full.Length - 1] -eq $sep -and -not $full.EndsWith(':' + $sep, [StringComparison]::Ordinal)) {
        $full = $full.Substring(0, $full.Length - 1)
    }
    return $full
}

function Join-NSPath {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Base,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Name
    )
    if ([string]::IsNullOrEmpty($Base) -or [IO.Path]::IsPathRooted($Name)) {
        return $Name
    }
    $last = $Base[$Base.Length - 1]
    if ($last -eq [IO.Path]::DirectorySeparatorChar -or $last -eq [IO.Path]::AltDirectorySeparatorChar) {
        return ($Base + $Name)
    }
    return ($Base + [IO.Path]::DirectorySeparatorChar + $Name)
}

function Get-NSRelativePath {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Path
    )
    if ($Path -eq $Base) {
        return '.'
    }
    $prefix = $Base.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    foreach ($sep in @([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)) {
        $head = $prefix + $sep
        if ($Path.StartsWith($head, [StringComparison]::Ordinal)) {
            return $Path.Substring($head.Length)
        }
    }
    return $Path
}

# The canonical capability document: recursively sorted keys,
# two-space indent, "key": value, [] and {} for empties, \uXXXX for every
# character outside printable ASCII, no escaped slash, LF only. -Compact drops
# every newline and space, giving Python json.dumps(sort_keys=True,
# separators=(",", ":")) - the one-line form the evidence ledger stores.
function ConvertTo-NSJsonStringLiteral {
    param([AllowNull()][AllowEmptyString()][string]$Text)
    $builder = New-Object Text.StringBuilder
    $null = $builder.Append('"')
    if (-not [string]::IsNullOrEmpty($Text)) {
        foreach ($char in $Text.ToCharArray()) {
            $code = [int]$char
            if ($code -eq 34) { $null = $builder.Append('\"') }
            elseif ($code -eq 92) { $null = $builder.Append('\\') }
            elseif ($code -eq 8) { $null = $builder.Append('\b') }
            elseif ($code -eq 9) { $null = $builder.Append('\t') }
            elseif ($code -eq 10) { $null = $builder.Append('\n') }
            elseif ($code -eq 12) { $null = $builder.Append('\f') }
            elseif ($code -eq 13) { $null = $builder.Append('\r') }
            elseif ($code -lt 32 -or $code -gt 126) { $null = $builder.Append(('\u{0:x4}' -f $code)) }
            else { $null = $builder.Append($char) }
        }
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function Test-NSJsonInteger {
    param($Value)
    return ($Value -is [int] -or $Value -is [long] -or $Value -is [int16] -or $Value -is [byte] -or $Value -is [uint16] -or $Value -is [uint32] -or $Value -is [uint64] -or $Value -is [sbyte])
}

function Test-NSJsonFloat {
    param($Value)
    return ($Value -is [double] -or $Value -is [single] -or $Value -is [decimal])
}

# repr() of a Python float: shortest round-trip, and always a fractional part so
# 1.0 never collapses to 1.
function Format-NSJsonFloat {
    param($Value)
    $text = ([double]$Value).ToString('R', [Globalization.CultureInfo]::InvariantCulture)
    if ($text.IndexOf('.') -lt 0 -and $text.IndexOf('E') -lt 0 -and $text.IndexOf('e') -lt 0 -and $text.IndexOf('N') -lt 0 -and $text.IndexOf('I') -lt 0) {
        $text = $text + '.0'
    }
    return $text
}

function Write-NSCanonicalJsonValue {
    param(
        [Parameter(Mandatory = $true)]$Builder,
        $Value,
        [int]$Level = 0,
        [switch]$Compact
    )
    if ($null -eq $Value) {
        $null = $Builder.Append('null')
        return
    }
    if ($Value -is [bool]) {
        if ($Value) { $null = $Builder.Append('true') } else { $null = $Builder.Append('false') }
        return
    }
    if ($Value -is [string]) {
        $null = $Builder.Append((ConvertTo-NSJsonStringLiteral $Value))
        return
    }
    if (Test-NSJsonInteger $Value) {
        $null = $Builder.Append(([long]$Value).ToString([Globalization.CultureInfo]::InvariantCulture))
        return
    }
    if (Test-NSJsonFloat $Value) {
        $null = $Builder.Append((Format-NSJsonFloat $Value))
        return
    }
    $pad = ' ' * (2 * ($Level + 1))
    $tail = ' ' * (2 * $Level)
    $break = "`n"
    $colon = ': '
    if ($Compact) {
        $pad = ''
        $tail = ''
        $break = ''
        $colon = ':'
    }
    if ($Value -is [Collections.IDictionary]) {
        $keys = Sort-NSOrdinal (@($Value.Keys))
        if ($keys.Count -eq 0) {
            $null = $Builder.Append('{}')
            return
        }
        $null = $Builder.Append('{')
        $index = 0
        foreach ($key in $keys) {
            if ($index -gt 0) { $null = $Builder.Append(',') }
            $null = $Builder.Append($break)
            $null = $Builder.Append($pad)
            $null = $Builder.Append((ConvertTo-NSJsonStringLiteral $key))
            $null = $Builder.Append($colon)
            Write-NSCanonicalJsonValue $Builder $Value[$key] ($Level + 1) -Compact:$Compact
            $index++
        }
        $null = $Builder.Append($break)
        $null = $Builder.Append($tail)
        $null = $Builder.Append('}')
        return
    }
    if ($Value -is [Collections.IEnumerable]) {
        $items = @($Value)
        if ($items.Count -eq 0) {
            $null = $Builder.Append('[]')
            return
        }
        $null = $Builder.Append('[')
        $index = 0
        foreach ($item in $items) {
            if ($index -gt 0) { $null = $Builder.Append(',') }
            $null = $Builder.Append($break)
            $null = $Builder.Append($pad)
            Write-NSCanonicalJsonValue $Builder $item ($Level + 1) -Compact:$Compact
            $index++
        }
        $null = $Builder.Append($break)
        $null = $Builder.Append($tail)
        $null = $Builder.Append(']')
        return
    }
    $null = $Builder.Append((ConvertTo-NSJsonStringLiteral ([string]$Value)))
}

function ConvertTo-NSCanonicalJson {
    param([AllowNull()]$InputObject, [switch]$Compact)
    $builder = New-Object Text.StringBuilder
    Write-NSCanonicalJsonValue $builder $InputObject 0 -Compact:$Compact
    return $builder.ToString()
}

function Get-NSSchemaDocument {
    param([Parameter(Mandatory = $true)][string]$Name)
    $dir = Join-Path (Split-Path -Parent $PSScriptRoot) 'skills/nightshift/references/schemas/v1'
    $raw = [IO.File]::ReadAllText((Join-Path $dir $Name))
    return ($raw | ConvertFrom-Json)
}

function Get-NSJsonProperty {
    param($Object, [Parameter(Mandatory = $true)][string]$Name)
    if ($null -eq $Object) {
        return $null
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function New-NSCapabilityResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [AllowEmptyString()][string]$Reason,
        [AllowEmptyString()][string]$Locator,
        [string]$EvidenceLadder = 'observed'
    )
    return [ordered]@{
        status         = $Status
        reason         = $Reason
        locator        = $Locator
        evidenceLadder = $EvidenceLadder
    }
}

function Test-NSExecutableFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (Test-NSWindows) {
        return $true
    }
    try {
        $mode = [IO.File]::GetUnixFileMode($Path)
        $bits = [IO.UnixFileMode]::UserExecute -bor [IO.UnixFileMode]::GroupExecute -bor [IO.UnixFileMode]::OtherExecute
        return ([int]($mode -band $bits) -ne 0)
    }
    catch {
        return $false
    }
}

function Find-NSCommandPath {
    param(
        [AllowNull()][AllowEmptyString()][string]$Command,
        [AllowNull()][AllowEmptyString()][string]$SearchPath
    )
    if ([string]::IsNullOrEmpty($Command) -or $Command.StartsWith('-', [StringComparison]::Ordinal)) {
        return $null
    }
    if ([string]::IsNullOrEmpty($SearchPath)) {
        return $null
    }
    foreach ($directory in $SearchPath.Split([IO.Path]::PathSeparator)) {
        if ([string]::IsNullOrEmpty($directory)) {
            continue
        }
        $candidate = Join-NSPath $directory $Command
        if ((Test-Path -LiteralPath $candidate -PathType Leaf) -and (Test-NSExecutableFile $candidate)) {
            return $candidate
        }
        if (Test-NSWindows) {
            foreach ($ext in @('.exe', '.cmd', '.bat')) {
                $alt = $candidate + $ext
                if (Test-Path -LiteralPath $alt -PathType Leaf) {
                    return $alt
                }
            }
        }
    }
    return $null
}

# Runs "<path> --version" and nothing else. Never the tool's real work command.
function Invoke-NSVersionProbe {
    param([Parameter(Mandatory = $true)][string]$Path)
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Path
    $info.Arguments = '--version'
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $utf8 = New-Object Text.UTF8Encoding($false)
    $info.StandardOutputEncoding = $utf8
    $info.StandardErrorEncoding = $utf8
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $info
    try {
        $null = $process.Start()
    }
    catch {
        $process.Dispose()
        return @{ Status = 'available-but-failing'; Detail = $_.Exception.Message }
    }
    $outTask = $process.StandardOutput.ReadToEndAsync()
    $errTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    $text = $outTask.GetAwaiter().GetResult() + $errTask.GetAwaiter().GetResult()
    $code = $process.ExitCode
    $process.Dispose()
    $trimmed = $text.Trim()
    $first = ''
    if ($trimmed.Length -gt 0) {
        $first = ($trimmed -split "`r`n|`n|`r", 2)[0]
    }
    if ($first.Length -gt 200) {
        $first = $first.Substring(0, 200)
    }
    if ($code -eq 0) {
        return @{ Status = 'available-and-verified'; Detail = $first }
    }
    return @{ Status = 'available-but-failing'; Detail = ('exit {0}: {1}' -f $code, $first) }
}

function Get-NSCommandProbeResult {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [AllowNull()][AllowEmptyString()][string]$SearchPath,
        [AllowEmptyString()][string]$Locator
    )
    $path = Find-NSCommandPath $Command $SearchPath
    if ([string]::IsNullOrEmpty($path)) {
        return (New-NSCapabilityResult 'unavailable' ('command {0} is not on PATH' -f $Command) $Locator 'observed')
    }
    $probe = Invoke-NSVersionProbe $path
    $detail = $probe['Detail']
    if ([string]::IsNullOrEmpty($detail)) {
        $detail = 'no version text'
    }
    $ladder = 'observed'
    if ($probe['Status'] -ceq 'available-and-verified') {
        $ladder = 'measured'
    }
    return (New-NSCapabilityResult $probe['Status'] ('{0} -> {1} ({2})' -f $Command, $path, $detail) $path $ladder)
}

# One directory listing: child directory names, which of them are links (never
# descended, matching os.walk), and file names. Both lists ordinal sorted.
function Get-NSDirectoryEntries {
    param([Parameter(Mandatory = $true)][string]$Path)
    $dirs = New-Object Collections.Generic.List[string]
    $links = New-Object Collections.Generic.List[string]
    $files = New-Object Collections.Generic.List[string]
    $items = @()
    try {
        $items = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    }
    catch {
        $items = @()
    }
    foreach ($item in $items) {
        if ($item.PSIsContainer) {
            $dirs.Add($item.Name)
            if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                $links.Add($item.Name)
            }
        }
        else {
            $files.Add($item.Name)
        }
    }
    return @{
        Dirs  = (Sort-NSOrdinal $dirs.ToArray())
        Links = $links.ToArray()
        Files = (Sort-NSOrdinal $files.ToArray())
    }
}

function Get-NSArtifactCapabilities {
    param([Parameter(Mandatory = $true)][string]$Target)
    $markdown = New-Object Collections.Generic.List[string]
    $html = New-Object Collections.Generic.List[string]
    $pending = New-Object Collections.Generic.List[string]
    $pending.Add($Target)
    while ($pending.Count -gt 0) {
        $dir = $pending[0]
        $pending.RemoveAt(0)
        $entries = Get-NSDirectoryEntries $dir
        $slot = 0
        foreach ($name in $entries['Dirs']) {
            if ($name -ceq '.git' -or $name -ceq 'node_modules') {
                continue
            }
            if ($entries['Links'] -ccontains $name) {
                continue
            }
            $pending.Insert($slot, (Join-NSPath $dir $name))
            $slot++
        }
        foreach ($name in $entries['Files']) {
            $lower = $name.ToLowerInvariant()
            if ($lower.EndsWith('.md', [StringComparison]::Ordinal) -or $lower.EndsWith('.markdown', [StringComparison]::Ordinal)) {
                $markdown.Add((Join-NSPath $dir $name))
            }
            elseif ($lower.EndsWith('.html', [StringComparison]::Ordinal) -or $lower.EndsWith('.htm', [StringComparison]::Ordinal)) {
                $html.Add((Join-NSPath $dir $name))
            }
        }
        if (($markdown.Count + $html.Count) -gt 40) {
            break
        }
    }
    $caps = New-Object -TypeName Collections.Specialized.OrderedDictionary -ArgumentList ([StringComparer]::Ordinal)
    if ($markdown.Count -gt 0) {
        $caps['local-markdown'] = New-NSCapabilityResult 'available-and-verified' ('{0} markdown files' -f $markdown.Count) $markdown[0] 'observed'
        $caps['source-export'] = New-NSCapabilityResult 'available-and-verified' 'local files can be cited' $markdown[0] 'observed'
    }
    else {
        $caps['local-markdown'] = New-NSCapabilityResult 'unavailable' 'no markdown files' $Target 'observed'
        $caps['source-export'] = New-NSCapabilityResult 'unavailable' 'no local source files' $Target 'observed'
    }
    if ($html.Count -gt 0) {
        $caps['local-html'] = New-NSCapabilityResult 'available-and-verified' ('{0} html files' -f $html.Count) $html[0] 'observed'
    }
    else {
        $caps['local-html'] = New-NSCapabilityResult 'unavailable' 'no html files' $Target 'observed'
    }
    return $caps
}

function Get-NSScanFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Name
    )
    $hits = New-Object Collections.Generic.List[string]
    $pruned = @('.git', 'node_modules', 'vendor', 'target')
    $pending = New-Object Collections.Generic.List[string]
    $pending.Add($Root)
    while ($pending.Count -gt 0) {
        $dir = $pending[0]
        $pending.RemoveAt(0)
        $entries = Get-NSDirectoryEntries $dir
        $slot = 0
        foreach ($child in $entries['Dirs']) {
            if ($pruned -ccontains $child) {
                continue
            }
            if ($entries['Links'] -ccontains $child) {
                continue
            }
            $pending.Insert($slot, (Join-NSPath $dir $child))
            $slot++
        }
        foreach ($file in $entries['Files']) {
            if ($file -ceq $Name) {
                $hits.Add((Join-NSPath $dir $file))
            }
        }
        if ($hits.Count -ge 20) {
            break
        }
    }
    return , $hits.ToArray()
}

# Root plus immediate child dirs that carry a package signal. Symlinked
# children are skipped, exactly as the lstat check in the reference does.
function Get-NSPackageList {
    param([Parameter(Mandatory = $true)][string]$Target)
    $found = New-Object Collections.Generic.List[string]
    $found.Add($Target)
    $items = @()
    try {
        $items = @(Get-ChildItem -LiteralPath $Target -Force -ErrorAction Stop)
    }
    catch {
        return , $found.ToArray()
    }
    $byName = New-Object -TypeName 'Collections.Generic.Dictionary[string,object]' -ArgumentList ([StringComparer]::Ordinal)
    foreach ($item in $items) {
        $byName[$item.Name] = $item
    }
    $signals = @(
        'package.json',
        'pyproject.toml',
        'requirements.txt',
        'go.mod',
        'Cargo.toml',
        'Makefile',
        '.claude-plugin',
        '.codex-plugin'
    )
    foreach ($name in (Sort-NSOrdinal (@($byName.Keys)))) {
        if ($name.StartsWith('.', [StringComparison]::Ordinal)) {
            continue
        }
        $item = $byName[$name]
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            continue
        }
        if (-not $item.PSIsContainer) {
            continue
        }
        $path = Join-NSPath $Target $name
        foreach ($signal in $signals) {
            if (Test-Path -LiteralPath (Join-NSPath $path $signal)) {
                $found.Add($path)
                break
            }
        }
    }
    return , $found.ToArray()
}

function Get-NSPackageStacks {
    param([Parameter(Mandatory = $true)][string]$Package)
    $stacks = New-Object Collections.Generic.List[string]
    if (Test-Path -LiteralPath (Join-NSPath $Package 'package.json') -PathType Leaf) {
        $stacks.Add('javascript-typescript')
    }
    if ((Test-Path -LiteralPath (Join-NSPath $Package 'pyproject.toml') -PathType Leaf) -or (Test-Path -LiteralPath (Join-NSPath $Package 'requirements.txt') -PathType Leaf)) {
        $stacks.Add('python')
    }
    if (Test-Path -LiteralPath (Join-NSPath $Package 'go.mod') -PathType Leaf) {
        $stacks.Add('go')
    }
    if (Test-Path -LiteralPath (Join-NSPath $Package 'Cargo.toml') -PathType Leaf) {
        $stacks.Add('rust')
    }
    $plugin = $false
    foreach ($rel in @('.claude-plugin', '.codex-plugin', 'plugins')) {
        if (Test-Path -LiteralPath (Join-NSPath $Package $rel)) {
            $plugin = $true
        }
    }
    if ($plugin) {
        $stacks.Add('shell-plugin')
    }
    if (Test-Path -LiteralPath (Join-NSPath $Package 'Makefile') -PathType Leaf) {
        $stacks.Add('make')
    }
    return , $stacks.ToArray()
}

function Get-NSPackageScriptNames {
    param([Parameter(Mandatory = $true)][string]$Package)
    $path = Join-NSPath $Package 'package.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return , @()
    }
    $data = $null
    try {
        $data = [IO.File]::ReadAllText($path) | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return , @()
    }
    $scripts = Get-NSJsonProperty $data 'scripts'
    if ($null -eq $scripts -or -not ($scripts -is [Management.Automation.PSCustomObject])) {
        return , @()
    }
    return , (Sort-NSOrdinal (@($scripts.PSObject.Properties.Name)))
}

function Get-NSMakefileTargets {
    param([Parameter(Mandatory = $true)][string]$Package)
    $path = Join-NSPath $Package 'Makefile'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        return , @()
    }
    $text = ''
    try {
        $text = [IO.File]::ReadAllText($path)
    }
    catch {
        return , @()
    }
    $names = New-Object Collections.Generic.List[string]
    foreach ($match in [regex]::Matches($text, '^([A-Za-z0-9][^:\n]*):', [Text.RegularExpressions.RegexOptions]::Multiline)) {
        $name = $match.Groups[1].Value
        if ($names -cnotcontains $name) {
            $names.Add($name)
        }
    }
    return , (Sort-NSOrdinal $names.ToArray())
}

function Get-NSOwnerGatesResult {
    param([Parameter(Mandatory = $true)][string]$Nightshift)
    $punch = Join-NSPath $Nightshift 'punch-list.md'
    if (-not (Test-Path -LiteralPath $punch -PathType Leaf)) {
        return (New-NSCapabilityResult 'unavailable' 'no punch-list.md' $punch 'declared')
    }
    $text = [IO.File]::ReadAllText($punch)
    if ($text.IndexOf('## Gates', [StringComparison]::Ordinal) -lt 0) {
        return (New-NSCapabilityResult 'unavailable' 'punch list has no Gates block' $punch 'declared')
    }
    return (New-NSCapabilityResult 'available-and-verified' 'owner Gates block present' $punch 'declared')
}

function Get-NSMergedCapability {
    param($Results)
    $rank = @{
        'available-and-verified' = 5
        'available-but-failing'  = 4
        'fallback-only'          = 3
        'provisionable'          = 2
        'unavailable'            = 1
    }
    $best = $null
    foreach ($item in $Results) {
        if ($null -eq $best -or $rank[$item['status']] -gt $rank[$best['status']]) {
            $best = $item
        }
    }
    if ($null -eq $best) {
        return (New-NSCapabilityResult 'unavailable' 'not probed' '' 'declared')
    }
    return $best
}

function Get-NSCommandProbeMap {
    $map = [ordered]@{}
    $map['lint'] = @(
        @{ Cmd = 'eslint'; Stack = 'javascript-typescript' },
        @{ Cmd = 'ruff'; Stack = 'python' },
        @{ Cmd = 'golangci-lint'; Stack = 'go' }
    )
    $map['typecheck'] = @(
        @{ Cmd = 'tsc'; Stack = 'javascript-typescript' },
        @{ Cmd = 'mypy'; Stack = 'python' }
    )
    $map['test'] = @(
        @{ Cmd = 'node'; Stack = 'javascript-typescript' },
        @{ Cmd = 'pytest'; Stack = 'python' },
        @{ Cmd = 'go'; Stack = 'go' },
        @{ Cmd = 'cargo'; Stack = 'rust' },
        @{ Cmd = 'bats'; Stack = 'shell-plugin' }
    )
    $map['coverage'] = @(
        @{ Cmd = 'c8'; Stack = 'javascript-typescript' },
        @{ Cmd = 'pytest'; Stack = 'python' },
        @{ Cmd = 'go'; Stack = 'go' }
    )
    $map['dead-code'] = @(
        @{ Cmd = 'knip'; Stack = 'javascript-typescript' },
        @{ Cmd = 'vulture'; Stack = 'python' }
    )
    $map['build'] = @(
        @{ Cmd = 'tsc'; Stack = 'javascript-typescript' },
        @{ Cmd = 'go'; Stack = 'go' },
        @{ Cmd = 'cargo'; Stack = 'rust' }
    )
    $map['security'] = @(
        @{ Cmd = 'npm'; Stack = 'javascript-typescript' },
        @{ Cmd = 'pip-audit'; Stack = 'python' },
        @{ Cmd = 'govulncheck'; Stack = 'go' }
    )
    $map['documentation-link'] = @(
        @{ Cmd = 'markdown-link-check'; Stack = $null }
    )
    $map['accessibility'] = @(
        @{ Cmd = 'axe'; Stack = $null },
        @{ Cmd = 'pa11y'; Stack = $null }
    )
    $map['api-schema'] = @()
    $map['localization'] = @()
    $map['benchmark'] = @()
    $map['mutation-fuzz'] = @()
    $map['seo-performance'] = @()
    $map['browser'] = @(
        @{ Cmd = 'chrome'; Stack = $null },
        @{ Cmd = 'chromium'; Stack = $null }
    )
    $map['connector'] = @(
        @{ Cmd = 'gh'; Stack = $null }
    )
    $map['structured-results'] = @()
    return $map
}

function Get-NSRepositoryCapabilities {
    param(
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Nightshift,
        [AllowNull()][AllowEmptyString()][string]$SearchPath
    )
    $caps = Get-NSArtifactCapabilities $Target
    $packages = Get-NSPackageList $Target
    $stackSet = New-Object Collections.Generic.List[string]
    foreach ($package in $packages) {
        foreach ($stack in (Get-NSPackageStacks $package)) {
            if ($stackSet -cnotcontains $stack) {
                $stackSet.Add($stack)
            }
        }
    }
    $stacks = Sort-NSOrdinal $stackSet.ToArray()
    $topology = [ordered]@{
        root     = $Target
        packages = $packages
        monorepo = ($packages.Count -gt 1)
        stacks   = $stacks
    }

    $caps['owner-gates'] = Get-NSOwnerGatesResult $Nightshift

    $scripts = New-Object Collections.Generic.List[string]
    foreach ($package in $packages) {
        $relative = Get-NSRelativePath $Target $package
        foreach ($name in (Get-NSPackageScriptNames $package)) {
            $scripts.Add(('{0}:{1}' -f $relative, $name))
        }
        foreach ($name in (Get-NSMakefileTargets $package)) {
            $scripts.Add(('make:{0}' -f $name))
        }
    }
    if ($scripts.Count -gt 0) {
        $shown = New-Object Collections.Generic.List[string]
        $limit = [Math]::Min(12, $scripts.Count)
        for ($i = 0; $i -lt $limit; $i++) {
            $shown.Add($scripts[$i])
        }
        $caps['scripts'] = New-NSCapabilityResult 'available-and-verified' ('declared scripts: {0}' -f ($shown -join ', ')) $Target 'declared'
    }
    else {
        $caps['scripts'] = New-NSCapabilityResult 'unavailable' 'no package.json scripts or Makefile targets' $Target 'observed'
    }
    $caps['task-runner'] = $caps['scripts']

    $ciHits = New-Object Collections.Generic.List[string]
    foreach ($rel in @('.github/workflows', '.gitlab-ci.yml', 'azure-pipelines.yml')) {
        $path = Join-NSPath $Target $rel
        if (Test-Path -LiteralPath $path) {
            $ciHits.Add($path)
        }
    }
    if ($ciHits.Count -gt 0) {
        $caps['ci'] = New-NSCapabilityResult 'available-and-verified' 'CI config present' $ciHits[0] 'observed'
    }
    else {
        $caps['ci'] = New-NSCapabilityResult 'unavailable' 'no CI config' $Target 'observed'
    }

    # A package.json script name is a declaration, not proof of a binary; a
    # PATH binary is what earns "measured".
    $scriptHints = @{
        'test'      = 'test'
        'lint'      = 'lint'
        'typecheck' = 'typecheck'
        'coverage'  = 'coverage'
        'build'     = 'build'
    }

    $commandMap = Get-NSCommandProbeMap
    foreach ($cap in @($commandMap.Keys)) {
        $found = New-Object Collections.Generic.List[object]
        foreach ($probe in @($commandMap[$cap])) {
            $stack = $probe['Stack']
            if ($stack -and ($stacks -cnotcontains $stack) -and $cap -cne 'connector') {
                continue
            }
            $found.Add((Get-NSCommandProbeResult $probe['Cmd'] $SearchPath $Target))
        }
        if ($scriptHints.ContainsKey($cap)) {
            $key = $scriptHints[$cap]
            $declared = $false
            foreach ($package in $packages) {
                if ((Get-NSPackageScriptNames $package) -ccontains $key) {
                    $declared = $true
                    break
                }
            }
            if ($declared) {
                $found.Add((New-NSCapabilityResult 'available-and-verified' ('package.json scripts.{0} is declared; not proof of a binary' -f $key) (Join-NSPath $packages[0] 'package.json') 'declared'))
            }
        }
        if ($cap -eq 'test') {
            $hasTestTarget = $false
            foreach ($package in $packages) {
                if ((Get-NSMakefileTargets $package) -ccontains 'test') {
                    $hasTestTarget = $true
                    break
                }
            }
            if ($hasTestTarget) {
                $found.Add((New-NSCapabilityResult 'available-and-verified' 'Makefile test target declared' $Target 'declared'))
            }
        }
        if ($cap -eq 'structured-results') {
            $hits = New-Object Collections.Generic.List[string]
            foreach ($name in @('junit.xml', 'coverage.lcov', 'lcov.info')) {
                foreach ($hit in (Get-NSScanFiles $Target $name)) {
                    $hits.Add($hit)
                }
            }
            if ($hits.Count -gt 0) {
                $found.Add((New-NSCapabilityResult 'available-and-verified' 'structured result file present' $hits[0] 'observed'))
            }
        }
        if ($cap -eq 'api-schema') {
            foreach ($name in @('openapi.yaml', 'openapi.yml', 'openapi.json', 'schema.graphql')) {
                $path = Join-NSPath $Target $name
                if (Test-Path -LiteralPath $path -PathType Leaf) {
                    $found.Add((New-NSCapabilityResult 'available-and-verified' 'schema file present' $path 'observed'))
                }
            }
        }
        if ($cap -eq 'localization') {
            foreach ($rel in @('locales', 'i18n', 'translations')) {
                $path = Join-NSPath $Target $rel
                if (Test-Path -LiteralPath $path -PathType Container) {
                    $found.Add((New-NSCapabilityResult 'available-and-verified' 'locale directory present' $path 'observed'))
                }
            }
        }
        $caps[$cap] = Get-NSMergedCapability $found
    }

    return @{ Capabilities = $caps; Topology = $topology }
}

function Get-NSContractEvaluation {
    param(
        $Requirement,
        $Capabilities,
        [Parameter(Mandatory = $true)][string]$WorkMode
    )
    $fallback = Get-NSJsonProperty $Requirement 'fallback'
    $artifact = Get-NSJsonProperty $Requirement 'artifact'
    if (($artifact -is [bool]) -and (-not $artifact) -and $WorkMode -ceq 'artifact') {
        return [ordered]@{
            applies  = $false
            reason   = 'contract is skipped in artifact mode'
            missing  = @()
            fallback = $fallback
        }
    }
    $present = @('available-and-verified', 'available-but-failing', 'fallback-only')
    $missing = New-Object Collections.Generic.List[string]
    foreach ($cap in @(Get-NSJsonProperty $Requirement 'requires')) {
        $item = $Capabilities[$cap]
        if ($null -eq $item) {
            $item = New-NSCapabilityResult 'unavailable' 'not detected' '' 'declared'
        }
        if ($item['status'] -ceq 'unavailable' -or $item['status'] -ceq 'provisionable') {
            $missing.Add($cap)
        }
    }
    $requiresAny = @(Get-NSJsonProperty $Requirement 'requiresAny')
    if ($requiresAny.Count -gt 0) {
        $anyOk = $false
        foreach ($cap in $requiresAny) {
            $item = $Capabilities[$cap]
            if ($null -eq $item) {
                $item = New-NSCapabilityResult 'unavailable' 'not detected' '' 'declared'
            }
            if ($present -ccontains $item['status']) {
                $anyOk = $true
                break
            }
        }
        if (-not $anyOk) {
            foreach ($cap in $requiresAny) {
                $missing.Add($cap)
            }
        }
    }
    if ($missing.Count -gt 0) {
        if ($fallback) {
            return [ordered]@{
                applies  = $true
                reason   = ('fallback: {0}' -f $fallback)
                missing  = $missing.ToArray()
                fallback = $fallback
                status   = 'fallback-only'
            }
        }
        return [ordered]@{
            applies  = $false
            reason   = ('missing capabilities: {0}' -f ($missing -join ', '))
            missing  = $missing.ToArray()
            fallback = $null
        }
    }
    return [ordered]@{
        applies  = $true
        reason   = 'required capabilities are present'
        missing  = @()
        fallback = $fallback
    }
}

function Get-NSCapabilityDocument {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [string]$HostName = 'claude',
        $SearchPath = $null
    )
    $identifiers = Get-NSSchemaDocument 'identifiers.json'
    if ($identifiers.hosts -cnotcontains $HostName) {
        throw ('unknown host: {0}' -f $HostName)
    }
    if ($null -eq $SearchPath) {
        $SearchPath = $env:PATH
    }
    if ($null -eq $SearchPath) {
        $SearchPath = ''
    }
    $SearchPath = [string]$SearchPath

    $ns = Join-NSPath $Project '.nightshift'
    $workMode = 'repository'
    $modePath = Join-NSPath $ns 'work-mode'
    if (Test-Path -LiteralPath $modePath -PathType Leaf) {
        $recorded = ([IO.File]::ReadAllText($modePath)).Trim()
        if (-not [string]::IsNullOrEmpty($recorded)) {
            $workMode = $recorded
        }
    }
    $target = $Project
    $targetPath = Join-NSPath $ns 'work-target'
    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
        $recorded = ([IO.File]::ReadAllText($targetPath)).Trim()
        if (-not [string]::IsNullOrEmpty($recorded)) {
            $target = $recorded
        }
    }

    $topology = [ordered]@{
        root     = $target
        packages = @($target)
        monorepo = $false
        stacks   = @()
    }
    $capabilities = $null
    if ($workMode -ceq 'artifact') {
        $capabilities = Get-NSArtifactCapabilities $target
        foreach ($cap in (Get-NSSchemaDocument 'capabilities.json').capabilities) {
            if ($cap -ceq 'local-markdown' -or $cap -ceq 'local-html' -or $cap -ceq 'source-export') {
                continue
            }
            $capabilities[$cap] = New-NSCapabilityResult 'unavailable' 'artifact mode does not probe repository tools' $target 'declared'
        }
    }
    else {
        $repository = Get-NSRepositoryCapabilities $target $ns $SearchPath
        $capabilities = $repository['Capabilities']
        $topology = $repository['Topology']
    }

    $requirements = (Get-NSSchemaDocument 'catalog-requirements.json').contracts
    $contracts = New-Object -TypeName Collections.Specialized.OrderedDictionary -ArgumentList ([StringComparer]::Ordinal)
    foreach ($id in (Sort-NSOrdinal (@($requirements.PSObject.Properties.Name)))) {
        $contracts[$id] = Get-NSContractEvaluation $requirements.PSObject.Properties[$id].Value $capabilities $workMode
    }

    return [ordered]@{
        schemaVersion       = 1
        host                = $HostName
        workMode            = $workMode
        workTarget          = $target
        topology            = $topology
        capabilities        = $capabilities
        contracts           = $contracts
        provisioningDefault = (Get-NSSchemaDocument 'capabilities.json').provisioningDefault
    }
}

# ---------------------------------------------------------------------------
# Evidence ledger - the native side of runtime/windows/evidence.ps1.
# Validates records. Does not verify a Nightshift tick or interpret domain
# meaning. Every byte it writes matches runtime/evidence.py for the same input.
# ---------------------------------------------------------------------------

$script:NSEvidenceLadderRank = New-Object Collections.Specialized.OrderedDictionary([StringComparer]::Ordinal)
$script:NSEvidenceLadderRank['declared'] = 0
$script:NSEvidenceLadderRank['observed'] = 1
$script:NSEvidenceLadderRank['reproduced'] = 2
$script:NSEvidenceLadderRank['measured'] = 3
$script:NSEvidenceLadderRank['verified-after-change'] = 4
$script:NSEvidenceLadderRank['human-accepted'] = 5

$script:NSEvidenceSecret = New-Object Text.RegularExpressions.Regex(
    '(api[_-]?key|secret|token|password|authorization:\s*bearer)\s*[:=]\s*\S+|-----BEGIN [A-Z ]*PRIVATE KEY-----',
    ([Text.RegularExpressions.RegexOptions]::IgnoreCase -bor [Text.RegularExpressions.RegexOptions]::CultureInvariant))

$script:NSEvidenceTsvColumns = @(
    'id', 'domain', 'sourceClass', 'source', 'scope', 'severity',
    'confidence', 'impact', 'status', 'ladder', 'locator', 'host'
)

# ConvertFrom-Json turns any string that looks like a timestamp into a DateTime,
# which would rewrite firstSeen/lastChecked on the way through. Prefixing every
# string literal with one guard character before the parse - and dropping it
# again after - keeps every value the text it was.
$script:NSJsonGuard = '~'

function Add-NSJsonStringGuard {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $builder = New-Object Text.StringBuilder
    $inString = $false
    $i = 0
    while ($i -lt $Text.Length) {
        $ch = $Text[$i]
        if (-not $inString) {
            $null = $builder.Append($ch)
            if ($ch -eq '"') {
                $inString = $true
                $null = $builder.Append($script:NSJsonGuard)
            }
            $i++
            continue
        }
        if ($ch -eq '\') {
            $null = $builder.Append($ch)
            if ($i + 1 -lt $Text.Length) { $null = $builder.Append($Text[$i + 1]) }
            $i += 2
            continue
        }
        $null = $builder.Append($ch)
        if ($ch -eq '"') { $inString = $false }
        $i++
    }
    return $builder.ToString()
}

function Remove-NSJsonStringGuard {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    if ($Text.Length -eq 0) { return $Text }
    return $Text.Substring(1)
}

function New-NSOrdinalMap {
    return (New-Object Collections.Specialized.OrderedDictionary([StringComparer]::Ordinal))
}

function ConvertFrom-NSJsonNode {
    param($Node)
    if ($null -eq $Node) { return $null }
    if ($Node -is [string]) { return (Remove-NSJsonStringGuard $Node) }
    if ($Node -is [bool] -or (Test-NSJsonInteger $Node) -or (Test-NSJsonFloat $Node)) { return $Node }
    if ($Node -is [Collections.IDictionary]) {
        $map = New-NSOrdinalMap
        foreach ($key in @($Node.Keys)) {
            $map[(Remove-NSJsonStringGuard ([string]$key))] = ConvertFrom-NSJsonNode $Node[$key]
        }
        return $map
    }
    if ($Node -is [Collections.IEnumerable]) {
        $items = New-Object Collections.Generic.List[object]
        foreach ($item in $Node) { $items.Add((ConvertFrom-NSJsonNode $item)) }
        return , $items.ToArray()
    }
    $map = New-NSOrdinalMap
    foreach ($property in $Node.PSObject.Properties) {
        $map[(Remove-NSJsonStringGuard $property.Name)] = ConvertFrom-NSJsonNode $property.Value
    }
    return $map
}

# json.loads: ordered dictionaries with ordinal keys, so "id" and "ID" stay two
# keys and the canonical serializer sees them the way Python does.
function ConvertFrom-NSJsonText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $parsed = ConvertFrom-Json (Add-NSJsonStringGuard $Text) -ErrorAction Stop
    return (ConvertFrom-NSJsonNode $parsed)
}

function Get-NSMapValue {
    param($Map, [Parameter(Mandatory = $true)][string]$Key)
    if (-not ($Map -is [Collections.IDictionary])) { return $null }
    if (-not $Map.Contains($Key)) { return $null }
    return $Map[$Key]
}

function Copy-NSMap {
    param($Map)
    $copy = New-NSOrdinalMap
    if ($Map -is [Collections.IDictionary]) {
        foreach ($key in @($Map.Keys)) { $copy[$key] = $Map[$key] }
    }
    return $copy
}

# Python truth testing: empty string, zero, empty container and None are false.
function Test-NSPyTruthy {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    if ($Value -is [string]) { return ($Value.Length -gt 0) }
    if (Test-NSJsonInteger $Value) { return ([long]$Value -ne 0) }
    if (Test-NSJsonFloat $Value) { return ([double]$Value -ne 0) }
    if ($Value -is [Collections.IDictionary]) { return ($Value.Count -gt 0) }
    if ($Value -is [Collections.ICollection]) { return ($Value.Count -gt 0) }
    return $true
}

# Python str(): None renders None, booleans render True/False.
function ConvertTo-NSPyText {
    param($Value)
    if ($null -eq $Value) { return 'None' }
    if ($Value -is [bool]) {
        if ($Value) { return 'True' }
        return 'False'
    }
    if (Test-NSJsonFloat $Value) { return (Format-NSJsonFloat $Value) }
    return [string]$Value
}

# Python ==: same type and same value, so 1 and "1" stay different.
function Test-NSPyEqual {
    param($Left, $Right)
    return ((ConvertTo-NSCanonicalJson $Left -Compact) -ceq (ConvertTo-NSCanonicalJson $Right -Compact))
}

function Write-NSEvidenceOut {
    param([AllowEmptyString()][string]$Text)
    [Console]::Out.Write($Text)
    [Console]::Out.Write("`n")
}

function Write-NSEvidenceError {
    param([AllowEmptyString()][string]$Text)
    [Console]::Error.WriteLine($Text)
}

function Write-NSEvidenceUsage {
    Write-NSEvidenceError 'usage: evidence.ps1 -Project DIR -Command {init|validate|append|disposition|render|export-tsv|migrate} ...'
    return 1
}

function Get-NSEvidenceNow {
    $fixed = $env:NIGHTSHIFT_EVIDENCE_NOW
    if (-not [string]::IsNullOrEmpty($fixed)) { return $fixed }
    return [DateTime]::UtcNow.ToString('yyyy-MM-dd\THH:mm:ss\Z', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-NSTextSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha.ComputeHash($script:NSUtf8NoBom.GetBytes($Text))
    }
    finally {
        $sha.Dispose()
    }
    $builder = New-Object Text.StringBuilder
    foreach ($byte in $hash) { $null = $builder.Append($byte.ToString('x2')) }
    return $builder.ToString()
}

function Protect-NSEvidenceText {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return [regex]::Replace($Text, $script:NSEvidenceSecret.ToString(), '[redacted]', $script:NSEvidenceSecret.Options)
}

function Test-NSEvidenceSecret {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    return $script:NSEvidenceSecret.IsMatch($Text)
}

function Get-NSEvidencePaths {
    param([Parameter(Mandatory = $true)][string]$Project)
    $ns = Join-NSPath (Get-NSAbsolutePath $Project) '.nightshift'
    $evidence = Join-NSPath $ns 'evidence'
    $paths = New-NSOrdinalMap
    $paths['ns'] = $ns
    $paths['dir'] = $evidence
    $paths['jsonl'] = Join-NSPath $evidence 'findings.jsonl'
    $paths['md'] = Join-NSPath $evidence 'findings.md'
    $paths['raw'] = Join-NSPath $evidence 'raw'
    $paths['version'] = Join-NSPath $evidence 'schema-version'
    return $paths
}

function Write-NSEvidenceFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    [IO.File]::WriteAllText($Path, $Text, $script:NSUtf8NoBom)
}

function Write-NSEvidenceFileAtomic {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )
    $tmp = $Path + '.tmp'
    Write-NSEvidenceFile -Path $tmp -Text $Text
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        # [NullString]::Value, not $null: PowerShell would bind $null to "" and
        # Replace rejects an empty backup path.
        [IO.File]::Replace($tmp, $Path, [NullString]::Value)
        return
    }
    [IO.File]::Move($tmp, $Path)
}

function Test-NSEvidenceSchemaOne {
    param($Value)
    if ($null -eq $Value) { return $false }
    if ($Value -is [bool]) { return [bool]$Value }
    if (Test-NSJsonInteger $Value) { return ([long]$Value -eq 1) }
    if (Test-NSJsonFloat $Value) { return ([double]$Value -eq 1) }
    return $false
}

# Python "value in list": exact, case-sensitive, and never true across types.
function Test-NSEvidenceEnum {
    param($Value, $Allowed)
    if (-not ($Value -is [string])) { return $false }
    foreach ($candidate in @($Allowed)) {
        if (($candidate -is [string]) -and ($candidate -ceq $Value)) { return $true }
    }
    return $false
}

function Get-NSEvidenceLadderRank {
    param($Ladder)
    if (-not ($Ladder -is [string])) { return -1 }
    if (-not $script:NSEvidenceLadderRank.Contains($Ladder)) { return -1 }
    return [int]$script:NSEvidenceLadderRank[$Ladder]
}

function Test-NSEvidenceRecord {
    param($Record, $Schema, $Previous)
    $errors = New-Object Collections.Generic.List[string]
    if (-not ($Record -is [Collections.IDictionary])) {
        $errors.Add('record is not an object')
        return , $errors
    }
    foreach ($key in $Schema.required) {
        if (-not $Record.Contains($key)) { $errors.Add('missing ' + $key) }
    }
    if (-not (Test-NSEvidenceSchemaOne (Get-NSMapValue $Record 'schemaVersion'))) { $errors.Add('unsupported schemaVersion') }
    if (-not (Test-NSEvidenceEnum (Get-NSMapValue $Record 'severity') $Schema.severity)) { $errors.Add('invalid severity') }
    if (-not (Test-NSEvidenceEnum (Get-NSMapValue $Record 'confidence') $Schema.confidence)) { $errors.Add('invalid confidence') }
    if (-not (Test-NSEvidenceEnum (Get-NSMapValue $Record 'impact') $Schema.impact)) { $errors.Add('invalid impact') }
    if (-not (Test-NSEvidenceEnum (Get-NSMapValue $Record 'status') $Schema.status)) { $errors.Add('invalid status') }
    if (-not (Test-NSEvidenceEnum (Get-NSMapValue $Record 'ladder') $Schema.ladder)) { $errors.Add('invalid ladder') }
    $locator = Get-NSMapValue $Record 'locator'
    if (-not (Test-NSPyTruthy $locator)) { $locator = '' }
    if (([string]$locator).Contains('://') -and -not (Test-NSPyTruthy (Get-NSMapValue $Record 'untrusted'))) {
        $errors.Add('remote locator requires untrusted=true')
    }
    if (Test-NSEvidenceSecret (ConvertTo-NSCanonicalJson $Record -Compact)) { $errors.Add('record contains a secret pattern') }
    if ($null -ne $Previous) {
        $oldRank = Get-NSEvidenceLadderRank (Get-NSMapValue $Previous 'ladder')
        $newRank = Get-NSEvidenceLadderRank (Get-NSMapValue $Record 'ladder')
        $promoteBy = Get-NSMapValue $Record 'promoteBy'
        if ($oldRank -ge 0 -and $newRank -ge 0 -and $newRank -gt $oldRank -and ($promoteBy -is [string]) -and ($promoteBy -ceq 'prose')) {
            $errors.Add('ladder must not be promoted by prose')
        }
    }
    return , $errors
}

# SystemExit in the reference: the message goes to stderr and the process
# leaves with 1, whichever command was running.
function New-NSEvidenceHalt {
    param([Parameter(Mandatory = $true)][string]$Message)
    return (New-Object ApplicationException($Message))
}

function Read-NSEvidenceRecords {
    param([Parameter(Mandatory = $true)][string]$Path)
    $records = New-Object Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return , $records }
    $lines = [regex]::Split([IO.File]::ReadAllText($Path, $script:NSUtf8NoBom), "\r\n|\n|\r")
    for ($i = 0; $i -lt $lines.Length; $i++) {
        $line = $lines[$i].Trim()
        if ($line.Length -eq 0) { continue }
        $record = $null
        try {
            $record = ConvertFrom-NSJsonText $line
        }
        catch {
            throw (New-NSEvidenceHalt ('evidence: malformed JSON on line ' + ($i + 1)))
        }
        $records.Add($record)
    }
    return , $records
}

function Write-NSEvidenceRecords {
    param([Parameter(Mandatory = $true)][string]$Path, $Records)
    $builder = New-Object Text.StringBuilder
    foreach ($record in $Records) {
        $null = $builder.Append((ConvertTo-NSCanonicalJson $record -Compact))
        $null = $builder.Append("`n")
    }
    Write-NSEvidenceFileAtomic -Path $Path -Text $builder.ToString()
}

function Invoke-NSEvidenceInit {
    param([Parameter(Mandatory = $true)][string]$Project, [switch]$Quiet)
    $paths = Get-NSEvidencePaths $Project
    if (-not (Test-Path -LiteralPath $paths['ns'] -PathType Container)) {
        Write-NSEvidenceError ('evidence: no .nightshift/ at ' + $Project)
        return 1
    }
    $null = [IO.Directory]::CreateDirectory($paths['raw'])
    if (-not (Test-Path -LiteralPath $paths['jsonl'] -PathType Leaf)) {
        Write-NSEvidenceFile -Path $paths['jsonl'] -Text ''
    }
    if (-not (Test-Path -LiteralPath $paths['version'] -PathType Leaf)) {
        Write-NSEvidenceFile -Path $paths['version'] -Text "1`n"
    }
    if (-not $Quiet) { Write-NSEvidenceOut $paths['jsonl'] }
    return 0
}

function Invoke-NSEvidenceValidate {
    param([Parameter(Mandatory = $true)][string]$Project)
    $paths = Get-NSEvidencePaths $Project
    if (-not (Test-Path -LiteralPath $paths['jsonl'] -PathType Leaf)) {
        Write-NSEvidenceOut 'evidence: no ledger (valid empty workspace)'
        return 0
    }
    $schema = Get-NSSchemaDocument 'finding.json'
    $records = Read-NSEvidenceRecords $paths['jsonl']
    $seen = New-NSOrdinalMap
    $code = 0
    foreach ($record in $records) {
        $id = Get-NSMapValue $record 'id'
        $key = ConvertTo-NSCanonicalJson $id -Compact
        $previous = $null
        if ($seen.Contains($key)) { $previous = $seen[$key] }
        $errors = Test-NSEvidenceRecord $record $schema $previous
        if ($errors.Count -gt 0) {
            $code = 2
            $label = '?'
            if (Test-NSPyTruthy $id) { $label = ConvertTo-NSPyText $id }
            foreach ($error in $errors) { Write-NSEvidenceError ('evidence: ' + $label + ': ' + $error) }
        }
        if (Test-NSPyTruthy $id) { $seen[$key] = $record }
    }
    return $code
}

function Invoke-NSEvidenceAppend {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$RecordJson,
        [AllowEmptyString()][string]$RawText = ''
    )
    $paths = Get-NSEvidencePaths $Project
    $null = Invoke-NSEvidenceInit -Project $Project -Quiet
    $record = ConvertFrom-NSJsonText $RecordJson
    if ($record -is [Collections.IDictionary]) {
        if (-not $record.Contains('schemaVersion')) { $record['schemaVersion'] = 1 }
        if (-not $record.Contains('firstSeen')) { $record['firstSeen'] = Get-NSEvidenceNow }
        if (-not $record.Contains('lastChecked')) { $record['lastChecked'] = $record['firstSeen'] }
        if (-not $record.Contains('digest')) {
            $record['digest'] = Get-NSTextSha256 (ConvertTo-NSCanonicalJson $record -Compact)
        }
        foreach ($key in @('action', 'fix', 'verificationLocator', 'disposition', 'rollback')) {
            if (-not $record.Contains($key)) { $record[$key] = '' }
        }
        $source = Get-NSMapValue $record 'source'
        if (-not (Test-NSPyTruthy $source)) { $source = Get-NSMapValue $record 'sourceCommand' }
        if (-not (Test-NSPyTruthy $source)) { $source = '' }
        $record['source'] = $source
        $sourceClass = Get-NSMapValue $record 'sourceClass'
        if (-not (Test-NSPyTruthy $sourceClass)) { $sourceClass = Get-NSMapValue $record 'sourceTool' }
        if (-not (Test-NSPyTruthy $sourceClass)) { $sourceClass = 'unknown' }
        $record['sourceClass'] = $sourceClass
    }
    $schema = Get-NSSchemaDocument 'finding.json'
    $records = Read-NSEvidenceRecords $paths['jsonl']
    $previous = $null
    foreach ($existing in $records) {
        if (Test-NSPyEqual (Get-NSMapValue $existing 'id') (Get-NSMapValue $record 'id')) {
            $previous = $existing
            break
        }
    }
    $errors = Test-NSEvidenceRecord $record $schema $previous
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) { Write-NSEvidenceError ('evidence: ' + $error) }
        return 2
    }
    if (Test-NSPyTruthy $RawText) {
        $record['rawPath'] = 'evidence/raw/' + [string]$record['id'] + '.txt'
        $redacted = Protect-NSEvidenceText $RawText
        $onDisk = $redacted
        if (-not $redacted.EndsWith("`n")) { $onDisk = $redacted + "`n" }
        Write-NSEvidenceFile -Path (Join-NSPath $paths['ns'] $record['rawPath']) -Text $onDisk
        $record['rawDigest'] = Get-NSTextSha256 $redacted
    }
    $records.Add($record)
    Write-NSEvidenceRecords -Path $paths['jsonl'] -Records $records
    Write-NSEvidenceOut (ConvertTo-NSPyText (Get-NSMapValue $record 'id'))
    return 0
}

function Invoke-NSEvidenceDisposition {
    param(
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Disposition,
        [AllowEmptyString()][string]$Ladder = ''
    )
    $paths = Get-NSEvidencePaths $Project
    $records = Read-NSEvidenceRecords $paths['jsonl']
    $schema = Get-NSSchemaDocument 'finding.json'
    $found = $false
    foreach ($record in $records) {
        $recordId = Get-NSMapValue $record 'id'
        if (-not (($recordId -is [string]) -and ($recordId -ceq $Id))) { continue }
        $found = $true
        $previous = Copy-NSMap $record
        $record['disposition'] = $Disposition
        $record['lastChecked'] = Get-NSEvidenceNow
        if (Test-NSPyTruthy $Ladder) { $record['ladder'] = $Ladder }
        $errors = Test-NSEvidenceRecord $record $schema $previous
        if ($errors.Count -gt 0) {
            foreach ($error in $errors) { Write-NSEvidenceError ('evidence: ' + $error) }
            return 2
        }
    }
    if (-not $found) {
        Write-NSEvidenceError ('evidence: unknown id ' + $Id)
        return 2
    }
    Write-NSEvidenceRecords -Path $paths['jsonl'] -Records $records
    return 0
}

function Get-NSEvidenceMarkdown {
    param($Records)
    $dash = [string][char]0x2014
    $lines = New-Object Collections.Generic.List[string]
    $lines.Add('# Evidence ledger')
    $lines.Add('')
    $lines.Add('Machine source: `evidence/findings.jsonl`. Helpers validate records; they do not')
    $lines.Add('verify a Nightshift tick or interpret domain meaning.')
    $lines.Add('')
    $lines.Add('| ID | Domain | Severity | Ladder | Status | Locator |')
    $lines.Add('| --- | --- | --- | --- | --- | --- |')
    $count = 0
    foreach ($record in $Records) {
        $cells = New-Object Collections.Generic.List[string]
        foreach ($column in @('id', 'domain', 'severity', 'ladder', 'status', 'locator')) {
            $cells.Add((ConvertTo-NSPyText (Get-NSMapValue $record $column)))
        }
        $lines.Add('| ' + ($cells -join ' | ') + ' |')
        $count++
    }
    if ($count -eq 0) {
        $empty = @($dash, $dash, $dash, $dash, $dash, 'empty')
        $lines.Add('| ' + ($empty -join ' | ') + ' |')
    }
    return (($lines -join "`n") + "`n")
}

function Invoke-NSEvidenceRender {
    param([Parameter(Mandatory = $true)][string]$Project)
    $paths = Get-NSEvidencePaths $Project
    $records = Read-NSEvidenceRecords $paths['jsonl']
    $text = Get-NSEvidenceMarkdown $records
    $null = [IO.Directory]::CreateDirectory($paths['dir'])
    Write-NSEvidenceFile -Path $paths['md'] -Text $text
    [Console]::Out.Write($text)
    return 0
}

function Invoke-NSEvidenceExportTsv {
    param([Parameter(Mandatory = $true)][string]$Project)
    $paths = Get-NSEvidencePaths $Project
    $records = Read-NSEvidenceRecords $paths['jsonl']
    Write-NSEvidenceOut ($script:NSEvidenceTsvColumns -join "`t")
    foreach ($record in $records) {
        $cells = New-Object Collections.Generic.List[string]
        foreach ($column in $script:NSEvidenceTsvColumns) {
            $value = ''
            if (($record -is [Collections.IDictionary]) -and $record.Contains($column)) {
                $value = ConvertTo-NSPyText $record[$column]
            }
            $cells.Add($value.Replace("`t", ' '))
        }
        Write-NSEvidenceOut ($cells -join "`t")
    }
    return 0
}

function Invoke-NSEvidenceMigrate {
    param([Parameter(Mandatory = $true)][string]$Project)
    $paths = Get-NSEvidencePaths $Project
    $hasDir = Test-Path -LiteralPath $paths['dir'] -PathType Container
    $hasLedger = Test-Path -LiteralPath $paths['jsonl'] -PathType Leaf
    if (-not $hasDir -and -not $hasLedger) {
        Write-NSEvidenceOut 'evidence: nothing to migrate'
        return 0
    }
    $version = '0'
    if (Test-Path -LiteralPath $paths['version'] -PathType Leaf) {
        $version = ([IO.File]::ReadAllText($paths['version'], $script:NSUtf8NoBom)).Trim()
        if ($version.Length -eq 0) { $version = '0' }
    }
    if (($version -ceq '0') -or ($version -ceq '1')) {
        $null = [IO.Directory]::CreateDirectory($paths['raw'])
        Write-NSEvidenceFile -Path $paths['version'] -Text "1`n"
        if (-not (Test-Path -LiteralPath $paths['jsonl'] -PathType Leaf)) {
            Write-NSEvidenceFile -Path $paths['jsonl'] -Text ''
        }
        Write-NSEvidenceOut 'evidence: schema-version 1'
        return 0
    }
    Write-NSEvidenceError ('evidence: unsupported evidence schema-version ' + $version)
    return 2
}

function Invoke-NSEvidenceCommand {
    param(
        [AllowEmptyString()][string]$Project = '',
        [AllowEmptyString()][string]$Command = '',
        [AllowEmptyString()][string]$Record = '',
        [AllowEmptyString()][string]$Raw = '',
        [AllowEmptyString()][string]$Id = '',
        [AllowEmptyString()][string]$Disposition = '',
        [AllowEmptyString()][string]$Ladder = ''
    )
    try {
        if ([string]::IsNullOrEmpty($Project) -or [string]::IsNullOrEmpty($Command)) { return (Write-NSEvidenceUsage) }
        switch ($Command) {
            'init' { return (Invoke-NSEvidenceInit -Project $Project) }
            'validate' { return (Invoke-NSEvidenceValidate -Project $Project) }
            'append' {
                if ([string]::IsNullOrEmpty($Record)) { return (Write-NSEvidenceUsage) }
                return (Invoke-NSEvidenceAppend -Project $Project -RecordJson $Record -RawText $Raw)
            }
            'disposition' {
                if ([string]::IsNullOrEmpty($Id) -or [string]::IsNullOrEmpty($Disposition)) { return (Write-NSEvidenceUsage) }
                return (Invoke-NSEvidenceDisposition -Project $Project -Id $Id -Disposition $Disposition -Ladder $Ladder)
            }
            'render' { return (Invoke-NSEvidenceRender -Project $Project) }
            'export-tsv' { return (Invoke-NSEvidenceExportTsv -Project $Project) }
            'migrate' { return (Invoke-NSEvidenceMigrate -Project $Project) }
        }
        return (Write-NSEvidenceUsage)
    }
    catch [ApplicationException] {
        Write-NSEvidenceError $_.Exception.Message
        return 1
    }
}

# ---------------------------------------------------------------------------
# Layered shift policy - the native side of runtime/windows/shift-policy.ps1,
# preflight-needs.ps1 and park-needs.ps1.
#
# rules.json carries the permanent boundaries, shift-defaults.json only prefills
# the next composition question, and shift-policy.json is tonight's snapshot.
# Get-NSPolicyResolution is the one resolver: hardhat, Start, Doctor, Status and
# the support bundle render what it returns and never re-derive precedence.
# ---------------------------------------------------------------------------

$script:NSPolicyCategories = @('sudo', 'containers', 'global-packages', 'daemons', 'external-services')
$script:NSPolicyVerificationLevels = @('none', 'final', 'per-item', 'custom')
$script:NSPolicyToolingPolicies = @('existing-tools', 'review-missing', 'auto-add')
$script:NSPolicyProfiles = @('fast', 'balanced', 'strict', 'custom')
$script:NSPolicyExecutions = @('review-first', 'run-direct')
$script:NSPolicySources = @('composition', 'start-defaults')
$script:NSPolicyScopes = @('category', 'exact-plan')
$script:NSPolicyProvenances = @('rules', 'one-shift')

# Shipped elevation patterns (grep -E), used for any category rules.json does not
# carry. Preflight and the hardhat guard read them through Get-NSElevationPattern,
# so the signal that parks an item is the signal that blocks the command.
$script:NSPolicyElevationPattern = New-Object Collections.Specialized.OrderedDictionary([StringComparer]::Ordinal)
$script:NSPolicyElevationPattern['sudo'] = '(^|[;&|(]|[[:space:]])(sudo|doas)([[:space:]]|$)'
$script:NSPolicyElevationPattern['containers'] = '(^|[;&|(]|[[:space:]])(docker|docker-compose|podman|nerdctl|colima)([[:space:]]|$)'
$script:NSPolicyElevationPattern['global-packages'] = '(^|[;&|(]|[[:space:]])(brew|apt|apt-get|dnf|yum|pacman|choco|winget|scoop)([[:space:]]|$)|npm[[:space:]]+(i|install)[[:space:]]+(-g|--global)|pnpm[[:space:]]+add[[:space:]]+-g|yarn[[:space:]]+global|pip3?[[:space:]]+install[[:space:]]+--user'
$script:NSPolicyElevationPattern['daemons'] = '(^|[;&|(]|[[:space:]])(systemctl|launchctl|service|brew[[:space:]]+services|pg_ctl|redis-server|mongod|mysqld)([[:space:]]|$)'
$script:NSPolicyElevationPattern['external-services'] = '(^|[;&|(]|[[:space:]])(gh[[:space:]]+auth[[:space:]]+login|npm[[:space:]]+login|docker[[:space:]]+login|az[[:space:]]+login|gcloud[[:space:]]+auth|aws[[:space:]]+configure)([[:space:]]|$)'

# Every setting the resolved view reports, in the order the table prints them.
$script:NSPolicySettingNames = @(
    'deadlineEpoch',
    'elevation.containers',
    'elevation.daemons',
    'elevation.external-services',
    'elevation.global-packages',
    'elevation.sudo',
    'expectedEmail',
    'forbiddenCommands',
    'neverCommitPatterns',
    'protectedDirs',
    'stallMax',
    'toolingPolicy',
    'verificationLevel',
    'watchMinutes'
)

function Write-NSPolicyOut {
    param([AllowEmptyString()][string]$Text)
    [Console]::Out.Write($Text)
    [Console]::Out.Write("`n")
}

function Write-NSPolicyError {
    param([AllowEmptyString()][string]$Text)
    [Console]::Error.WriteLine($Text)
}

function Get-NSPolicyNow {
    $fixed = $env:NIGHTSHIFT_POLICY_NOW
    if (-not [string]::IsNullOrEmpty($fixed)) { return $fixed }
    return [DateTime]::UtcNow.ToString('yyyy-MM-dd\THH:mm:ss\Z', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-NSPolicyPaths {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $ns = Join-NSPath (Get-NSAbsolutePath $Workspace) '.nightshift'
    $paths = New-NSOrdinalMap
    $paths['ns'] = $ns
    $paths['policy'] = Join-NSPath $ns 'shift-policy.json'
    $paths['defaults'] = Join-NSPath $ns 'shift-defaults.json'
    $paths['legacy'] = Join-NSPath $ns 'capability-policy.json'
    $paths['deadline'] = Join-NSPath $ns 'deadline'
    $paths['armed'] = Join-NSPath $ns '.shift-armed'
    $paths['archive'] = Join-NSPath $ns 'archive'
    $paths['punch'] = Join-NSPath $ns 'punch-list.md'
    $paths['orders'] = Join-NSPath $ns 'work-orders.md'
    $paths['parking'] = Join-NSPath $ns 'parking-lot.md'
    return $paths
}

function Test-NSPolicyArmed {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    return (Test-Path -LiteralPath (Get-NSPolicyPaths $Workspace)['armed'] -PathType Leaf)
}

# .NET has no POSIX character classes; the shipped patterns and any owner pattern
# in rules.elevation are grep -E. Same table as the hardhat hook's converter.
function Convert-NSPolicyErePattern {
    param([Parameter(Mandatory = $true)][string]$Pattern)
    $result = $Pattern.Replace('[[:space:]]', '\s')
    $result = $result.Replace('[[:blank:]]', '[ \t]')
    $result = $result.Replace('[[:digit:]]', '\d')
    $result = $result.Replace('[[:alnum:]]', '[A-Za-z0-9]')
    $result = $result.Replace('[[:alpha:]]', '[A-Za-z]')
    $result = $result.Replace('[[:lower:]]', '[a-z]')
    $result = $result.Replace('[[:upper:]]', '[A-Z]')
    $result = $result.Replace('[[:xdigit:]]', '[A-Fa-f0-9]')
    if ($result -match '\[:[a-z]+:\]') {
        throw 'unmapped POSIX character class'
    }
    return $result
}

function New-NSPolicyRegex {
    param([Parameter(Mandatory = $true)][string]$Pattern)
    return [Text.RegularExpressions.Regex]::new(
        (Convert-NSPolicyErePattern $Pattern),
        [Text.RegularExpressions.RegexOptions]::Multiline)
}

function Get-NSRulesElevationEntry {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Category
    )
    $rules = Get-NSRulesObject $Workspace
    if ($null -eq $rules) { return $null }
    $elevation = Get-NSJsonProperty $rules 'elevation'
    if ($null -eq $elevation) { return $null }
    return (Get-NSJsonProperty $elevation $Category)
}

function Get-NSElevationPattern {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Category
    )
    if (-not ($script:NSPolicyCategories -ccontains $Category)) { return '' }
    $entry = Get-NSRulesElevationEntry $Workspace $Category
    if ($null -ne $entry) {
        $pattern = Get-NSJsonProperty $entry 'pattern'
        if (($pattern -is [string]) -and $pattern.Length -gt 0) { return $pattern }
    }
    return [string]$script:NSPolicyElevationPattern[$Category]
}

function Get-NSElevationRulePolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Category
    )
    $entry = Get-NSRulesElevationEntry $Workspace $Category
    if ($null -eq $entry) { return '' }
    $policy = Get-NSJsonProperty $entry 'policy'
    if (($policy -is [string]) -and (($policy -ceq 'allow') -or ($policy -ceq 'deny'))) { return $policy }
    return ''
}

# ---------------------------------------------------------------------------
# shift-policy.json
# ---------------------------------------------------------------------------

# A function that returns an array unrolls it, so a one-command plan would come
# back as a bare string. The comma keeps an array an array and a scalar a scalar.
function Get-NSPolicyField {
    param($Map, [Parameter(Mandatory = $true)][string]$Key)
    if (-not ($Map -is [Collections.IDictionary])) { return $null }
    if (-not $Map.Contains($Key)) { return $null }
    return , $Map[$Key]
}

function Test-NSPolicyShiftId {
    param($Value)
    if (-not ($Value -is [string])) { return $false }
    if ($Value -cmatch '^[0-9a-f]{16}$') { return $true }
    return ($Value -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$')
}

function Test-NSPolicyDigest {
    param($Value)
    return (($Value -is [string]) -and ($Value -cmatch '^[0-9a-f]{64}$'))
}

# The schema lives at references/schemas/v1/shift-policy.json; these are the same
# constraints, applied without a file read so a helper still validates on a host
# whose plugin tree is read-only or partially installed.
function Test-NSShiftPolicyDocument {
    param($Document)
    $errors = New-Object Collections.Generic.List[string]
    if (-not ($Document -is [Collections.IDictionary])) {
        $errors.Add('document: not a JSON object')
        return , $errors
    }
    $known = @('schemaVersion', 'shiftId', 'createdAt', 'source', 'deadlineEpoch',
        'verificationLevel', 'toolingPolicy', 'budgets', 'allowances', 'gatesDigest')
    foreach ($key in @($Document.Keys)) {
        if (-not ($known -ccontains [string]$key)) {
            $errors.Add(([string]$key) + ': unknown field')
        }
    }
    foreach ($key in @('schemaVersion', 'shiftId', 'createdAt', 'source', 'verificationLevel', 'toolingPolicy')) {
        if (-not $Document.Contains($key)) { $errors.Add($key + ': missing') }
    }
    if ($Document.Contains('schemaVersion') -and -not (Test-NSEvidenceSchemaOne $Document['schemaVersion'])) {
        $errors.Add('schemaVersion: must be 1')
    }
    if ($Document.Contains('shiftId') -and -not (Test-NSPolicyShiftId $Document['shiftId'])) {
        $errors.Add('shiftId: must be a uuid or 16 lowercase hex characters')
    }
    if ($Document.Contains('createdAt') -and -not (($Document['createdAt'] -is [string]) -and ($Document['createdAt'] -cmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$'))) {
        $errors.Add('createdAt: must be YYYY-MM-DDTHH:MM:SSZ')
    }
    if ($Document.Contains('source') -and -not (Test-NSEvidenceEnum $Document['source'] $script:NSPolicySources)) {
        $errors.Add('source: must be one of ' + ($script:NSPolicySources -join ', '))
    }
    if ($Document.Contains('verificationLevel') -and -not (Test-NSEvidenceEnum $Document['verificationLevel'] $script:NSPolicyVerificationLevels)) {
        $errors.Add('verificationLevel: must be one of ' + ($script:NSPolicyVerificationLevels -join ', '))
    }
    if ($Document.Contains('toolingPolicy') -and -not (Test-NSEvidenceEnum $Document['toolingPolicy'] $script:NSPolicyToolingPolicies)) {
        $errors.Add('toolingPolicy: must be one of ' + ($script:NSPolicyToolingPolicies -join ', '))
    }
    if ($Document.Contains('deadlineEpoch')) {
        $deadline = $Document['deadlineEpoch']
        if ($null -ne $deadline -and -not (Test-NSJsonInteger $deadline)) {
            $errors.Add('deadlineEpoch: must be an integer or null')
        }
    }
    if ($Document.Contains('gatesDigest') -and -not (Test-NSPolicyDigest $Document['gatesDigest'])) {
        $errors.Add('gatesDigest: must be 64 lowercase hex characters')
    }
    if ($Document.Contains('budgets')) {
        $budgets = $Document['budgets']
        if (-not ($budgets -is [Collections.IDictionary])) {
            $errors.Add('budgets: must be an object of integers')
        }
        else {
            foreach ($key in @($budgets.Keys)) {
                if (-not (Test-NSJsonInteger $budgets[$key])) {
                    $errors.Add('budgets.' + ([string]$key) + ': must be an integer')
                }
            }
        }
    }
    if ($Document.Contains('allowances')) {
        $allowances = $Document['allowances']
        if (($allowances -is [Collections.IDictionary]) -or ($allowances -is [string]) -or -not ($allowances -is [Collections.IEnumerable])) {
            $errors.Add('allowances: must be an array')
        }
        else {
            $index = 0
            foreach ($allowance in @($allowances)) {
                $label = 'allowances[' + $index + ']'
                $index++
                if (-not ($allowance -is [Collections.IDictionary])) {
                    $errors.Add($label + ': not a JSON object')
                    continue
                }
                foreach ($key in @($allowance.Keys)) {
                    if (-not (@('category', 'scope', 'provenance', 'plan') -ccontains [string]$key)) {
                        $errors.Add($label + '.' + ([string]$key) + ': unknown field')
                    }
                }
                if (-not (Test-NSEvidenceEnum (Get-NSMapValue $allowance 'category') $script:NSPolicyCategories)) {
                    $errors.Add($label + '.category: must be one of ' + ($script:NSPolicyCategories -join ', '))
                }
                if (-not (Test-NSEvidenceEnum (Get-NSMapValue $allowance 'scope') $script:NSPolicyScopes)) {
                    $errors.Add($label + '.scope: must be one of ' + ($script:NSPolicyScopes -join ', '))
                }
                if (-not (Test-NSEvidenceEnum (Get-NSMapValue $allowance 'provenance') $script:NSPolicyProvenances)) {
                    $errors.Add($label + '.provenance: must be one of ' + ($script:NSPolicyProvenances -join ', '))
                }
                $scope = Get-NSMapValue $allowance 'scope'
                $plan = Get-NSMapValue $allowance 'plan'
                if (($scope -is [string]) -and ($scope -ceq 'exact-plan')) {
                    foreach ($planError in (Test-NSPolicyPlan $plan ($label + '.plan'))) { $errors.Add($planError) }
                }
                elseif ($null -ne $plan) {
                    $errors.Add($label + '.plan: only an exact-plan allowance carries a plan')
                }
            }
        }
    }
    return , $errors
}

function Test-NSPolicyPlan {
    param($Plan, [Parameter(Mandatory = $true)][string]$Label)
    $errors = New-Object Collections.Generic.List[string]
    if (-not ($Plan -is [Collections.IDictionary])) {
        $errors.Add($Label + ': an exact-plan allowance needs a plan object')
        return , $errors
    }
    foreach ($key in @($Plan.Keys)) {
        if (-not (@('commands', 'workTarget', 'digest', 'expiry') -ccontains [string]$key)) {
            $errors.Add($Label + '.' + ([string]$key) + ': unknown field')
        }
    }
    $commands = Get-NSPolicyField $Plan 'commands'
    if (($commands -is [Collections.IDictionary]) -or ($commands -is [string]) -or -not ($commands -is [Collections.IEnumerable])) {
        $errors.Add($Label + '.commands: must be an array of strings')
    }
    else {
        $items = @($commands)
        if ($items.Count -eq 0) {
            $errors.Add($Label + '.commands: must list at least one command')
        }
        foreach ($command in $items) {
            if (-not (($command -is [string]) -and $command.Trim().Length -gt 0)) {
                $errors.Add($Label + '.commands: must be an array of non-empty strings')
                break
            }
        }
    }
    $target = Get-NSMapValue $Plan 'workTarget'
    if (-not (($target -is [string]) -and $target.Length -gt 0 -and [IO.Path]::IsPathRooted($target))) {
        $errors.Add($Label + '.workTarget: must be an absolute path')
    }
    if ($Plan.Contains('expiry')) {
        $expiry = $Plan['expiry']
        if ($null -ne $expiry -and -not (Test-NSJsonInteger $expiry)) {
            $errors.Add($Label + '.expiry: must be a UNIX epoch integer or null')
        }
    }
    if (-not (Test-NSPolicyDigest (Get-NSMapValue $Plan 'digest'))) {
        $errors.Add($Label + '.digest: must be 64 lowercase hex characters')
    }
    return , $errors
}

# The digest an exact-plan allowance carries and hardhat recomputes: sha256 over
# the compact canonical JSON of {"commands":[...],"shiftId":...,"workTarget":...}.
# plan.expiry is checked before the digest, never inside it.
function Get-NSPolicyPlanDigest {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Commands,
        [Parameter(Mandatory = $true)][string]$WorkTarget,
        [Parameter(Mandatory = $true)][string]$ShiftId
    )
    $normalized = New-Object Collections.Generic.List[string]
    foreach ($command in $Commands) { $normalized.Add((Get-NSPolicyNormalizedCommand $command)) }
    $preimage = New-NSOrdinalMap
    $preimage['commands'] = $normalized.ToArray()
    $preimage['shiftId'] = $ShiftId
    $preimage['workTarget'] = $WorkTarget
    return (Get-NSTextSha256 (ConvertTo-NSCanonicalJson $preimage -Compact))
}

# Whitespace runs collapse to one space and the ends are trimmed, so a command
# approved as written matches the command as the host reports it.
function Get-NSPolicyNormalizedCommand {
    param([AllowEmptyString()][string]$Command)
    if ([string]::IsNullOrEmpty($Command)) { return '' }
    return ([regex]::Replace($Command, '\s+', ' ')).Trim()
}

function Get-NSShiftPolicyState {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $paths = Get-NSPolicyPaths $Workspace
    $state = New-NSOrdinalMap
    $state['state'] = 'absent'
    $state['error'] = ''
    $state['policy'] = $null
    $path = $paths['policy']
    if (Test-NSReparsePoint $path) {
        $state['state'] = 'malformed'
        $state['error'] = 'document: shift-policy.json is not a usable file'
        return $state
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return $state }
    $document = $null
    try {
        $document = ConvertFrom-NSJsonText ([IO.File]::ReadAllText($path, $script:NSUtf8NoBom))
    }
    catch {
        $state['state'] = 'malformed'
        $state['error'] = 'document: not valid JSON'
        return $state
    }
    $errors = Test-NSShiftPolicyDocument $document
    if ($errors.Count -gt 0) {
        $state['state'] = 'malformed'
        $state['error'] = $errors[0]
        return $state
    }
    $state['state'] = 'valid'
    $state['policy'] = $document
    return $state
}

function Get-NSShiftPolicy {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $state = Get-NSShiftPolicyState $Workspace
    return $state['policy']
}

function Set-NSShiftPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Json
    )
    $paths = Get-NSPolicyPaths $Workspace
    if (-not (Test-Path -LiteralPath $paths['ns'] -PathType Container)) {
        Write-NSPolicyError ('shift-policy: no .nightshift/ at ' + $Workspace)
        return 2
    }
    if (Test-NSPolicyArmed $Workspace) {
        Write-NSPolicyError 'shift-policy: refuse to rewrite the shift policy while the shift is armed; park the need'
        return 4
    }
    $document = $null
    try {
        $document = ConvertFrom-NSJsonText $Json
    }
    catch {
        Write-NSPolicyError 'shift-policy: document: not valid JSON'
        return 2
    }
    $errors = Test-NSShiftPolicyDocument $document
    if ($errors.Count -gt 0) {
        foreach ($error in $errors) { Write-NSPolicyError ('shift-policy: ' + $error) }
        return 2
    }
    Write-NSEvidenceFileAtomic -Path $paths['policy'] -Text ((ConvertTo-NSCanonicalJson $document) + "`n")
    return 0
}

# ---------------------------------------------------------------------------
# shift-defaults.json - prefill only. Nothing here is ever an effective value.
# ---------------------------------------------------------------------------

function New-NSShiftDefaultsDocument {
    $document = New-NSOrdinalMap
    $document['schemaVersion'] = 1
    $document['verificationProfile'] = 'fast'
    $document['hours'] = $null
    $document['toolingPolicy'] = 'existing-tools'
    $document['execution'] = 'review-first'
    $document['updatedAt'] = ''
    return $document
}

function Get-NSShiftDefaults {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $paths = Get-NSPolicyPaths $Workspace
    $defaults = New-NSShiftDefaultsDocument
    $path = $paths['defaults']
    if ((Test-NSReparsePoint $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $defaults }
    $document = $null
    try {
        $document = ConvertFrom-NSJsonText ([IO.File]::ReadAllText($path, $script:NSUtf8NoBom))
    }
    catch {
        return $defaults
    }
    if (-not ($document -is [Collections.IDictionary])) { return $defaults }
    $storedProfile = Get-NSMapValue $document 'verificationProfile'
    if (Test-NSEvidenceEnum $storedProfile $script:NSPolicyProfiles) { $defaults['verificationProfile'] = $storedProfile }
    $tooling = Get-NSMapValue $document 'toolingPolicy'
    if (Test-NSEvidenceEnum $tooling $script:NSPolicyToolingPolicies) { $defaults['toolingPolicy'] = $tooling }
    $execution = Get-NSMapValue $document 'execution'
    if (Test-NSEvidenceEnum $execution $script:NSPolicyExecutions) { $defaults['execution'] = $execution }
    $hours = Get-NSMapValue $document 'hours'
    if ((Test-NSJsonInteger $hours) -and [long]$hours -ge 0) { $defaults['hours'] = [long]$hours }
    $updated = Get-NSMapValue $document 'updatedAt'
    if ($updated -is [string]) { $defaults['updatedAt'] = $updated }
    return $defaults
}

function Set-NSShiftDefaults {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [AllowEmptyString()][string]$VerificationProfile = '',
        [AllowEmptyString()][string]$Hours = '',
        [AllowEmptyString()][string]$ToolingPolicy = '',
        [AllowEmptyString()][string]$Execution = ''
    )
    $paths = Get-NSPolicyPaths $Workspace
    if (-not (Test-Path -LiteralPath $paths['ns'] -PathType Container)) {
        Write-NSPolicyError ('shift-policy: no .nightshift/ at ' + $Workspace)
        return 2
    }
    if (Test-NSPolicyArmed $Workspace) {
        Write-NSPolicyError 'shift-policy: refuse to rewrite the shift defaults while the shift is armed; park the need'
        return 4
    }
    $document = Get-NSShiftDefaults $Workspace
    if (-not [string]::IsNullOrEmpty($VerificationProfile)) {
        if (-not (Test-NSEvidenceEnum $VerificationProfile $script:NSPolicyProfiles)) {
            Write-NSPolicyError ('shift-policy: verificationProfile: must be one of ' + ($script:NSPolicyProfiles -join ', '))
            return 2
        }
        $document['verificationProfile'] = $VerificationProfile
    }
    if (-not [string]::IsNullOrEmpty($ToolingPolicy)) {
        if (-not (Test-NSEvidenceEnum $ToolingPolicy $script:NSPolicyToolingPolicies)) {
            Write-NSPolicyError ('shift-policy: toolingPolicy: must be one of ' + ($script:NSPolicyToolingPolicies -join ', '))
            return 2
        }
        $document['toolingPolicy'] = $ToolingPolicy
    }
    if (-not [string]::IsNullOrEmpty($Execution)) {
        if (-not (Test-NSEvidenceEnum $Execution $script:NSPolicyExecutions)) {
            Write-NSPolicyError ('shift-policy: execution: must be one of ' + ($script:NSPolicyExecutions -join ', '))
            return 2
        }
        $document['execution'] = $Execution
    }
    if (-not [string]::IsNullOrEmpty($Hours)) {
        if ($Hours -ceq 'null') {
            $document['hours'] = $null
        }
        elseif ($Hours -cmatch '^[0-9]+$') {
            $document['hours'] = [long]$Hours
        }
        else {
            Write-NSPolicyError 'shift-policy: hours: must be a whole number of hours or null'
            return 2
        }
    }
    $document['updatedAt'] = Get-NSPolicyNow
    Write-NSEvidenceFileAtomic -Path $paths['defaults'] -Text ((ConvertTo-NSCanonicalJson $document) + "`n")
    return 0
}

# ---------------------------------------------------------------------------
# The resolver
# ---------------------------------------------------------------------------

function New-NSPolicySetting {
    param($Value, [Parameter(Mandatory = $true)][string]$Source, [Parameter(Mandatory = $true)][string]$Expiry)
    $entry = New-NSOrdinalMap
    $entry['value'] = $Value
    $entry['source'] = $Source
    $entry['expiry'] = $Expiry
    return $entry
}

# A key the owner wrote is an owner decision even when its value is empty, so
# presence - not emptiness - decides the source.
function Test-NSRuleKeyPresent {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $rules = Get-NSRulesObject $Workspace
    if ($null -eq $rules) { return $false }
    return ($null -ne $rules.PSObject.Properties[$Key])
}

function Get-NSPolicyRuleSetting {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Key
    )
    $value = Get-NSRule $Workspace $Key ''
    if (Test-NSRuleKeyPresent $Workspace $Key) { return (New-NSPolicySetting $value 'rules' 'permanent') }
    return (New-NSPolicySetting $value 'built-in' '-')
}

function Get-NSPolicyRuleInteger {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Key,
        [Parameter(Mandatory = $true)][long]$Fallback
    )
    $value = Get-NSRule $Workspace $Key ''
    if ($value -cmatch '^-?[0-9]+$') { return (New-NSPolicySetting ([long]$value) 'rules' 'permanent') }
    return (New-NSPolicySetting $Fallback 'built-in' '-')
}

function Get-NSPolicyDeadlineFile {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $path = (Get-NSPolicyPaths $Workspace)['deadline']
    if ((Test-NSReparsePoint $path) -or -not (Test-Path -LiteralPath $path -PathType Leaf)) { return $null }
    $raw = ''
    try {
        $raw = ([IO.File]::ReadAllText($path, $script:NSUtf8NoBom)).Trim()
    }
    catch {
        return $null
    }
    if ($raw -cmatch '^[0-9]+$') { return [long]$raw }
    return $null
}

# The one resolver. Precedence, top to bottom: an allowance in tonight's policy,
# then rules.json, then the built-in default. Protected paths, never-commit
# patterns and the expected email come from rules.json alone - no allowance lifts
# them - and shift-defaults.json never appears as the source of a value.
function Get-NSPolicyResolution {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $paths = Get-NSPolicyPaths $Workspace
    $state = Get-NSShiftPolicyState $Workspace
    $policy = $state['policy']
    $settings = New-NSOrdinalMap

    # The built-in shift is the shipped fast profile: no gate cadence, existing
    # tools, no deadline. Only tonight's policy moves any of the three.
    $settings['verificationLevel'] = New-NSPolicySetting 'none' 'built-in' '-'
    $settings['toolingPolicy'] = New-NSPolicySetting 'existing-tools' 'built-in' '-'
    $settings['deadlineEpoch'] = New-NSPolicySetting $null 'built-in' '-'
    if ($null -ne $policy) {
        $settings['verificationLevel'] = New-NSPolicySetting $policy['verificationLevel'] 'one-shift' 'shift'
        $settings['toolingPolicy'] = New-NSPolicySetting $policy['toolingPolicy'] 'one-shift' 'shift'
        $deadline = Get-NSMapValue $policy 'deadlineEpoch'
        if (Test-NSJsonInteger $deadline) {
            $settings['deadlineEpoch'] = New-NSPolicySetting ([long]$deadline) 'one-shift' 'shift'
        }
    }

    foreach ($category in $script:NSPolicyCategories) {
        $entry = New-NSPolicySetting 'deny' 'built-in' '-'
        $rulePolicy = Get-NSElevationRulePolicy $Workspace $category
        if (-not [string]::IsNullOrEmpty($rulePolicy)) {
            $entry = New-NSPolicySetting $rulePolicy 'rules' 'permanent'
        }
        $allowance = Get-NSPolicyCategoryAllowance $policy $category
        if ($null -ne $allowance) {
            $provenance = [string]$allowance['provenance']
            if ($provenance -ceq 'rules') {
                $entry = New-NSPolicySetting 'allow' 'rules' 'permanent'
            }
            else {
                $entry = New-NSPolicySetting 'allow' 'one-shift' 'shift'
            }
        }
        elseif ((Get-NSPolicyExactPlanAllowances $policy $category).Count -gt 0) {
            $entry = New-NSPolicySetting 'exact-plan' 'exact-plan' 'shift'
        }
        $settings['elevation.' + $category] = $entry
    }

    $settings['forbiddenCommands'] = Get-NSPolicyRuleSetting $Workspace 'forbiddenCommands'
    $settings['protectedDirs'] = Get-NSPolicyRuleSetting $Workspace 'protectedDirs'
    $settings['neverCommitPatterns'] = Get-NSPolicyRuleSetting $Workspace 'neverCommitPatterns'
    $settings['expectedEmail'] = Get-NSPolicyRuleSetting $Workspace 'expectedEmail'
    $settings['stallMax'] = Get-NSPolicyRuleInteger $Workspace 'stallMax' 0
    $settings['watchMinutes'] = Get-NSPolicyRuleInteger $Workspace 'watchMinutes' 10

    $resolution = New-NSOrdinalMap
    $resolution['settings'] = $settings
    $resolution['policy'] = $policy
    $resolution['policyState'] = $state['state']
    $resolution['policyError'] = $state['error']
    $resolution['deadlineFile'] = Get-NSPolicyDeadlineFile $Workspace
    $resolution['deadlinePolicy'] = $settings['deadlineEpoch']['value']
    $resolution['legacyCapabilityPolicy'] = (Test-Path -LiteralPath $paths['legacy'] -PathType Leaf)
    return $resolution
}

function Get-NSPolicyAllowances {
    param($Policy, [Parameter(Mandatory = $true)][string]$Category)
    $found = New-Object Collections.Generic.List[object]
    if ($null -eq $Policy) { return , $found }
    $allowances = Get-NSPolicyField $Policy 'allowances'
    if ($null -eq $allowances) { return , $found }
    foreach ($allowance in @($allowances)) {
        if (-not ($allowance -is [Collections.IDictionary])) { continue }
        $candidate = Get-NSMapValue $allowance 'category'
        if (($candidate -is [string]) -and ($candidate -ceq $Category)) { $found.Add($allowance) }
    }
    return , $found
}

function Get-NSPolicyCategoryAllowance {
    param($Policy, [Parameter(Mandatory = $true)][string]$Category)
    foreach ($allowance in (Get-NSPolicyAllowances $Policy $Category)) {
        $scope = Get-NSMapValue $allowance 'scope'
        if (($scope -is [string]) -and ($scope -ceq 'category')) { return $allowance }
    }
    return $null
}

function Get-NSPolicyExactPlanAllowances {
    param($Policy, [Parameter(Mandatory = $true)][string]$Category)
    $plans = New-Object Collections.Generic.List[object]
    foreach ($allowance in (Get-NSPolicyAllowances $Policy $Category)) {
        $scope = Get-NSMapValue $allowance 'scope'
        if (($scope -is [string]) -and ($scope -ceq 'exact-plan')) { $plans.Add($allowance) }
    }
    return , $plans
}

function Format-NSPolicyValue {
    param($Value)
    if ($null -eq $Value) { return 'none' }
    if (Test-NSJsonInteger $Value) { return ([long]$Value).ToString([Globalization.CultureInfo]::InvariantCulture) }
    return [string]$Value
}

function Format-NSPolicyTable {
    param($Resolution)
    $settings = $Resolution['settings']
    $lines = New-Object Collections.Generic.List[string]
    foreach ($name in (Sort-NSOrdinal $script:NSPolicySettingNames)) {
        $entry = $settings[$name]
        $lines.Add(('{0}={1} ({2}, {3})' -f $name, (Format-NSPolicyValue $entry['value']), $entry['source'], $entry['expiry']))
    }
    return , $lines.ToArray()
}

function Resolve-NSPolicy {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [switch]$Json,
        [switch]$Table
    )
    if ($Table -and $Json) {
        throw 'choose one of -Json or -Table'
    }
    $resolution = Get-NSPolicyResolution $Workspace
    if ($Table) {
        return ((Format-NSPolicyTable $resolution) -join "`n")
    }
    $document = New-NSOrdinalMap
    $document['schemaVersion'] = 1
    $document['settings'] = $resolution['settings']
    return (ConvertTo-NSCanonicalJson $document -Compact)
}

# The gate honours the earlier of the two, so a deadline file that drifts from
# the policy shortens the night rather than extending it.
function Get-NSPolicyDeadlineEpoch {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $resolution = Get-NSPolicyResolution $Workspace
    $file = $resolution['deadlineFile']
    $fromPolicy = $resolution['deadlinePolicy']
    if ($null -eq $file) { return $fromPolicy }
    if ($null -eq $fromPolicy) { return $file }
    if ([long]$file -lt [long]$fromPolicy) { return [long]$file }
    return [long]$fromPolicy
}

# 0 allow - 1 deny - 2 the category is denied and no exact plan covers this
# command. The caller has already matched the command against the category
# pattern; this answers only whether the shift permits it.
function Test-NSPolicyAllowed {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Command
    )
    if (-not ($script:NSPolicyCategories -ccontains $Category)) { return 1 }
    $resolution = Get-NSPolicyResolution $Workspace
    $value = [string]$resolution['settings']['elevation.' + $Category]['value']
    if ($value -ceq 'allow') { return 0 }
    if ($value -cne 'exact-plan') { return 1 }
    if (Test-NSPolicyExactPlan -Workspace $Workspace -Resolution $resolution -Category $Category -Command $Command) { return 0 }
    return 2
}

# An exact plan binds the command, the resolved work target, the shift identity
# and the deadline. Any drift is a mismatch, never a fall-through to the category.
function Test-NSPolicyExactPlan {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)]$Resolution,
        [Parameter(Mandatory = $true)][string]$Category,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Command
    )
    $policy = $Resolution['policy']
    if ($null -eq $policy) { return $false }
    $deadline = $Resolution['deadlinePolicy']
    if ($null -ne $deadline -and (Get-NSUnixTime) -gt [long]$deadline) { return $false }
    $target = $Workspace
    try {
        $target = Resolve-NSWorkTarget $Workspace
    }
    catch {
        $target = Get-NSAbsolutePath $Workspace
    }
    $shiftId = [string]$policy['shiftId']
    $normalized = Get-NSPolicyNormalizedCommand $Command
    foreach ($allowance in (Get-NSPolicyExactPlanAllowances $policy $Category)) {
        $plan = Get-NSMapValue $allowance 'plan'
        if ($null -eq $plan) { continue }
        # A plan may expire before the shift does; a plan with no expiry of its
        # own defers to the shift deadline checked above.
        $planExpiry = Get-NSMapValue $plan 'expiry'
        if ((Test-NSJsonInteger $planExpiry) -and (Get-NSUnixTime) -gt [long]$planExpiry) { continue }
        $planTarget = [string](Get-NSMapValue $plan 'workTarget')
        if (-not ($planTarget -ceq (Get-NSAbsolutePath $target))) { continue }
        $commands = New-Object Collections.Generic.List[string]
        foreach ($command in @(Get-NSPolicyField $plan 'commands')) { $commands.Add([string]$command) }
        $expected = Get-NSPolicyPlanDigest -Commands $commands.ToArray() -WorkTarget $planTarget -ShiftId $shiftId
        if (-not ($expected -ceq [string](Get-NSMapValue $plan 'digest'))) { continue }
        foreach ($command in $commands) {
            if ((Get-NSPolicyNormalizedCommand $command) -ceq $normalized) { return $true }
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Permission preflight - a filter for surprises, never a guarantee. It reports
# and exits 0; only the owner lifts a category.
# ---------------------------------------------------------------------------

function Get-NSPreflightTitle {
    param([AllowEmptyString()][string]$Line)
    $title = $Line.Trim()
    $title = [regex]::Replace($title, '^-\s*\[[ xX]\]\s*', '')
    $title = [regex]::Replace($title, '^#+\s*', '')
    $title = $title.Replace('**', '')
    return $title.Trim()
}

function Get-NSPreflightSectionItems {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory = $true)][string]$Source,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FallbackTitle
    )
    $items = New-Object Collections.Generic.List[object]
    $current = $null
    $sawBox = $false
    $text = New-Object Text.StringBuilder
    foreach ($line in $Lines) {
        # A ticked box is finished work: it closes the item above it and starts
        # nothing, so no allowance is ever reported or parked for it.
        if ($line -match '^-\s*\[[xX]\]') {
            $sawBox = $true
            if ($null -ne $current) {
                $current['text'] = $text.ToString()
                $items.Add($current)
                $current = $null
            }
            continue
        }
        if ($line -match '^-\s*\[ \]') {
            $sawBox = $true
            if ($null -ne $current) {
                $current['text'] = $text.ToString()
                $items.Add($current)
            }
            $current = New-NSOrdinalMap
            $current['title'] = Get-NSPreflightTitle $line
            $current['source'] = $Source
            $text = New-Object Text.StringBuilder
        }
        if ($null -ne $current) {
            $null = $text.Append($line)
            $null = $text.Append("`n")
        }
    }
    if ($null -ne $current) {
        $current['text'] = $text.ToString()
        $items.Add($current)
    }
    # A section that carries no box at all is itself the unit; one whose boxes are
    # all ticked has nothing left to need.
    if ($items.Count -eq 0 -and -not $sawBox -and -not [string]::IsNullOrEmpty($FallbackTitle)) {
        $item = New-NSOrdinalMap
        $item['title'] = $FallbackTitle
        $item['source'] = $Source
        $item['text'] = ($Lines -join "`n")
        $items.Add($item)
    }
    return , $items
}

function Get-NSPreflightFileLines {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ((Test-NSReparsePoint $Path) -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return , @() }
    try {
        return , ([regex]::Split([IO.File]::ReadAllText($Path, $script:NSUtf8NoBom), "\r\n|\n|\r"))
    }
    catch {
        return , @()
    }
}

function Get-NSPreflightItems {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $paths = Get-NSPolicyPaths $Workspace
    $items = New-Object Collections.Generic.List[object]

    $section = New-Object Collections.Generic.List[string]
    $inItems = $false
    foreach ($line in (Get-NSPreflightFileLines $paths['punch'])) {
        if (-not $inItems) {
            if ($line -match '^##\s+Items\s*$') { $inItems = $true }
            continue
        }
        if ($line -match '^##\s') { break }
        $section.Add($line)
    }
    foreach ($item in (Get-NSPreflightSectionItems -Lines $section.ToArray() -Source 'punch-list' -FallbackTitle '')) {
        $items.Add($item)
    }

    $orderLines = New-Object Collections.Generic.List[string]
    $orderTitle = ''
    foreach ($line in (Get-NSPreflightFileLines $paths['orders'])) {
        if ($line -match '^##\s+Work order') {
            if (-not [string]::IsNullOrEmpty($orderTitle)) {
                foreach ($item in (Get-NSPreflightSectionItems -Lines $orderLines.ToArray() -Source 'work-order' -FallbackTitle $orderTitle)) {
                    $items.Add($item)
                }
            }
            $orderTitle = Get-NSPreflightTitle $line
            $orderLines = New-Object Collections.Generic.List[string]
            continue
        }
        if ($line -match '^##\s') {
            if (-not [string]::IsNullOrEmpty($orderTitle)) {
                foreach ($item in (Get-NSPreflightSectionItems -Lines $orderLines.ToArray() -Source 'work-order' -FallbackTitle $orderTitle)) {
                    $items.Add($item)
                }
            }
            $orderTitle = ''
            $orderLines = New-Object Collections.Generic.List[string]
            continue
        }
        if (-not [string]::IsNullOrEmpty($orderTitle)) { $orderLines.Add($line) }
    }
    if (-not [string]::IsNullOrEmpty($orderTitle)) {
        foreach ($item in (Get-NSPreflightSectionItems -Lines $orderLines.ToArray() -Source 'work-order' -FallbackTitle $orderTitle)) {
            $items.Add($item)
        }
    }
    return , $items
}

function Get-NSPreflightReport {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $resolution = Get-NSPolicyResolution $Workspace
    $patterns = New-NSOrdinalMap
    foreach ($category in $script:NSPolicyCategories) {
        $pattern = Get-NSElevationPattern $Workspace $category
        $regex = $null
        try {
            $regex = New-NSPolicyRegex $pattern
        }
        catch {
            # An unreadable pattern is one reported defect. The category stays
            # denied and the hardhat guard still fails closed on the command.
            $regex = $null
        }
        $patterns[$category] = $regex
    }
    $patternErrors = New-Object Collections.Generic.List[string]
    foreach ($category in $script:NSPolicyCategories) {
        if ($null -eq $patterns[$category]) { $patternErrors.Add($category) }
    }
    $items = New-Object Collections.Generic.List[object]
    $gaps = New-Object Collections.Generic.List[object]
    foreach ($item in (Get-NSPreflightItems $Workspace)) {
        # An item quotes its commands in markdown; the backticks become spaces so
        # the shared elevation patterns read prose the way the guard reads a command.
        $text = ([string]$item['text']).Replace('`', ' ')
        $needs = New-Object Collections.Generic.List[object]
        foreach ($category in $script:NSPolicyCategories) {
            $regex = $patterns[$category]
            if ($null -eq $regex) { continue }
            if (-not $regex.IsMatch($text)) { continue }
            $value = [string]$resolution['settings']['elevation.' + $category]['value']
            $need = New-NSOrdinalMap
            $need['category'] = $category
            $need['resolved'] = $value
            $need['allowed'] = ($value -ceq 'allow')
            $needs.Add($need)
            if (-not $need['allowed']) {
                $gap = New-NSOrdinalMap
                $gap['category'] = $category
                $gap['title'] = $item['title']
                $gaps.Add($gap)
            }
        }
        $entry = New-NSOrdinalMap
        $entry['title'] = $item['title']
        $entry['source'] = $item['source']
        $entry['needs'] = $needs.ToArray()
        $items.Add($entry)
    }
    $report = New-NSOrdinalMap
    $report['schemaVersion'] = 1
    $report['items'] = $items.ToArray()
    $report['gaps'] = $gaps.ToArray()
    $report['patternErrors'] = $patternErrors.ToArray()
    return $report
}

function Get-NSPreflightNeeds {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [switch]$Json
    )
    $report = Get-NSPreflightReport $Workspace
    if ($Json) {
        return (ConvertTo-NSCanonicalJson $report -Compact)
    }
    $lines = New-Object Collections.Generic.List[string]
    $index = 0
    foreach ($item in $report['items']) {
        $index++
        $lines.Add(('item {0} ({1}): {2}' -f $index, $item['source'], $item['title']))
        if (@($item['needs']).Count -eq 0) {
            $lines.Add('  needs: none')
            continue
        }
        foreach ($need in $item['needs']) {
            $state = 'denied'
            if ($need['allowed']) { $state = 'allowed' }
            elseif ([string]$need['resolved'] -ceq 'exact-plan') { $state = 'exact-plan only' }
            $lines.Add(('  needs {0}: {1}' -f $need['category'], $state))
        }
    }
    if ($index -eq 0) {
        $lines.Add('items: none')
    }
    foreach ($category in $report['patternErrors']) {
        $lines.Add('pattern error: ' + $category + ' (rules.elevation pattern does not compile)')
    }
    $categories = New-Object Collections.Generic.List[string]
    foreach ($gap in $report['gaps']) {
        if (-not ($categories -ccontains [string]$gap['category'])) { $categories.Add([string]$gap['category']) }
    }
    if ($categories.Count -eq 0) {
        $lines.Add('gaps: none')
    }
    else {
        $lines.Add('gaps: ' + ((Sort-NSOrdinal $categories.ToArray()) -join ', '))
    }
    return ($lines -join "`n")
}

# One parking-lot entry per item and category, idempotent: Start may run twice
# over the same punch list and the owner still reads one entry per gap.
function Add-NSParkedNeeds {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $paths = Get-NSPolicyPaths $Workspace
    $report = Get-NSPreflightReport $Workspace
    $added = New-Object Collections.Generic.List[string]
    if (@($report['gaps']).Count -eq 0) { return , $added.ToArray() }
    $path = $paths['parking']
    if (Test-NSReparsePoint $path) {
        throw 'parking-lot.md is not a usable file'
    }
    $existing = ''
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $existing = [IO.File]::ReadAllText($path, $script:NSUtf8NoBom)
    }
    else {
        $existing = "# Parking Lot`n"
    }
    $dash = [string][char]0x2014
    $builder = New-Object Text.StringBuilder
    $null = $builder.Append($existing)
    if (-not $existing.EndsWith("`n")) { $null = $builder.Append("`n") }
    foreach ($gap in $report['gaps']) {
        $category = [string]$gap['category']
        $title = [string]$gap['title']
        $marker = '**needs allowance: {0}** {1} item "{2}"' -f $category, $dash, $title
        if ($builder.ToString().Contains($marker)) { continue }
        $null = $builder.Append("`n")
        $null = $builder.Append($marker)
        $null = $builder.Append((' needs the {0} elevation category, which is denied for this shift. Default: parked, worked last if the owner allows it before then.' -f $category))
        $null = $builder.Append("`n")
        $added.Add(('{0}: {1}' -f $category, $title))
    }
    if ($added.Count -gt 0) {
        Write-NSEvidenceFileAtomic -Path $path -Text $builder.ToString()
    }
    return , $added.ToArray()
}

# The legacy capability-policy.json carried one field the layered policy still
# uses: its tooling policy becomes the remembered prefill and the file goes.
function Invoke-NSMigrateCapabilityPolicy {
    param([Parameter(Mandatory = $true)][string]$Workspace)
    $paths = Get-NSPolicyPaths $Workspace
    $result = New-NSOrdinalMap
    $result['state'] = 'absent'
    $result['toolingPolicy'] = ''
    if (-not (Test-Path -LiteralPath $paths['legacy'] -PathType Leaf)) { return $result }
    if (Test-NSPolicyArmed $Workspace) {
        $result['state'] = 'armed'
        return $result
    }
    $tooling = ''
    try {
        $document = ConvertFrom-NSJsonText ([IO.File]::ReadAllText($paths['legacy'], $script:NSUtf8NoBom))
        $candidate = Get-NSMapValue $document 'policy'
        if (Test-NSEvidenceEnum $candidate $script:NSPolicyToolingPolicies) { $tooling = [string]$candidate }
    }
    catch {
        $tooling = ''
    }
    if ([string]::IsNullOrEmpty($tooling)) {
        $result['state'] = 'discarded'
    }
    else {
        if ((Set-NSShiftDefaults -Workspace $Workspace -ToolingPolicy $tooling) -ne 0) {
            $result['state'] = 'failed'
            return $result
        }
        $result['toolingPolicy'] = $tooling
        $result['state'] = 'migrated'
    }
    Remove-NSFile $paths['legacy']
    return $result
}

# ---------------------------------------------------------------------------
# Command surfaces for the thin runtime scripts
# ---------------------------------------------------------------------------

function Write-NSShiftPolicyUsage {
    Write-NSPolicyError 'usage: shift-policy.ps1 -Project DIR -Command {get|set|defaults-get|defaults-set|resolve|archive} ...'
    return 1
}

function Invoke-NSShiftPolicyArchive {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$Date
    )
    $paths = Get-NSPolicyPaths $Workspace
    if (-not (Test-Path -LiteralPath $paths['policy'] -PathType Leaf)) {
        Write-NSPolicyError 'shift-policy: no shift policy to archive'
        return 3
    }
    $state = Get-NSShiftPolicyState $Workspace
    $shiftId = 'unknown'
    if ($state['state'] -ceq 'valid') {
        $shiftId = [string]$state['policy']['shiftId']
    }
    else {
        Write-NSPolicyError ('shift-policy: ' + $state['error'] + '; archiving as shift-policy-unknown.json')
    }
    $directory = Join-NSPath $paths['archive'] $Date
    foreach ($candidate in @($paths['archive'], $directory)) {
        if (Test-NSReparsePoint $candidate) {
            Write-NSPolicyError 'shift-policy: refuse to write through a symlink archive path'
            return 2
        }
    }
    $null = [IO.Directory]::CreateDirectory($directory)
    $destination = Join-NSPath $directory ('shift-policy-' + $shiftId + '.json')
    Write-NSEvidenceFileAtomic -Path $destination -Text ([IO.File]::ReadAllText($paths['policy'], $script:NSUtf8NoBom))
    Remove-Item -LiteralPath $paths['policy'] -Force
    Write-NSPolicyOut $destination
    return 0
}

function Invoke-NSShiftPolicyCommand {
    param(
        [AllowEmptyString()][string]$Project = '',
        [AllowEmptyString()][string]$Command = '',
        [AllowEmptyString()][string]$FromJson = '',
        [AllowEmptyString()][string]$VerificationProfile = '',
        [AllowEmptyString()][string]$Hours = '',
        [AllowEmptyString()][string]$ToolingPolicy = '',
        [AllowEmptyString()][string]$Execution = '',
        [AllowEmptyString()][string]$Date = '',
        [switch]$Json,
        [switch]$Table
    )
    if ([string]::IsNullOrEmpty($Project) -or [string]::IsNullOrEmpty($Command)) { return (Write-NSShiftPolicyUsage) }
    $workspace = Get-NSAbsolutePath $Project
    $paths = Get-NSPolicyPaths $workspace
    switch ($Command) {
        'get' {
            if (-not (Test-Path -LiteralPath $paths['policy'] -PathType Leaf)) {
                Write-NSPolicyOut '{}'
                return 3
            }
            $text = [IO.File]::ReadAllText($paths['policy'], $script:NSUtf8NoBom)
            [Console]::Out.Write($text)
            if (-not $text.EndsWith("`n")) { [Console]::Out.Write("`n") }
            return 0
        }
        'set' {
            if ([string]::IsNullOrEmpty($FromJson)) { return (Write-NSShiftPolicyUsage) }
            $documentText = ''
            if ($FromJson -ceq '-') {
                $documentText = Get-NSStdinText
            }
            elseif (Test-Path -LiteralPath $FromJson -PathType Leaf) {
                $documentText = [IO.File]::ReadAllText($FromJson, $script:NSUtf8NoBom)
            }
            else {
                Write-NSPolicyError ('shift-policy: cannot read ' + $FromJson)
                return 2
            }
            return (Set-NSShiftPolicy -Workspace $workspace -Json $documentText)
        }
        'defaults-get' {
            Write-NSPolicyOut (ConvertTo-NSCanonicalJson (Get-NSShiftDefaults $workspace))
            return 0
        }
        'defaults-set' {
            return (Set-NSShiftDefaults -Workspace $workspace -VerificationProfile $VerificationProfile `
                    -Hours $Hours -ToolingPolicy $ToolingPolicy -Execution $Execution)
        }
        'resolve' {
            if ($Table) {
                Write-NSPolicyOut (Resolve-NSPolicy -Workspace $workspace -Table)
                return 0
            }
            Write-NSPolicyOut (Resolve-NSPolicy -Workspace $workspace -Json)
            return 0
        }
        'archive' {
            $day = $Date
            if ([string]::IsNullOrEmpty($day)) { $day = Get-Date -Format 'yyyy-MM-dd' }
            if ($day -cnotmatch '^[0-9]{4}-[0-9]{2}-[0-9]{2}$') {
                Write-NSPolicyError 'shift-policy: -Date must be YYYY-MM-DD'
                return 2
            }
            return (Invoke-NSShiftPolicyArchive -Workspace $workspace -Date $day)
        }
    }
    return (Write-NSShiftPolicyUsage)
}

function Invoke-NSPreflightNeedsCommand {
    param([AllowEmptyString()][string]$Project = '', [switch]$Json)
    if ([string]::IsNullOrEmpty($Project)) {
        Write-NSPolicyError 'usage: preflight-needs.ps1 -Project DIR [-Json]'
        return 1
    }
    Write-NSPolicyOut (Get-NSPreflightNeeds -Workspace (Get-NSAbsolutePath $Project) -Json:$Json)
    return 0
}

function Invoke-NSParkNeedsCommand {
    param([AllowEmptyString()][string]$Project = '')
    if ([string]::IsNullOrEmpty($Project)) {
        Write-NSPolicyError 'usage: park-needs.ps1 -Project DIR'
        return 1
    }
    $workspace = Get-NSAbsolutePath $Project
    if (-not (Test-Path -LiteralPath (Get-NSPolicyPaths $workspace)['ns'] -PathType Container)) {
        Write-NSPolicyError ('park-needs: no .nightshift/ at ' + $workspace)
        return 1
    }
    $added = Add-NSParkedNeeds -Workspace $workspace
    foreach ($entry in $added) { Write-NSPolicyOut ('parked ' + $entry) }
    Write-NSPolicyOut ('park-needs: added ' + $added.Count)
    return 0
}

Export-ModuleMember -Function *
