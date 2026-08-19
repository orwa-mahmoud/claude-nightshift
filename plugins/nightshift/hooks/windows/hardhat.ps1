param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('claude', 'codex')]
    [string]$HostName,
    [Parameter(ValueFromPipeline = $true)]
    [AllowEmptyString()]
    [string]$HookJson = ''
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking
$script:cwd = ''
$script:ns = ''

function Write-Deny {
    param([Parameter(Mandatory = $true)][string]$Reason)
    if ((Test-Path Variable:workspace) -and -not [string]::IsNullOrEmpty($workspace)) {
        $Reason = Expand-NSInjectedPaths $workspace $Reason
    }
    $output = @{
        hookSpecificOutput = @{
            hookEventName = 'PreToolUse'
            permissionDecision = 'deny'
            permissionDecisionReason = $Reason
        }
    }
    [Console]::Out.WriteLine(($output | ConvertTo-Json -Compress -Depth 5))
    exit 0
}

function Get-PropertyValue {
    param(
        [AllowNull()][object]$Object,
        [Parameter(Mandatory = $true)][string]$Name,
        [AllowNull()][object]$Default = ''
    )
    if ($null -eq $Object) {
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property -or $null -eq $property.Value) {
        return $Default
    }
    return $property.Value
}

function Remove-NSCommitMessage {
    param([AllowEmptyString()][string]$Command)

    $quotedPattern = @'
(?is)(?<!\S)(?<option>-m|--message)(?<separator>=|\s*)(?<value>'[^']*'|"(?:\\.|[^"])*")
'@
    $quoted = [Text.RegularExpressions.Regex]::new($quotedPattern)
    $Command = $quoted.Replace($Command, [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $value = $match.Groups['value'].Value
        $separator = $match.Groups['separator'].Value
        if ([string]::IsNullOrEmpty($separator) -and $value[0] -notin @("'", '"')) {
            return $match.Value
        }
        if ($value[0] -eq '"' -and ($value.Contains('$(') -or $value.Contains('`'))) {
            return $match.Value
        }
        return $match.Groups['option'].Value + $separator + 'MSG'
    })

    $plainPattern = @'
(?is)(?<!\S)(?<option>-m|--message)(?<separator>=|\s+)(?<value>[^\s'"]+)
'@
    $plain = [Text.RegularExpressions.Regex]::new($plainPattern)
    return $plain.Replace($Command, '${option}${separator}MSG')
}

function Get-NSNestedStrings {
    param([AllowNull()][object]$Value)
    if ($null -eq $Value) {
        return
    }
    if ($Value -is [string]) {
        $Value
        return
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [Management.Automation.PSCustomObject]) {
        foreach ($entry in $Value) {
            Get-NSNestedStrings $entry
        }
        return
    }
    foreach ($property in $Value.PSObject.Properties) {
        Get-NSNestedStrings $property.Value
    }
}

function Get-NSPayloadTargets {
    param(
        [AllowNull()][object]$ToolInput,
        [AllowEmptyString()][string]$ToolName,
        [AllowEmptyString()][string]$Command
    )
    if ($ToolName -in @('Bash', 'PowerShell')) {
        Remove-NSCommitMessage $Command
        return
    }
    if ($ToolName -eq 'apply_patch') {
        foreach ($line in ($Command -split "`r?`n")) {
            if ($line -match '^\*\*\* (?:Add|Update|Delete) File:\s*(.+)$' -or $line -match '^\*\*\* Move to:\s*(.+)$') {
                $Matches[1]
            }
        }
        return
    }
    if ($null -eq $ToolInput) {
        return
    }

    $pathKey = '(?i)((^|_)(path|filepath|file|filename|directory|dir|uri|name)$|^(target|destination|dest|source|src)$)'
    $commandKey = '(?i)(^|_)(command|cmd|script)$'
    function Walk-Input {
        param([AllowNull()][object]$Value)
        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) {
            return
        }
        if ($Value -is [Collections.IEnumerable] -and $Value -isnot [Management.Automation.PSCustomObject]) {
            foreach ($entry in $Value) {
                Walk-Input $entry
            }
            return
        }
        $directories = @()
        $names = @()
        foreach ($property in $Value.PSObject.Properties) {
            $strings = @(Get-NSNestedStrings $property.Value)
            if ($property.Name -match $commandKey) {
                foreach ($string in $strings) {
                    Remove-NSCommitMessage $string
                }
            }
            elseif ($property.Name -match $pathKey) {
                $strings
            }
            if ($property.Name -match '^(?i:directory|dir)$') {
                $directories += $strings
            }
            if ($property.Name -match '^(?i:name|filename|file)$') {
                $names += $strings
            }
            Walk-Input $property.Value
        }
        foreach ($directory in $directories) {
            foreach ($name in $names) {
                Join-Path $directory $name
            }
        }
    }
    Walk-Input $ToolInput
}

function Test-NSRulesTarget {
    param([AllowEmptyString()][string]$Target)
    $normalized = $Target.Replace('\', '/')
    return $normalized -match '(?i)\.nightshift/rules\.json|nightshift-rules\.json' `
        -or ($normalized -match '(?i)\.nightshift' -and $normalized -match '(?i)rules\.json')
}

function Test-NSLeaseTarget {
    param([AllowEmptyString()][string]$Target)
    $normalized = $Target.Replace('\', '/').Replace('"', '').Replace("'", '')
    if ($normalized -match '(?i)(^|/)(\.shift-lease|\.mutex-scope)($|[^A-Za-z0-9_-])|(^|/)\.lease-lock\.d($|/)') {
        return $true
    }
    $nightshiftContext = Test-NSNightshiftDirContext $normalized
    if ($nightshiftContext -and
        $normalized -match '(?i)\.nightshift/(?:\.\*|\*|\?|\[|\{|\$|`)') {
        return $true
    }
    if ($nightshiftContext -and $normalized -match '(?i)\.(shift|lease|mutex)-(?:\*|\?|\[|\{|\$|`)') {
        return $true
    }
    if ($normalized -match '(?i)(^|[;&|()\s])(rm|rmdir|unlink|mv|Remove-Item|Move-Item|Rename-Item)\s+([^;&|\r\n]*\s+)?(\./)?\.nightshift/?([;&|()\s]|$)') {
        return $true
    }
    if ($normalized -match '(?i)(^|[;&|\s])find(\s|$)' -and $normalized -match '(?i)\.nightshift' `
        -and $normalized -match '(?i)(-delete|-exec)') {
        return $true
    }
    return $false
}

function Test-NSNightshiftDirContext {
    param([AllowEmptyString()][string]$Normalized)
    # `cd .nightshift && unlink .shift-armed` has no slash after the directory name.
    if ($Normalized -match '(?i)\.nightshift([/\s;&]|$)') {
        return $true
    }
    if ($Normalized -match '(?i)(^|[;&|()\s])(cd|pushd|Set-Location)(?:\s+-LiteralPath)?\s+[''"]?\.nightshift\b') {
        return $true
    }
    $cwdValue = [string]$script:cwd
    $nsValue = [string]$script:ns
    if (-not [string]::IsNullOrEmpty($cwdValue) -and -not [string]::IsNullOrEmpty($nsValue)) {
        $cwdNorm = $cwdValue.Replace('\', '/').TrimEnd('/')
        $nsNorm = $nsValue.Replace('\', '/').TrimEnd('/')
        if ($cwdNorm -eq $nsNorm -or $cwdNorm.StartsWith("$nsNorm/")) {
            return $true
        }
    }
    return $false
}

function Test-NSControlRewritePath {
    param([AllowEmptyString()][string]$Target)
    $normalized = $Target.Replace('\', '/').Replace('"', '').Replace("'", '')
    return $normalized -match '(?i)(^|/|\.)nightshift/(STOP|\.shift-armed|\.ended|\.shift-session|work-target)(/|$|[^A-Za-z0-9_.-])'
}

function Test-NSControlListPath {
    param([AllowEmptyString()][string]$Target)
    $normalized = $Target.Replace('\', '/').Replace('"', '').Replace("'", '')
    return $normalized -match '(?i)(^|/|\.)nightshift/punch-list\.md(/|$|[^A-Za-z0-9_.-])'
}

function Test-NSControlRewriteName {
    param([AllowEmptyString()][string]$Target)
    return $Target -match '(?i)(^|[;&|()\s])(\./)?(STOP|\.shift-armed|\.ended|\.shift-session|work-target)([;&|()\s]|$)'
}

function Test-NSControlListName {
    param([AllowEmptyString()][string]$Target)
    return $Target -match '(?i)(^|[;&|()\s])(\./)?punch-list\.md([;&|()\s]|$)'
}

function Test-NSControlDeleteVerb {
    param([AllowEmptyString()][string]$Target)
    return $Target -match '(?i)(^|[;&|()\s])(rm|rmdir|unlink|mv|Remove-Item|Move-Item|Rename-Item)([\s]|$)'
}

function Test-NSControlTarget {
    param([AllowEmptyString()][string]$Target)
    $normalized = $Target.Replace('\', '/').Replace('"', '').Replace("'", '')
    if (Test-NSControlRewritePath $normalized) {
        return $true
    }
    if ((Test-NSControlListPath $normalized) -and (Test-NSControlDeleteVerb $normalized)) {
        return $true
    }
    if (Test-NSNightshiftDirContext $normalized) {
        if (Test-NSControlRewriteName $normalized) {
            return $true
        }
        if ((Test-NSControlListName $normalized) -and (Test-NSControlDeleteVerb $normalized)) {
            return $true
        }
    }
    return $false
}

function Convert-NSErePattern {
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

function New-NSRegex {
    param(
        [Parameter(Mandatory = $true)][string]$Pattern,
        [switch]$IgnoreCase
    )
    $options = [Text.RegularExpressions.RegexOptions]::Multiline
    if ($IgnoreCase) {
        $options = $options -bor [Text.RegularExpressions.RegexOptions]::IgnoreCase
    }
    return [Text.RegularExpressions.Regex]::new((Convert-NSErePattern $Pattern), $options)
}

function Test-NSGitVerb {
    param(
        [AllowEmptyString()][string]$Command,
        [Parameter(Mandatory = $true)][string]$Verb
    )
    return $Command -match '(?i)(^|[^A-Za-z0-9_-])git(?:\.exe)?([^A-Za-z0-9]|$)' `
        -and $Command -match ('(?i)(^|[^A-Za-z0-9_-]){0}([^A-Za-z0-9]|$)' -f [regex]::Escape($Verb))
}

function Resolve-NSCommandRepository {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$BaseDirectory,
        [Parameter(Mandatory = $true)][string]$Workspace
    )
    $directory = $null
    if ($Command -match '(?i)\bgit(?:\.exe)?\s+-C\s+["'']?([^"''\s;&|]+)') {
        $directory = $Matches[1]
    }
    elseif ($Command -match '(?i)^\s*(?:cd|Set-Location)(?:\s+-LiteralPath)?\s+["'']?([^"''\s;&|]+)["'']?\s*(?:&&|;)') {
        $directory = $Matches[1]
    }
    if ($null -ne $directory) {
        if (-not [IO.Path]::IsPathRooted($directory)) {
            $directory = Join-Path $BaseDirectory $directory
        }
        $top = Invoke-NSGit $directory @('rev-parse', '--show-toplevel')
        if ([string]::IsNullOrWhiteSpace($top)) {
            return $null
        }
        return (Resolve-NSCanonicalPath $top)
    }

    $top = Invoke-NSGit $BaseDirectory @('rev-parse', '--show-toplevel')
    if (-not [string]::IsNullOrWhiteSpace($top)) {
        return (Resolve-NSCanonicalPath $top)
    }
    try {
        return Resolve-NSWorkTarget $Workspace
    }
    catch {
        return $null
    }
}

function Get-NSProspectiveGitPaths {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Verb,
        [switch]$AsDiff
    )
    $gitDir = Invoke-NSGit $Repository @('rev-parse', '--absolute-git-dir')
    if ([string]::IsNullOrWhiteSpace($gitDir)) {
        return $null
    }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("ns-git-" + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $temp -Force
    $index = Join-Path $gitDir 'index'
    $copy = Join-Path $temp 'index'
    if (Test-Path -LiteralPath $index -PathType Leaf) {
        Copy-Item -LiteralPath $index -Destination $copy -Force
    }
    $env:GIT_INDEX_FILE = $copy
    try {
        $before = Invoke-NSGitCommand $Repository @('ls-files', '--stage')
        $beforePaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($line in $before.Lines) {
            $tab = $line.IndexOf("`t")
            if ($tab -ge 0) {
                [void]$beforePaths.Add($line.Substring($tab + 1).Replace('\', '/'))
            }
        }
        $words = @($Command -split '\s+' | Where-Object { $_ -ne '' })
        $start = [array]::IndexOf($words, $Verb)
        if ($start -lt 0) { return $null }
        $form = 'index'
        $paths = New-Object System.Collections.Generic.List[string]
        $rest = $false
        $skip = $false
        foreach ($word in $words[($start + 1)..($words.Length - 1)]) {
            if ($skip) { $skip = $false; continue }
            if ($rest) {
                if ($word -ne 'MSG') { $paths.Add($word) }
                continue
            }
            switch -Regex ($word) {
                '^--$' { $rest = $true; break }
                '^(--all|-A)$' { $form = $(if ($Verb -eq 'add') { 'all' } else { 'tracked' }); break }
                '^(--update|-u)$' { $form = 'tracked'; break }
                '^(--include|-i)$' { if ($Verb -eq 'commit') { $form = 'include' }; break }
                '^(--only|-o)$' { if ($Verb -eq 'commit') { $form = 'only' }; break }
                '^(-m|--message|--file|--author|--date|--cleanup)$' { $skip = $true; break }
                '^(--message=|--file=|--author=|--date=|MSG)' { break }
                '^(--allow-empty|--allow-empty-message|--no-verify|--no-edit|--quiet|--signoff|-q|-s|-n|--no-gpg-sign|--verbose|-v|--force|-f|--ignore-missing|--refresh|--porcelain)$' { break }
                # .NET has no POSIX [[:alpha:]]; clustered shorts like -am must use [A-Za-z].
                '^-[A-Za-z]*a[A-Za-z]*$' { if ($Verb -eq 'commit') { $form = 'tracked' }; break }
                '^-[A-Za-z]*i[A-Za-z]*$' { if ($Verb -eq 'commit') { $form = 'include' }; break }
                '^-[A-Za-z]*o[A-Za-z]*$' { if ($Verb -eq 'commit') { $form = 'only' }; break }
                '^-[A-Za-z]*A[A-Za-z]*$' { if ($Verb -eq 'add') { $form = 'all' }; break }
                '^-[A-Za-z]*u[A-Za-z]*$' { if ($Verb -eq 'add') { $form = 'tracked' }; break }
                '^-' { return $null }
                default { if ($word -ne 'MSG') { $paths.Add($word) }; break }
            }
        }
        if ($Verb -eq 'commit' -and $paths.Count -gt 0 -and $form -eq 'index') { $form = 'only' }
        $replay = $null
        switch ("$Verb-$form") {
            'add-all' { $replay = Invoke-NSGitCommand $Repository @('add', '-A') }
            'add-tracked' { $replay = Invoke-NSGitCommand $Repository @('add', '-u') }
            'add-index' {
                if ($paths.Count -gt 0) { $replay = Invoke-NSGitCommand $Repository (@('add', '--') + @($paths)) }
                else { $replay = [pscustomobject]@{ ExitCode = 0 } }
            }
            'commit-index' { $replay = [pscustomobject]@{ ExitCode = 0 } }
            'commit-tracked' { $replay = Invoke-NSGitCommand $Repository @('add', '-u') }
            'commit-include' {
                if ($paths.Count -gt 0) { $replay = Invoke-NSGitCommand $Repository (@('add', '--') + @($paths)) }
                else { $replay = [pscustomobject]@{ ExitCode = 0 } }
            }
            'commit-only' {
                $replay = Invoke-NSGitCommand $Repository @('read-tree', 'HEAD')
                if ($null -eq $replay -or $replay.ExitCode -ne 0) {
                    $replay = Invoke-NSGitCommand $Repository @('read-tree', '--empty')
                }
                if ($null -ne $replay -and $replay.ExitCode -eq 0 -and $paths.Count -gt 0) {
                    $replay = Invoke-NSGitCommand $Repository (@('add', '--') + @($paths))
                }
            }
            default { return $null }
        }
        if ($null -eq $replay -or $replay.ExitCode -ne 0) {
            return $null
        }
        if ($AsDiff) {
            $diff = Get-NSGitDiffText $Repository @('diff', '--cached', '--no-ext-diff', 'HEAD')
            if ($null -eq $diff) {
                $diff = Get-NSGitDiffText $Repository @('diff', '--cached', '--no-ext-diff')
            }
            return $diff
        }
        $changed = New-Object System.Collections.Generic.List[string]
        if ($Verb -eq 'add') {
            $after = Invoke-NSGitCommand $Repository @('ls-files', '--stage')
            $afterPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            $beforeLines = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
            foreach ($line in $before.Lines) {
                [void]$beforeLines.Add($line)
            }
            foreach ($line in $after.Lines) {
                $tab = $line.IndexOf("`t")
                if ($tab -ge 0) {
                    $path = $line.Substring($tab + 1).Replace('\', '/')
                    [void]$afterPaths.Add($path)
                    if (-not $beforeLines.Contains($line)) {
                        $changed.Add($path)
                    }
                }
            }
            foreach ($path in $beforePaths) {
                if (-not $afterPaths.Contains($path)) {
                    $changed.Add($path)
                }
            }
            return @($changed | Select-Object -Unique)
        }
        $listed = Get-NSGitDiffText $Repository @('diff', '--cached', '--name-only', '--no-ext-diff', 'HEAD')
        if ($null -eq $listed) {
            $listed = Get-NSGitDiffText $Repository @('diff', '--cached', '--name-only', '--no-ext-diff')
        }
        if ([string]::IsNullOrEmpty($listed)) { return @() }
        return @($listed -split "(`r`n|`n|`0)" | Where-Object { -not [string]::IsNullOrEmpty($_) })
    }
    finally {
        Remove-Item -LiteralPath $env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
        Remove-Item Env:GIT_INDEX_FILE -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Get-NSCommandDenyReason {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$Scrubbed,
        [Parameter(Mandatory = $true)][string]$CurrentDirectory,
        [Parameter(Mandatory = $true)][string]$Workspace,
        [AllowEmptyString()][string]$ProtectedDirectories,
        [AllowEmptyString()][string]$ExpectedEmail,
        [AllowEmptyString()][string]$NeverCommitPatterns,
        [AllowEmptyString()][string]$ForbiddenCommands
    )
    $forbiddenRegex = $null
    $neverRegex = $null
    try {
        if (-not [string]::IsNullOrEmpty($ForbiddenCommands)) {
            $forbiddenRegex = New-NSRegex $ForbiddenCommands
        }
        if (-not [string]::IsNullOrEmpty($NeverCommitPatterns)) {
            $neverRegex = New-NSRegex $NeverCommitPatterns -IgnoreCase
        }
    }
    catch {
        return 'BLOCKED: a Nightshift command or commit pattern is not a valid regular expression on this host. Fix the pattern in .nightshift/rules.json.'
    }

    $isGitWrite = (Test-NSGitVerb $Scrubbed 'add') -or (Test-NSGitVerb $Scrubbed 'commit') `
        -or (Test-NSGitVerb $Scrubbed 'tag') -or (Test-NSGitVerb $Scrubbed 'remote')
    if ($isGitWrite -and -not [string]::IsNullOrEmpty($ProtectedDirectories)) {
        $verb = $null
        if (Test-NSGitVerb $Scrubbed 'add') { $verb = 'add' }
        if (Test-NSGitVerb $Scrubbed 'commit') { $verb = 'commit' }
        if ($null -ne $verb) {
            $repository = Resolve-NSCommandRepository $Command $CurrentDirectory $Workspace
            if ([string]::IsNullOrEmpty($repository)) {
                return "BLOCKED: cannot tell which Git repository this $verb targets, so the protected-directory guard cannot run. Run it from inside the repository."
            }
            $paths = Get-NSProspectiveGitPaths $repository $Scrubbed $verb
            if ($null -eq $paths) {
                return "BLOCKED: this $verb uses a form the protected-directory guard cannot verify. Do not retry a rephrased form."
            }
            foreach ($path in $paths) {
                foreach ($directory in ($ProtectedDirectories -split '[\s|]+')) {
                    if ([string]::IsNullOrEmpty($directory)) { continue }
                    $normalized = $path.Replace('\', '/').TrimStart('./')
                    if ($normalized -eq $directory -or $normalized.StartsWith("$directory/") `
                        -or $normalized.EndsWith("/$directory") -or $normalized -match "/$([regex]::Escape($directory))/") {
                        return "BLOCKED: never git add/commit/tag/remote inside '$directory' (a protected directory). Do not retry a rephrased form."
                    }
                }
            }
        }
        else {
            $tokens = $Scrubbed -split '\s+'
            foreach ($directory in ($ProtectedDirectories -split '[\s|]+')) {
                if ([string]::IsNullOrEmpty($directory)) { continue }
                foreach ($token in $tokens) {
                    $clean = $token.Trim("'`"")
                    $parts = $clean.Replace('\', '/').Split('/')
                    if ($parts -contains $directory -or $clean -like "*=$directory" -or $clean -like "*=$directory/*") {
                        return "BLOCKED: never git add/commit/tag/remote inside '$directory' (a protected directory). Do not retry a rephrased form."
                    }
                }
            }
        }
    }

    $isCommit = Test-NSGitVerb $Scrubbed 'commit'
    if ($isCommit -and (-not [string]::IsNullOrEmpty($ExpectedEmail) -or $null -ne $neverRegex)) {
        if ($Scrubbed -match '(?i)--git-dir|--work-tree') {
            return 'BLOCKED: --git-dir/--work-tree point this commit somewhere the configured commit guards cannot verify. Run the commit from inside the repository instead.'
        }
        if (-not [string]::IsNullOrEmpty($ExpectedEmail) `
            -and $Scrubbed -match '(?i)-c\s*user\.email=|--author|GIT_(AUTHOR|COMMITTER)_EMAIL=|\$env:GIT_(AUTHOR|COMMITTER)_EMAIL') {
            return 'BLOCKED: this commit overrides the author identity on the command line, which the expected-identity guard cannot verify. Commit with the repository configured identity.'
        }
        $repository = Resolve-NSCommandRepository $Command $CurrentDirectory $Workspace
        if ([string]::IsNullOrEmpty($repository)) {
            return 'BLOCKED: cannot tell which Git repository this commit targets, so the configured commit guards cannot run. Run the commit from inside the repository.'
        }
        if (-not [string]::IsNullOrEmpty($ExpectedEmail)) {
            $email = Invoke-NSGit $repository @('config', 'user.email')
            if ($email -ne $ExpectedEmail) {
                return "BLOCKED: Git user.email is '$email', expected '$ExpectedEmail'. Configure the repository identity before committing."
            }
        }
        if ($null -ne $neverRegex) {
            $diff = Get-NSProspectiveGitPaths $repository $Scrubbed 'commit' -AsDiff
            if ($null -eq $diff) {
                return 'BLOCKED: this commit uses a form the never-commit guard cannot verify. Do not retry a rephrased form.'
            }
            if ($neverRegex.IsMatch([string]$diff)) {
                return 'BLOCKED: the diff this commit would write matches neverCommitPatterns. Remove the protected content before committing.'
            }
        }
    }

    if ($null -ne $forbiddenRegex -and $forbiddenRegex.IsMatch($Scrubbed)) {
        return 'BLOCKED: this command matches forbiddenCommands for the active shift. Do not retry a rephrased form.'
    }
    return ''
}

if ($env:NIGHTSHIFT_HARDHAT_LIB -eq '1') {
    return
}

$raw = Get-NSStdinText -Piped $HookJson
if ([string]::IsNullOrWhiteSpace($raw)) {
    $raw = Get-NSStdinText -Piped (($input | ForEach-Object { $_ }) -join "`n")
}
$payload = $null
if (-not [string]::IsNullOrWhiteSpace($raw)) {
    try {
        $payload = $raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $payload = $null
    }
}

$tool = [string](Get-PropertyValue $payload 'tool_name')
$toolInput = Get-PropertyValue $payload 'tool_input' $null
$command = [string](Get-PropertyValue $toolInput 'command')
if ([string]::IsNullOrEmpty($command)) {
    $command = [string](Get-PropertyValue $toolInput 'script')
}
$cwd = [string](Get-PropertyValue $payload 'cwd' ([Environment]::CurrentDirectory))
$sessionId = [string](Get-PropertyValue $payload 'session_id')
$transcript = [string](Get-PropertyValue $payload 'transcript_path')

if ($HostName -eq 'claude') {
    $hostRoot = if (-not [string]::IsNullOrEmpty($env:CLAUDE_PROJECT_DIR)) { $env:CLAUDE_PROJECT_DIR } else { $cwd }
}
else {
    $hostRoot = if (-not [string]::IsNullOrEmpty($env:CODEX_PROJECT_DIR)) { $env:CODEX_PROJECT_DIR } else { $cwd }
}
if ([string]::IsNullOrEmpty($hostRoot)) {
    $hostRoot = [Environment]::CurrentDirectory
}

try {
    $workspace = Resolve-NSWorkspaceRoot $hostRoot
}
catch {
    Write-Deny 'BLOCKED: .nightshift-link is invalid. Open the correct project task or repair the explicit link to an absolute workspace containing .nightshift/.'
}

$stateKind = Get-NSStateKind $workspace
if ($stateKind -in @('malformed', 'future')) {
    Write-Deny ('BLOCKED: ' + (Get-NSStateRefuseMessage $stateKind))
}

$ns = Join-Path $workspace '.nightshift'
$punch = Join-Path $ns 'punch-list.md'
$armed = Join-Path $ns '.shift-armed'
$ended = Join-Path $ns '.ended'
$counts = Get-NSBoxCounts $punch
$active = (Test-Path -LiteralPath $armed -PathType Leaf) -and (Test-Path -LiteralPath $punch -PathType Leaf) `
    -and -not (Test-Path -LiteralPath $ended -PathType Leaf) -and $counts.Open -gt 0

$token = [string]$env:NIGHTSHIFT_LEASE_TOKEN
$generation = [string]$env:NIGHTSHIFT_LEASE_GENERATION
$revival = $env:NIGHTSHIFT_REVIVAL -eq '1'

if (-not $active) {
    if ($revival -and (-not (Test-NSLeaseToken $ns $HostName $token $generation) `
        -or -not (Test-Path -LiteralPath $armed -PathType Leaf) `
        -or -not (Test-Path -LiteralPath $punch -PathType Leaf) `
        -or (Test-Path -LiteralPath $ended -PathType Leaf))) {
        Write-Deny 'BLOCKED: this recovered worker no longer owns an active shift. Do not continue after clock-out.'
    }
    exit 0
}

if ($null -eq $payload) {
    Write-Deny 'BLOCKED: the hook payload is unreadable while a shift is active. Retry after the host can provide valid hook JSON.'
}

$targets = @(Get-NSPayloadTargets $toolInput $tool $command)
foreach ($target in $targets) {
    if (Test-NSLeaseTarget ([string]$target)) {
        Write-Deny 'BLOCKED: the process lease is runtime-owned, as is its mutex identity. Do not read, delete, or rewrite either file; issue STOP from another session if ownership must be reset.'
    }
}

$unbound = Resolve-NSShiftUnbound -NightshiftDir $ns -HostName $HostName `
    -Token $token -Generation $generation -Revival $revival -Mode hardhat
if ($unbound.Status -eq 'Pass') { exit 0 }
if ($unbound.Status -eq 'Fail') { Write-Deny $unbound.Message }

$hostProcess = Get-NSHostProcess $HostName
$processId = if ($null -eq $hostProcess) { '' } else { [string]$hostProcess.Id }
$processStart = if ($null -eq $hostProcess) { '' } else { [string]$hostProcess.Start }

$bindingProbe = ($tool -in @('Bash', 'PowerShell')) -and (
    $command.Trim() -in @(': nightshift-binding-probe', "`$null = 'nightshift-binding-probe'")
)
$bindingTools = @('Bash', 'PowerShell', 'AskUserQuestion', 'request_user_input', 'apply_patch', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit')

$session = Read-NSSession $ns
if ($null -eq $session -and -not [string]::IsNullOrEmpty($sessionId) -and $tool -in $bindingTools) {
    $null = Claim-NSSession $ns $sessionId $transcript $processId $processStart $HostName
}

$rebind = Resolve-NSShiftRebind -NightshiftDir $ns -HostName $HostName `
    -SessionId $sessionId -Transcript $transcript -ProcessId $processId `
    -ProcessStart $processStart -Token $token -Generation $generation `
    -Revival $revival -Mode hardhat
if ($rebind.Status -eq 'Pass') { exit 0 }
if ($rebind.Status -eq 'Fail') { Write-Deny $rebind.Message }
$session = $rebind.Session

if ($bindingProbe) {
    if ([string]::IsNullOrEmpty($sessionId) -or $null -eq $session) {
        Write-Deny 'BLOCKED: Start could not bind this session atomically. Issue STOP, inspect with Doctor, and retry Start.'
    }
    if ($session.SessionId -ne $sessionId) {
        Write-Deny 'BLOCKED: another session already owns this shift. Reopen that conversation or issue STOP before running Start again.'
    }
}

$owned = Resolve-NSShiftAuthorize -NightshiftDir $ns -HostName $HostName `
    -SessionId $sessionId -ProcessId $processId -ProcessStart $processStart `
    -Token $token -Generation $generation -Revival $revival -Mode hardhat `
    -Session $session
if ($owned.Status -eq 'Pass') { exit 0 }
if ($owned.Status -eq 'Fail') { Write-Deny $owned.Message }
$session = $owned.Session

try {
    $toolRules = Get-NSToolRules $workspace ([string]$env:NIGHTSHIFT_TOOL_RULES)
}
catch {
    Write-Deny 'BLOCKED: toolDeny is not a JSON object of string values, so the tool rules cannot run. Fix .nightshift/rules.json or run Setup again.'
}

foreach ($target in $targets) {
    if (Test-NSRulesTarget ([string]$target)) {
        Write-Deny 'BLOCKED: the rules file is the owner''s - the night neither reads nor rewrites its own rules. Park the need in .nightshift/parking-lot.md and keep working.'
    }
}

$controlPassive = $tool -in @(
    'Read', 'Grep', 'Glob', 'LS', 'WebFetch', 'WebSearch', 'Task', 'TodoWrite',
    'AskUserQuestion', 'request_user_input', 'NotebookRead'
) -or $tool -match '(?i)read'
if (-not $controlPassive) {
    foreach ($target in $targets) {
        if (Test-NSControlTarget ([string]$target)) {
            Write-Deny 'BLOCKED: shift control files are owner-owned while the night is armed. Do not delete or forge .shift-armed, .ended, STOP, .shift-session, or work-target, and do not delete the punch list. Park the need in .nightshift/parking-lot.md and keep working.'
        }
    }
}

if ($tool -in @('AskUserQuestion', 'request_user_input')) {
    $property = if ($null -eq $toolRules) { $null } else { $toolRules.PSObject.Properties[$tool] }
    if ($null -eq $property) {
        Write-Deny "BLOCKED: toolDeny is missing the required '$tool' entry. Add that exact host tool name to .nightshift/rules.json with a denial message, or use an empty string to allow it; run Setup again to review the current template."
    }
    if (-not [string]::IsNullOrEmpty([string]$property.Value)) {
        Write-Deny ([string]$property.Value)
    }
    exit 0
}

if ($null -ne $toolRules -and -not [string]::IsNullOrEmpty($tool)) {
    $property = $toolRules.PSObject.Properties[$tool]
    if ($null -ne $property -and -not [string]::IsNullOrEmpty([string]$property.Value)) {
        Write-Deny ([string]$property.Value)
    }
}

if ($tool -in @('Bash', 'PowerShell')) {
    $scrubbed = Remove-NSCommitMessage $command
    $reason = Get-NSCommandDenyReason -Command $command -Scrubbed $scrubbed `
        -CurrentDirectory $cwd -Workspace $workspace `
        -ProtectedDirectories (Get-NSRule $workspace 'protectedDirs' ([string]$env:NIGHTSHIFT_PROTECTED_DIRS)) `
        -ExpectedEmail (Get-NSRule $workspace 'expectedEmail' ([string]$env:NIGHTSHIFT_EXPECTED_EMAIL)) `
        -NeverCommitPatterns (Get-NSRule $workspace 'neverCommitPatterns' ([string]$env:NIGHTSHIFT_NEVER_COMMIT_PATTERNS)) `
        -ForbiddenCommands (Get-NSRule $workspace 'forbiddenCommands' ([string]$env:NIGHTSHIFT_FORBIDDEN_COMMANDS))
    if (-not [string]::IsNullOrEmpty($reason)) {
        Write-Deny $reason
    }
}

exit 0
