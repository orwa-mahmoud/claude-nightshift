Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'
if (Test-Path Variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$plugin = Join-Path $repository 'plugins/nightshift'
$module = Join-Path $plugin 'lib/Nightshift.psm1'
$hardhat = Join-Path $plugin 'hooks/windows/hardhat.ps1'
$gate = Join-Path $plugin 'hooks/windows/clock-out-gate.ps1'
$setup = Join-Path $plugin 'runtime/windows/setup.ps1'
$schedule = Join-Path $plugin 'runtime/windows/schedule.ps1'
$watchman = Join-Path $plugin 'runtime/windows/watchman.ps1'
$startWatchman = Join-Path $plugin 'runtime/windows/start-watchman.ps1'
$linkWorkspace = Join-Path $plugin 'runtime/windows/link-workspace.ps1'
$claudeHardhatDispatch = Join-Path $plugin 'hooks/dispatch/claude-hardhat.ps1'
$claudeGateDispatch = Join-Path $plugin 'hooks/dispatch/claude-clock-out.ps1'
$claudeSessionEndDispatch = Join-Path $plugin 'hooks/dispatch/claude-session-end.ps1'
$codexHooksManifest = Join-Path $plugin 'hooks/codex/hooks.json'
$hostExecutable = (Get-Process -Id $PID).Path
$script:Assertions = 0

function Assert-True {
    param(
        [Parameter(Mandatory = $true)][bool]$Condition,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:Assertions++
    if (-not $Condition) {
        throw "assertion failed: $Message"
    }
}

function Assert-Equal {
    param(
        [AllowNull()][object]$Expected,
        [AllowNull()][object]$Actual,
        [Parameter(Mandatory = $true)][string]$Message
    )
    $script:Assertions++
    if ([string]$Expected -ne [string]$Actual) {
        throw "assertion failed: $Message (expected '$Expected', got '$Actual')"
    }
}

function Format-HookResult {
    param($Result)
    $stdout = if ($null -eq $Result) { '' } else { [string]$Result.Stdout }
    $stderr = if ($null -eq $Result) { '' } else { [string]$Result.Stderr }
    $code = if ($null -eq $Result) { '?' } else { $Result.ExitCode }
    return "exit=$code stdout='$stdout' stderr='$stderr'"
}

function Quote-TestArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value -notmatch '[\s"]' -and -not [string]::IsNullOrEmpty($Value)) {
        return $Value
    }
    $builder = New-Object Text.StringBuilder
    $null = $builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -eq '\') {
            $slashes++
            continue
        }
        if ($character -eq '"') {
            $null = $builder.Append(('\' * (($slashes * 2) + 1)))
            $null = $builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) {
            $null = $builder.Append(('\' * $slashes))
            $slashes = 0
        }
        $null = $builder.Append($character)
    }
    if ($slashes -gt 0) {
        $null = $builder.Append(('\' * ($slashes * 2)))
    }
    $null = $builder.Append('"')
    return $builder.ToString()
}

function Invoke-TestScript {
    param(
        [Parameter(Mandatory = $true)][string]$Script,
        [string[]]$Arguments = @(),
        [AllowEmptyString()][string]$InputText = '',
        [hashtable]$Environment = @{}
    )
    # Windows PowerShell 5.1 -File does not treat Process.StandardInput as
    # pipeline input. Pipe from this host so -HookJson binds.
    $managedKeys = @(
        @(Get-ChildItem Env: | Where-Object {
            $_.Name -like 'NIGHTSHIFT_*' -or $_.Name -in @(
                'CLAUDE_PROJECT_DIR', 'CODEX_PROJECT_DIR', 'CLAUDE_PLUGIN_ROOT', 'PLUGIN_ROOT'
            )
        } | ForEach-Object { $_.Name })
        @($Environment.Keys)
    ) | Select-Object -Unique
    $oldValues = @{}
    $wasPresent = @{}
    foreach ($key in $managedKeys) {
        $value = [Environment]::GetEnvironmentVariable([string]$key, 'Process')
        $wasPresent[[string]$key] = $null -ne $value
        $oldValues[[string]$key] = $value
        [Environment]::SetEnvironmentVariable([string]$key, $null, 'Process')
    }
    foreach ($key in $Environment.Keys) {
        [Environment]::SetEnvironmentVariable([string]$key, [string]$Environment[$key], 'Process')
    }
    $previous = $ErrorActionPreference
    $hadNative = Test-Path Variable:PSNativeCommandUseErrorActionPreference
    $previousNative = $false
    if ($hadNative) {
        $previousNative = $PSNativeCommandUseErrorActionPreference
        $PSNativeCommandUseErrorActionPreference = $false
    }
    $ErrorActionPreference = 'Continue'
    try {
        $argList = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $Script) + @($Arguments)
        $output = if ([string]::IsNullOrEmpty($InputText)) {
            & $hostExecutable @argList 2>&1
        }
        else {
            $InputText | & $hostExecutable @argList 2>&1
        }
        $stdoutLines = [Collections.Generic.List[string]]::new()
        $stderrLines = [Collections.Generic.List[string]]::new()
        foreach ($item in @($output)) {
            if ($item -is [Management.Automation.ErrorRecord]) {
                $stderrLines.Add([string]$item)
            }
            else {
                $stdoutLines.Add([string]$item)
            }
        }
        $code = $LASTEXITCODE
        if ($null -eq $code) {
            $code = 1
        }
        return [pscustomobject]@{
            ExitCode = [int]$code
            Stdout = ($stdoutLines -join "`n")
            Stderr = ($stderrLines -join "`n")
        }
    }
    finally {
        $ErrorActionPreference = $previous
        if ($hadNative) {
            $PSNativeCommandUseErrorActionPreference = $previousNative
        }
        foreach ($key in $managedKeys) {
            $restore = if ($wasPresent[[string]$key]) { $oldValues[[string]$key] } else { $null }
            [Environment]::SetEnvironmentVariable([string]$key, $restore, 'Process')
        }
    }
}

function Invoke-NSParallelScript {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$ScriptBlock,
        [Parameter(Mandatory = $true)][object[]]$ArgumentLists
    )
    $workers = foreach ($arguments in $ArgumentLists) {
        $shell = [PowerShell]::Create()
        $null = $shell.AddScript($ScriptBlock)
        foreach ($argument in @($arguments)) {
            $null = $shell.AddArgument($argument)
        }
        [pscustomobject]@{
            Shell = $shell
            Handle = $shell.BeginInvoke()
        }
    }
    foreach ($worker in $workers) {
        $output = @($worker.Shell.EndInvoke($worker.Handle))
        $errorText = (($worker.Shell.Streams.Error | ForEach-Object { $_.ToString() }) -join '; ')
        $worker.Shell.Dispose()
        if (-not [string]::IsNullOrEmpty($errorText)) {
            throw $errorText
        }
        if ($output.Count -eq 0) {
            $false
        }
        else {
            $output[$output.Count - 1]
        }
    }
}

function Invoke-TestCommandFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$InputText = '',
        [hashtable]$Environment = @{}
    )
    $managedKeys = @(
        @(Get-ChildItem Env: | Where-Object {
            $_.Name -like 'NIGHTSHIFT_*' -or $_.Name -in @(
                'CLAUDE_PROJECT_DIR', 'CODEX_PROJECT_DIR', 'CLAUDE_PLUGIN_ROOT', 'PLUGIN_ROOT'
            )
        } | ForEach-Object { $_.Name })
        @($Environment.Keys)
    ) | Select-Object -Unique
    $oldValues = @{}
    $wasPresent = @{}
    foreach ($key in $managedKeys) {
        $value = [Environment]::GetEnvironmentVariable([string]$key, 'Process')
        $wasPresent[[string]$key] = $null -ne $value
        $oldValues[[string]$key] = $value
        [Environment]::SetEnvironmentVariable([string]$key, $null, 'Process')
    }
    foreach ($key in $Environment.Keys) {
        [Environment]::SetEnvironmentVariable([string]$key, [string]$Environment[$key], 'Process')
    }
    $previousOutput = $OutputEncoding
    try {
        $OutputEncoding = New-Object Text.UTF8Encoding $false
        $output = ($InputText | & $env:ComSpec /D /C "`"$Path`"" 2>&1 | Out-String)
        $exitCode = $LASTEXITCODE
    }
    finally {
        $OutputEncoding = $previousOutput
        foreach ($key in $managedKeys) {
            $restore = if ($wasPresent[[string]$key]) { $oldValues[[string]$key] } else { $null }
            [Environment]::SetEnvironmentVariable([string]$key, $restore, 'Process')
        }
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Stdout = $output
        Stderr = ''
    }
}

function Initialize-TestWorkspace {
    param([Parameter(Mandatory = $true)][string]$Path)
    $null = New-Item -ItemType Directory -Path $Path -Force
    $repo = Join-Path $Path 'code repo'
    $null = New-Item -ItemType Directory -Path $repo -Force
    & git -C $repo init --quiet
    if ($LASTEXITCODE -ne 0) {
        throw 'git init failed'
    }
    $null = Invoke-NSGitCommand $repo @('config', 'core.autocrlf', 'false')
    $null = Invoke-NSGitCommand $repo @('config', 'user.email', 'dev@example.com')
    $null = Invoke-NSGitCommand $repo @('config', 'user.name', 'Nightshift Test')
    [IO.File]::WriteAllText((Join-Path $repo 'secret.txt'), "placeholder`n")
    $null = Invoke-NSGitCommand $repo @('add', '--', 'secret.txt')
    $seed = Invoke-NSGitCommand $repo @('commit', '--quiet', '-m', 'init')
    if ($seed.ExitCode -ne 0) {
        throw "initial work-target commit failed: $($seed.Text)"
    }
    $result = Invoke-TestScript $setup @('-Project', $Path, '-WorkTarget', $repo)
    Assert-Equal 0 $result.ExitCode "setup succeeds: $($result.Stderr)"
    try {
        $summary = $result.Stdout | ConvertFrom-Json
    }
    catch {
        throw "setup stdout was not JSON: $($result.Stdout)"
    }
    Assert-Equal (Resolve-Path $Path).ProviderPath $summary.workspace 'setup reports the workspace'
    Assert-Equal (Resolve-Path $repo).ProviderPath $summary.workTarget 'setup persists the work target'
    return $repo
}

function Set-TestPunch {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [bool]$Open = $true
    )
    $box = if ($Open) { '- [ ] Windows boundary' } else { '- [x] Windows boundary' }
    [IO.File]::WriteAllText(
        (Join-Path $Workspace '.nightshift/punch-list.md'),
        "# Contract`r`n`r`n## Items`r`n$box`r`n",
        (New-Object Text.UTF8Encoding($false))
    )
}

function Invoke-Hardhat {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$Tool,
        [Parameter(Mandatory = $true)][hashtable]$ToolInput,
        [hashtable]$ExtraEnvironment = @{}
    )
    $payload = @{
        session_id = $SessionId
        transcript_path = ''
        cwd = $Workspace
        tool_name = $Tool
        tool_input = $ToolInput
    } | ConvertTo-Json -Compress -Depth 10
    $environment = @{ CODEX_PROJECT_DIR = $Workspace }
    foreach ($key in $ExtraEnvironment.Keys) {
        $environment[$key] = $ExtraEnvironment[$key]
    }
    return Invoke-TestScript $hardhat @('-HostName', 'codex') $payload $environment
}

function Invoke-Gate {
    param(
        [Parameter(Mandatory = $true)][string]$Workspace,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [hashtable]$ExtraEnvironment = @{}
    )
    $payload = @{
        session_id = $SessionId
        transcript_path = ''
        cwd = $Workspace
        stop_hook_active = $true
    } | ConvertTo-Json -Compress
    $environment = @{ CODEX_PROJECT_DIR = $Workspace }
    foreach ($key in $ExtraEnvironment.Keys) {
        $environment[$key] = $ExtraEnvironment[$key]
    }
    return Invoke-TestScript $gate @('-HostName', 'codex') $payload $environment
}

$tempBase = if ([string]::IsNullOrEmpty($env:RUNNER_TEMP)) { [IO.Path]::GetTempPath() } else { $env:RUNNER_TEMP }
$root = Join-Path $tempBase ("nightshift windows {0}" -f [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root

try {
    Write-Host 'Checking PowerShell syntax'
    $powerShellFiles = @(Get-ChildItem -LiteralPath $plugin -Recurse -File |
        Where-Object { $_.Extension -in @('.ps1', '.psm1') })
    foreach ($file in $powerShellFiles) {
        $tokens = $null
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
        Assert-Equal 0 $errors.Count "$($file.FullName) parses"
    }

    Import-Module $module -Force -DisableNameChecking

    Write-Host 'Checking native setup and path handling'
    $workspace = Join-Path $root 'primary workspace'
    $workTarget = Initialize-TestWorkspace $workspace
    Assert-Equal 'current' (Get-NSStateKind $workspace) 'setup writes state version 1'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace '.nightshift/rules.json')) 'setup copies rules'
    $receiptSetup = Invoke-TestScript $setup @('-Project', $workspace, '-WorkTarget', $workTarget, '-Receipts')
    Assert-Equal 0 $receiptSetup.ExitCode "setup creates local receipts: $($receiptSetup.Stderr)"
    Assert-True (([IO.File]::ReadAllLines((Join-Path $workspace '.nightshift/.gitignore'))) -contains '.mutex-scope') `
        'setup keeps the private mutex identity out of receipts'
    $receiptIgnorePath = Join-Path $workspace '.nightshift/.gitignore'
    $legacyReceiptIgnore = @([IO.File]::ReadAllLines($receiptIgnorePath) |
        Where-Object { $_ -notin @('.mutex-scope', '.mutex-scope.tmp.*') })
    [IO.File]::WriteAllLines($receiptIgnorePath, $legacyReceiptIgnore, (New-Object Text.UTF8Encoding($false)))
    $customRules = Get-Content -LiteralPath (Join-Path $workspace '.nightshift/rules.json') -Raw
    $secondSetup = Invoke-TestScript $setup @('-Project', $workspace, '-WorkTarget', $workTarget)
    Assert-Equal 0 $secondSetup.ExitCode 'setup is idempotent'
    Assert-True (([IO.File]::ReadAllLines($receiptIgnorePath)) -contains '.mutex-scope') `
        'setup upgrades ignores in an existing receipts repository'
    Assert-Equal $customRules (Get-Content -LiteralPath (Join-Path $workspace '.nightshift/rules.json') -Raw) 'setup does not clobber rules'
    $workspaceNightshift = Join-Path $workspace '.nightshift'
    $receiptScope = Get-NSMutexScope $workspaceNightshift
    Assert-True ($receiptScope -match '^[a-f0-9]{32}$') 'mutex scope is created for the receipts workspace'
    & git -C $workspaceNightshift add --force -- .mutex-scope
    Assert-Equal 0 $LASTEXITCODE 'legacy tracked mutex identity fixture is staged'
    Assert-Equal 1 @(& git -C $workspaceNightshift ls-files -- .mutex-scope).Count `
        'legacy receipts fixture starts with a tracked mutex identity'
    Assert-Equal $receiptScope (Get-NSMutexScope $workspaceNightshift) `
        'receipt protection preserves the working mutex identity'
    Assert-Equal 0 @(& git -C $workspaceNightshift ls-files -- .mutex-scope).Count `
        'receipt protection removes the mutex identity from the index'
    Assert-True (([IO.File]::ReadAllLines((Join-Path $workspaceNightshift '.git/info/exclude'))) -contains '.mutex-scope') `
        'receipt protection excludes the mutex identity before use'
    $moduleSource = [IO.File]::ReadAllText($module)
    Assert-True ($moduleSource.Contains('"Global\Nightshift-$suffix"')) `
        'named mutexes use the machine-wide Windows namespace'
    Assert-True ($moduleSource.Contains('[Threading.MutexAcl]::Create')) `
        'PowerShell Core creates named mutexes with an explicit ACL'
    Assert-True ($moduleSource.Contains('function Resolve-NSShiftOwnership')) `
        'Windows hooks share one shift-ownership protocol'
    Assert-True (([IO.File]::ReadAllText($setup)).Contains('-DisableNameChecking')) `
        'setup import stays quiet so its JSON summary is the only stdout'

    $linkedHost = Join-Path $root 'linked host'
    $null = New-Item -ItemType Directory -Path $linkedHost
    & git -C $linkedHost init --quiet
    Assert-Equal 0 $LASTEXITCODE 'linked host Git repository initializes'
    $linked = Invoke-TestScript $linkWorkspace @('-HostRoot', $linkedHost, '-Workspace', $workspace)
    Assert-Equal 0 $linked.ExitCode "link-workspace succeeds: $($linked.Stderr)"
    Assert-Equal (Resolve-Path $workspace).ProviderPath (Resolve-NSWorkspaceRoot $linkedHost) 'absolute workspace links resolve'
    Assert-True (([IO.File]::ReadAllLines((Join-Path $linkedHost '.git/info/exclude'))) -contains '.nightshift-link') `
        'link-workspace keeps its local routing file out of Git'

    Write-Host 'Checking process evidence'
    $currentStart = Get-NSProcessStart $PID
    Assert-Equal 'Alive' (Test-NSRecordedProcess ([string]$PID) $currentStart) 'pid and start time identify the live process'
    Assert-Equal 'Dead' (Test-NSRecordedProcess ([string]$PID) '2000-01-01T00:00:00.0000000Z') 'a reused pid birthday is rejected'

    Write-Host 'Checking atomic concurrent ownership claims'
    $probeNightshift = Join-Path $root 'claim probe/.nightshift'
    $null = New-Item -ItemType Directory -Path $probeNightshift -Force
    try {
        Assert-True (Write-NSAtomicLines -Path (Join-Path $probeNightshift '.shift-session') `
            -Lines @('claim-probe', '', '', '', 'claude') -Private -CreateOnly) `
            'a sequential create-only write publishes .shift-session'
    }
    catch {
        throw "sequential create-only claim failed: $($_.Exception.Message)"
    }
    Assert-True (-not (Write-NSAtomicLines -Path (Join-Path $probeNightshift '.shift-session') `
        -Lines @('claim-probe-2', '', '', '', 'claude') -Private -CreateOnly)) `
        'a second create-only write loses to the existing session record'
    $claimWorkspace = Join-Path $root 'concurrent claim workspace'
    $claimNightshift = Join-Path $claimWorkspace '.nightshift'
    $null = New-Item -ItemType Directory -Path $claimNightshift -Force
    $claimArgLists = New-Object 'System.Collections.Generic.List[object]'
    foreach ($number in 1..8) {
        $claimArgLists.Add([pscustomobject]@{
                ModulePath = $module
                NightshiftDirectory = $claimNightshift
                SessionId = "claim-$number"
            })
    }
    $claimResults = @(Invoke-NSParallelScript -ScriptBlock {
            param($Work)
            Import-Module $Work.ModulePath -Force -DisableNameChecking
            Claim-NSSession $Work.NightshiftDirectory $Work.SessionId '' '' '' 'claude'
        } -ArgumentLists $claimArgLists.ToArray())
    $claimWins = @($claimResults | Where-Object { $_ -eq $true })
    Assert-Equal 1 $claimWins.Count "exactly one concurrent session claim wins (results: $($claimResults -join ','))"
    $claimedSession = Read-NSSession $claimNightshift
    Assert-True ($claimedSession.SessionId -match '^claim-[1-8]$') 'the winning claim is intact'
    $sessionAcl = Get-Acl -LiteralPath (Join-Path $claimNightshift '.shift-session')
    Assert-True $sessionAcl.AreAccessRulesProtected 'session identity has a protected Windows ACL'
    Assert-Equal 0 @(Get-ChildItem -LiteralPath $claimNightshift -Filter '.shift-session.tmp.*' -Force).Count `
        'private session claims leave no temporary capability file'
    $abandonedJob = Start-Job -ScriptBlock {
        param($ModulePath, $NightshiftDirectory)
        Import-Module $ModulePath -Force -DisableNameChecking
        $null = Enter-NSMutex $NightshiftDirectory '.abandoned-test'
    } -ArgumentList $module, $claimNightshift
    $null = Wait-Job -Job $abandonedJob
    Assert-Equal 'Completed' $abandonedJob.State 'mutex owner can terminate without explicit release'
    $abandonedJob | Receive-Job | Out-Null
    $abandonedJob | Remove-Job
    $reclaimedMutex = Enter-NSMutex $claimNightshift '.abandoned-test'
    Assert-True ($null -ne $reclaimedMutex) 'an abandoned named mutex is reclaimed by one successor'
    Exit-NSMutex $reclaimedMutex
    Assert-True (-not (Claim-NSSession (Join-Path $root 'missing/.nightshift') 'missing' '' '' '' 'claude')) `
        'an unavailable atomic-claim filesystem fails closed without crashing the hook'
    $claimAlias = Join-Path $root 'concurrent claim alias'
    $null = New-Item -ItemType Junction -Path $claimAlias -Target $claimWorkspace
    Assert-Equal (Get-NSMutexScope $claimNightshift) (Get-NSMutexScope (Join-Path $claimAlias '.nightshift')) `
        'junction aliases share one persisted mutex identity'
    $scopeAcl = Get-Acl -LiteralPath (Join-Path $claimNightshift '.mutex-scope')
    Assert-True $scopeAcl.AreAccessRulesProtected 'mutex identity has a protected Windows ACL'
    $heldMutex = Enter-NSMutex $claimNightshift '.alias-test'
    Assert-True ($null -ne $heldMutex) 'the canonical workspace acquires its alias-test mutex'
    $aliasJob = Start-Job -ScriptBlock {
        param($ModulePath, $AliasNightshift)
        Import-Module $ModulePath -Force -DisableNameChecking
        $candidate = Enter-NSMutex $AliasNightshift '.alias-test' 250
        if ($null -eq $candidate) {
            return $false
        }
        Exit-NSMutex $candidate
        return $true
    } -ArgumentList $module, (Join-Path $claimAlias '.nightshift')
    $null = Wait-Job -Job $aliasJob
    Assert-Equal $false ($aliasJob | Receive-Job) 'a junction alias cannot enter the held workspace mutex'
    $aliasJob | Remove-Job
    Exit-NSMutex $heldMutex
    $blockedRelease = Join-Path $root 'blocked release/.nightshift'
    $null = New-Item -ItemType Directory -Path (Join-Path $blockedRelease '.shift-lease') -Force
    [IO.File]::WriteAllText((Join-Path $blockedRelease '.shift-lease/child'), 'not a lease')
    Assert-True (-not (Release-NSLease $blockedRelease)) 'lease release reports a path it could not remove'

    Write-Host 'Checking hardhat and process lease boundaries'
    Set-TestPunch $workspace $true
    [IO.File]::WriteAllText((Join-Path $workspace '.nightshift/.shift-armed'), '')
    $sessionId = '11111111-1111-1111-1111-111111111111'
    # Codex reports shell calls to hooks with the canonical Bash tool name even on Windows.
    $probe = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = "`$null = 'nightshift-binding-probe'" }
    Assert-Equal 0 $probe.ExitCode "binding probe exits cleanly: $(Format-HookResult $probe)"
    Assert-True ([string]::IsNullOrWhiteSpace($probe.Stdout)) "winning binding probe is allowed ($(Format-HookResult $probe))"
    $session = Read-NSSession (Join-Path $workspace '.nightshift')
    $lease = Read-NSLease (Join-Path $workspace '.nightshift')
    Assert-Equal $sessionId $session.SessionId 'binding probe records the session'
    Assert-Equal 'codex' $lease.HostName 'binding probe creates a Codex lease'
    Assert-Equal 1 $lease.Generation 'initial lease is generation one'
    $acl = Get-Acl -LiteralPath (Join-Path $workspace '.nightshift/.shift-lease')
    Assert-True $acl.AreAccessRulesProtected 'lease capability has a protected Windows ACL'

    $loser = Invoke-Hardhat $workspace '22222222-2222-2222-2222-222222222222' 'Bash' @{ command = "`$null = 'nightshift-binding-probe'" }
    Assert-True ($loser.Stdout -match 'another session already owns') 'a second Start is denied'

    $leaseEdit = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = 'Remove-Item -Force .nightshift\.shift-*' }
    Assert-True ($leaseEdit.Stdout -match 'process lease is runtime-owned') 'indirect lease deletion is denied'
    $mutexEdit = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = 'Remove-Item -Force .nightshift\.mutex-*' }
    Assert-True ($mutexEdit.Stdout -match 'process lease is runtime-owned') 'indirect mutex-identity deletion is denied'
    $broadStateEdit = Invoke-Hardhat $workspace $sessionId 'Bash' `
        @{ command = 'Remove-Item -Recurse -Force .nightshift\*' }
    Assert-True ($broadStateEdit.Stdout -match 'process lease is runtime-owned') `
        'broad state-directory deletion is denied'

    $rulesRead = Invoke-Hardhat $workspace $sessionId 'Read' @{ path = (Join-Path $workspace '.nightshift/rules.json') }
    Assert-True ($rulesRead.Stdout -match 'rules file is the owner') 'rules reads are denied during a shift'

    $forbidden = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = 'git push origin HEAD' } `
        @{ NIGHTSHIFT_FORBIDDEN_COMMANDS = 'git .*push' }
    Assert-True ($forbidden.Stdout -match 'forbiddenCommands') 'PowerShell commands honor forbiddenCommands'

    $secretFile = Join-Path $workTarget 'secret.txt'
    [IO.File]::WriteAllText($secretFile, "SECRET_KEY=abc`n")
    $null = & git -C $workTarget add -- secret.txt
    $neverUpper = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = 'git commit -m x' } @{
        NIGHTSHIFT_NEVER_COMMIT_PATTERNS = 'secret_key'
    }
    Assert-True ($neverUpper.Stdout -match 'neverCommitPatterns') 'neverCommitPatterns is case-insensitive'

    $null = & git -C $workTarget reset --quiet HEAD -- secret.txt
    $amSecret = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = 'git commit -am x' } @{
        NIGHTSHIFT_NEVER_COMMIT_PATTERNS = 'secret_key'
    }
    Assert-True ($amSecret.Stdout -notmatch 'implicitly') "implicit staging inspects the real diff ($(Format-HookResult $amSecret))"
    Assert-True ($amSecret.Stdout -match 'neverCommitPatterns') "git commit -am still sees working-tree secrets ($(Format-HookResult $amSecret))"
    Remove-Item -LiteralPath $secretFile -Force
    $amClean = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = 'git commit -am x' } @{
        NIGHTSHIFT_NEVER_COMMIT_PATTERNS = 'secret_key'
    }
    Assert-True ([string]::IsNullOrWhiteSpace($amClean.Stdout)) 'a clean git commit -am is allowed'

    $unmapped = Invoke-Hardhat $workspace $sessionId 'Bash' @{ command = 'git status' } @{
        NIGHTSHIFT_FORBIDDEN_COMMANDS = '[[:punct:]]'
    }
    Assert-True ($unmapped.Stdout -match 'not a valid regular expression') `
        'unmapped POSIX classes fail closed'

    $helper = Invoke-Hardhat $workspace '33333333-3333-3333-3333-333333333333' 'WebSearch' @{ query = 'ordinary helper work' }
    Assert-True ([string]::IsNullOrWhiteSpace($helper.Stdout)) 'an unrelated conversation remains unrestricted'

    Write-Host 'Checking clock-out gate boundaries'
    $blocked = Invoke-Gate $workspace $sessionId
    Assert-True ($blocked.Stdout -match '"decision":"block"') 'an open punch list blocks Stop'

    $helperStop = Invoke-Gate $workspace '33333333-3333-3333-3333-333333333333'
    Assert-True ($helperStop.Stdout -match '"continue":true') 'another conversation stops freely'

    [IO.File]::WriteAllText((Join-Path $workspace '.nightshift/STOP'), "owner`r`n")
    $released = Invoke-Gate $workspace $sessionId
    Assert-True ($released.Stdout -match '"continue":true') 'STOP releases the shift'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $workspace '.nightshift/.shift-lease'))) 'clock-out releases the lease'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $workspace '.nightshift/.shift-armed'))) 'clock-out disarms the site'
    Assert-True (Test-Path -LiteralPath (Join-Path $workspace '.nightshift/.ended')) 'clock-out records the ending'

    Write-Host 'Checking Claude Windows dispatchers'
    $dispatchWorkspace = Join-Path $root 'dispatcher workspace'
    $null = Initialize-TestWorkspace $dispatchWorkspace
    Set-TestPunch $dispatchWorkspace $true
    [IO.File]::WriteAllText((Join-Path $dispatchWorkspace '.nightshift/.shift-armed'), '')
    $dispatchSession = 'dddddddd-dddd-dddd-dddd-dddddddddddd'
    $dispatchEnvironment = @{
        CLAUDE_PLUGIN_ROOT = $plugin
        CLAUDE_PROJECT_DIR = $dispatchWorkspace
    }
    $dispatchProbePayload = @{
        session_id = $dispatchSession
        transcript_path = ''
        cwd = $dispatchWorkspace
        tool_name = 'PowerShell'
        tool_input = @{ command = "`$null = 'nightshift-binding-probe'" }
    } | ConvertTo-Json -Compress -Depth 10
    $dispatchProbe = Invoke-TestScript $claudeHardhatDispatch @() $dispatchProbePayload $dispatchEnvironment
    Assert-Equal 0 $dispatchProbe.ExitCode "Claude hardhat dispatcher exits cleanly: $($dispatchProbe.Stderr)"
    Assert-True ([string]::IsNullOrWhiteSpace($dispatchProbe.Stdout)) 'Claude hardhat dispatcher allows the winning probe'
    Assert-Equal 'claude' (Read-NSSession (Join-Path $dispatchWorkspace '.nightshift')).HostName `
        'Claude hardhat dispatcher reaches the native hook'

    $dispatchGatePayload = @{
        session_id = $dispatchSession
        transcript_path = ''
        cwd = $dispatchWorkspace
        stop_hook_active = $true
    } | ConvertTo-Json -Compress
    $dispatchGate = Invoke-TestScript $claudeGateDispatch @() $dispatchGatePayload $dispatchEnvironment
    Assert-True ($dispatchGate.Stdout -match '"decision":"block"') 'Claude clock-out dispatcher reaches the native gate'

    $dispatchEndPayload = @{
        session_id = $dispatchSession
        cwd = $dispatchWorkspace
        reason = 'exit'
    } | ConvertTo-Json -Compress
    $dispatchEnd = Invoke-TestScript $claudeSessionEndDispatch @() $dispatchEndPayload $dispatchEnvironment
    Assert-Equal 0 $dispatchEnd.ExitCode "Claude SessionEnd dispatcher exits cleanly: $($dispatchEnd.Stderr)"
    Assert-True (Test-Path -LiteralPath (Join-Path $dispatchWorkspace '.nightshift/.session-end')) `
        'Claude SessionEnd dispatcher records the clean ending'

    [IO.File]::WriteAllText((Join-Path $dispatchWorkspace '.nightshift/STOP'), '')
    $dispatchRelease = Invoke-TestScript $claudeGateDispatch @() $dispatchGatePayload $dispatchEnvironment
    Assert-Equal 0 $dispatchRelease.ExitCode "Claude STOP dispatcher exits cleanly: $($dispatchRelease.Stderr)"
    Assert-True (Test-Path -LiteralPath (Join-Path $dispatchWorkspace '.nightshift/.ended')) `
        'Claude clock-out dispatcher releases STOP'

    Write-Host 'Checking Codex commandWindows entrypoints through cmd.exe'
    $codexHooks = Get-Content -LiteralPath $codexHooksManifest -Raw | ConvertFrom-Json
    $codexHardhatCommand = [string]$codexHooks.hooks.PreToolUse[0].hooks[0].commandWindows
    $codexGateCommand = [string]$codexHooks.hooks.Stop[0].hooks[0].commandWindows
    Assert-True ($codexHardhatCommand.Contains('%PLUGIN_ROOT%')) 'Codex hardhat uses cmd.exe environment syntax'
    Assert-True ($codexGateCommand.Contains('-ExecutionPolicy Bypass')) 'Codex gate bypasses script policy explicitly'
    $codexHardhatCommandFile = Join-Path $root 'codex hardhat.cmd'
    $codexGateCommandFile = Join-Path $root 'codex gate.cmd'
    [IO.File]::WriteAllText($codexHardhatCommandFile, "@echo off`r`n$codexHardhatCommand`r`n", [Text.Encoding]::ASCII)
    [IO.File]::WriteAllText($codexGateCommandFile, "@echo off`r`n$codexGateCommand`r`n", [Text.Encoding]::ASCII)

    $codexCommandWorkspace = Join-Path $root 'codex command workspace'
    $null = Initialize-TestWorkspace $codexCommandWorkspace
    Set-TestPunch $codexCommandWorkspace $true
    [IO.File]::WriteAllText((Join-Path $codexCommandWorkspace '.nightshift/.shift-armed'), '')
    $codexCommandSession = 'cccccccc-cccc-cccc-cccc-cccccccccccc'
    $codexCommandEnvironment = @{
        PLUGIN_ROOT = $plugin
        CODEX_PROJECT_DIR = $codexCommandWorkspace
    }
    $codexCommandProbePayload = @{
        session_id = $codexCommandSession
        transcript_path = ''
        cwd = $codexCommandWorkspace
        tool_name = 'Bash'
        tool_input = @{ command = "`$null = 'nightshift-binding-probe'" }
    } | ConvertTo-Json -Compress -Depth 10
    $codexCommandProbe = Invoke-TestCommandFile $codexHardhatCommandFile `
        $codexCommandProbePayload $codexCommandEnvironment
    Assert-Equal 0 $codexCommandProbe.ExitCode "Codex hardhat commandWindows exits cleanly: $($codexCommandProbe.Stdout)"
    Assert-True ([string]::IsNullOrWhiteSpace($codexCommandProbe.Stdout)) `
        "Codex hardhat commandWindows allows the winning probe ($(Format-HookResult $codexCommandProbe))"
    Assert-Equal 'codex' (Read-NSSession (Join-Path $codexCommandWorkspace '.nightshift')).HostName `
        'Codex commandWindows reaches the native hardhat'

    $codexCommandGatePayload = @{
        session_id = $codexCommandSession
        transcript_path = ''
        cwd = $codexCommandWorkspace
        stop_hook_active = $true
    } | ConvertTo-Json -Compress
    $codexCommandGate = Invoke-TestCommandFile $codexGateCommandFile `
        $codexCommandGatePayload $codexCommandEnvironment
    Assert-True ($codexCommandGate.Stdout -match '"decision":"block"') `
        'Codex gate commandWindows continues an open shift'
    [IO.File]::WriteAllText((Join-Path $codexCommandWorkspace '.nightshift/STOP'), '')
    $codexCommandRelease = Invoke-TestCommandFile $codexGateCommandFile `
        $codexCommandGatePayload $codexCommandEnvironment
    Assert-True ($codexCommandRelease.Stdout -match '"continue":true') `
        'Codex gate commandWindows releases STOP'

    Write-Host 'Checking Task Scheduler generation'
    Remove-Item -LiteralPath (Join-Path $workspace '.nightshift/STOP') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $workspace '.nightshift/.ended') -Force -ErrorAction SilentlyContinue
    $scheduled = Invoke-TestScript $schedule @('-Project', $workspace, '-At', '04:05', '-AsJson')
    Assert-Equal 0 $scheduled.ExitCode "scheduler generation succeeds: $($scheduled.Stderr)"
    $scheduleResult = $scheduled.Stdout | ConvertFrom-Json
    $taskXml = [xml]$scheduleResult.xml
    Assert-True ($scheduleResult.runScript.Contains($workspace)) 'scheduled command preserves a spaced workspace path'
    Assert-Equal '\' $scheduleResult.taskPath 'scheduled task uses the always-present root folder'
    Assert-Equal "$($scheduleResult.taskPath)$($scheduleResult.taskName)" $taskXml.Task.RegistrationInfo.URI 'task URI matches its root registration path'
    Assert-Equal 'IgnoreNew' $taskXml.Task.Settings.MultipleInstancesPolicy 'Task Scheduler refuses overlapping starts'
    Assert-Equal 'powershell.exe' $taskXml.Task.Actions.Exec.Command 'Task Scheduler invokes native PowerShell'
    Assert-True ($taskXml.Task.Actions.Exec.Arguments -match '-EncodedCommand') 'Task Scheduler avoids shell quoting loss'
    Assert-Equal 'InteractiveToken' $taskXml.Task.Principals.Principal.LogonType 'Task Scheduler declares its login boundary'
    $taskRegistered = $false
    try {
        $null = Register-ScheduledTask -TaskPath $scheduleResult.taskPath -TaskName $scheduleResult.taskName `
            -Xml $scheduleResult.xml -ErrorAction Stop
        $taskRegistered = $true
        $registeredTask = Get-ScheduledTask -TaskPath $scheduleResult.taskPath `
            -TaskName $scheduleResult.taskName -ErrorAction Stop
        Assert-Equal $scheduleResult.taskName $registeredTask.TaskName `
            'generated XML registers as a disposable native task'
        Assert-Equal '\' $registeredTask.TaskPath 'registered task remains in the existing root folder'
    }
    finally {
        if ($taskRegistered) {
            Unregister-ScheduledTask -TaskPath $scheduleResult.taskPath `
                -TaskName $scheduleResult.taskName -Confirm:$false -ErrorAction SilentlyContinue
        }
    }

    $preflight = Invoke-TestScript $schedule @('-Project', $workspace, '-Preflight')
    Assert-Equal 0 $preflight.ExitCode "scheduler preflight succeeds without a host subscription: $($preflight.Stderr)"
    Assert-True ($preflight.Stdout -match 'writes and registers nothing') 'preflight is generate-only'
    Assert-True ($preflight.Stdout -match 'headless Claude run may stall') `
        'preflight warns when Claude headless permissions are not evident'
    $codexPreflight = Invoke-TestScript $schedule @(
        '-Project', $workspace, '-Preflight', '-Agent', 'codex exec'
    )
    Assert-True ($codexPreflight.Stdout -match 'without a headless grant') `
        'preflight warns when a Codex command omits its sandbox grant'
    $codexGrantPreflight = Invoke-TestScript $schedule @(
        '-Project', $workspace, '-Preflight', '-Agent', 'codex exec -s danger-full-access'
    )
    Assert-True ($codexGrantPreflight.Stdout -match 'carries a headless sandbox grant') `
        'preflight recognizes an explicit Codex headless grant'

    Write-Host 'Checking native recovery and watchman placement'
    $recoveryWorkspace = Join-Path $root 'recovery workspace'
    $recoveryTarget = Initialize-TestWorkspace $recoveryWorkspace
    Set-TestPunch $recoveryWorkspace $true
    [IO.File]::WriteAllText((Join-Path $recoveryWorkspace '.nightshift/.shift-armed'), '')
    $recoverySession = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    $recoveryProbe = Invoke-Hardhat $recoveryWorkspace $recoverySession 'Bash' @{ command = "`$null = 'nightshift-binding-probe'" }
    Assert-Equal 0 $recoveryProbe.ExitCode 'recovery fixture binds'

    $agentReceipt = Join-Path $root 'agent receipt.txt'
    $agentStub = Join-Path $root 'agent stub.ps1'
    @'
param([string]$Prompt)
$record = @(
    [Environment]::CurrentDirectory,
    $env:NIGHTSHIFT_REVIVAL,
    $env:NIGHTSHIFT_LEASE_GENERATION,
    $env:NIGHTSHIFT_LEASE_TOKEN,
    $Prompt
)
[IO.File]::WriteAllLines($env:NIGHTSHIFT_TEST_AGENT_RECEIPT, $record)
exit 0
'@ | Set-Content -LiteralPath $agentStub -Encoding UTF8

    $watch = Invoke-TestScript $watchman `
        @('-Project', $recoveryWorkspace, '-HostName', 'codex', '-IntervalMinutes', '1', '-Agent', $agentStub, '-MaxWakes', '1') `
        '' @{ NIGHTSHIFT_WATCH_SLEEP = '0'; NIGHTSHIFT_TEST_AGENT_RECEIPT = $agentReceipt }
    Assert-Equal 7 $watch.ExitCode "one-wake recovery fixture reaches its test cap: $($watch.Stderr)"
    Assert-True (Test-Path -LiteralPath $agentReceipt) 'a dead session launches the recovery child'
    $receiptLines = [IO.File]::ReadAllLines($agentReceipt)
    Assert-Equal (Resolve-Path $recoveryTarget).ProviderPath $receiptLines[0] 'recovery child runs in the persisted work target'
    Assert-Equal '1' $receiptLines[1] 'recovery child inherits its revival mark'
    Assert-True ($receiptLines[2] -match '^[2-9][0-9]*$|^[2-9]$') 'watchman advances the lease generation'
    Assert-True (-not [string]::IsNullOrEmpty($receiptLines[3])) 'recovery child inherits a lease token'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $recoveryWorkspace '.nightshift/.watchman'))) 'watchman pid marker is cleaned'
    $recoveryAcl = Get-Acl -LiteralPath (Join-Path $recoveryWorkspace '.nightshift/.shift-lease')
    Assert-True $recoveryAcl.AreAccessRulesProtected 'lease takeover preserves the private ACL'

    $staleTool = Invoke-Hardhat $recoveryWorkspace $recoverySession 'Bash' @{ command = 'Get-Location' }
    Assert-True ($staleTool.Stdout -match 'continued in a recovered process') `
        'the pre-recovery process is fenced after lease takeover'
    $recoveredTool = Invoke-Hardhat $recoveryWorkspace $recoverySession 'Bash' @{ command = 'Get-Location' } @{
        NIGHTSHIFT_REVIVAL = '1'
        NIGHTSHIFT_LEASE_GENERATION = $receiptLines[2]
        NIGHTSHIFT_LEASE_TOKEN = $receiptLines[3]
    }
    Assert-True ([string]::IsNullOrWhiteSpace($recoveredTool.Stdout)) `
        'the child carrying the recovery capability remains allowed'
    Assert-True ((Get-Content -LiteralPath (Join-Path $recoveryWorkspace '.nightshift/parking-lot.md') -Raw) `
        -match 'the watchman revived it') 'revival writes an owner-facing parking-lot notice'

    Write-Host 'Checking default Codex recovery through an npm-style command shim'
    $codexRecoveryWorkspace = Join-Path $root 'codex shim recovery workspace'
    $null = Initialize-TestWorkspace $codexRecoveryWorkspace
    Set-TestPunch $codexRecoveryWorkspace $true
    [IO.File]::WriteAllText((Join-Path $codexRecoveryWorkspace '.nightshift/.shift-armed'), '')
    $codexRecoverySession = 'eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee'
    $codexRecoveryProbe = Invoke-Hardhat $codexRecoveryWorkspace $codexRecoverySession 'Bash' @{
        command = "`$null = 'nightshift-binding-probe'"
    }
    Assert-Equal 0 $codexRecoveryProbe.ExitCode 'Codex shim recovery fixture binds'
    $shimDirectory = Join-Path $root 'npm shim bin'
    $null = New-Item -ItemType Directory -Path $shimDirectory
    $codexShim = Join-Path $shimDirectory 'codex.cmd'
    $codexShimReceipt = Join-Path $root 'codex shim receipt.txt'
    [IO.File]::WriteAllText(
        $codexShim,
        "@echo off`r`n> `"%NIGHTSHIFT_TEST_CODEX_SHIM_RECEIPT%`" echo %*`r`nexit /b 0`r`n",
        [Text.Encoding]::ASCII
    )
    $shimWatch = Invoke-TestScript $watchman @(
        '-Project', $codexRecoveryWorkspace,
        '-HostName', 'codex',
        '-IntervalMinutes', '1',
        '-MaxWakes', '1'
    ) '' @{
        NIGHTSHIFT_WATCH_SLEEP = '0'
        NIGHTSHIFT_TEST_CODEX_SHIM_RECEIPT = $codexShimReceipt
        PATH = "$shimDirectory;$env:PATH"
    }
    Assert-Equal 7 $shimWatch.ExitCode "default Codex recovery reaches its test cap: $($shimWatch.Stderr)"
    Assert-True (Test-Path -LiteralPath $codexShimReceipt) `
        'default recovery resolves a standard codex.cmd launcher'
    $shimArguments = [IO.File]::ReadAllText($codexShimReceipt)
    Assert-True ($shimArguments -match 'exec\s+resume') 'Codex shim receives the resume subcommand'
    Assert-True ($shimArguments.Contains($codexRecoverySession)) 'Codex shim receives the recorded conversation id'

    $liveReceipt = Join-Path $root 'must not spawn.txt'
    $liveSession = Read-NSSession (Join-Path $recoveryWorkspace '.nightshift')
    Write-NSSession (Join-Path $recoveryWorkspace '.nightshift') $liveSession.SessionId $liveSession.Transcript `
        ([string]$PID) (Get-NSProcessStart $PID) 'codex' | Out-Null
    $liveWatch = Invoke-TestScript $watchman `
        @('-Project', $recoveryWorkspace, '-HostName', 'codex', '-IntervalMinutes', '1', '-Agent', $agentStub, '-MaxWakes', '1') `
        '' @{ NIGHTSHIFT_WATCH_SLEEP = '0'; NIGHTSHIFT_TEST_AGENT_RECEIPT = $liveReceipt }
    Assert-Equal 7 $liveWatch.ExitCode 'live-process fixture reaches its test cap'
    Assert-True (-not (Test-Path -LiteralPath $liveReceipt)) 'a live recorded process prevents recovery'

    Write-Host 'Checking detached watchman launcher'
    $launcherWorkspace = Join-Path $root 'launcher workspace'
    $null = Initialize-TestWorkspace $launcherWorkspace
    Set-TestPunch $launcherWorkspace $true
    [IO.File]::WriteAllText((Join-Path $launcherWorkspace '.nightshift/.shift-armed'), '')
    Write-NSSession (Join-Path $launcherWorkspace '.nightshift') 'launcher-session' '' `
        ([string]$PID) (Get-NSProcessStart $PID) 'claude' | Out-Null
    $launched = Invoke-TestScript $startWatchman @('-Project', $launcherWorkspace, '-HostName', 'claude') `
        '' @{ NIGHTSHIFT_WATCH_SLEEP = '1' }
    Assert-Equal 0 $launched.ExitCode "watchman launcher exits cleanly: $($launched.Stderr)"
    Assert-True ($launched.Stdout -match 'watchman started \(pid [1-9][0-9]*\)') `
        'watchman launcher returns detached process identity'
    $duplicateLaunch = Invoke-TestScript $startWatchman `
        @('-Project', $launcherWorkspace, '-HostName', 'claude') '' @{ NIGHTSHIFT_WATCH_SLEEP = '1' }
    Assert-True ($duplicateLaunch.ExitCode -ne 0) 'a second watchman launcher reports singleton refusal'
    [IO.File]::WriteAllText((Join-Path $launcherWorkspace '.nightshift/STOP'), '')
    $launcherReason = Join-Path $launcherWorkspace '.nightshift/.watch-reason'
    $launcherMarker = Join-Path $launcherWorkspace '.nightshift/.watchman'
    $launcherAttempts = 0
    while ((-not (Test-Path -LiteralPath $launcherReason -PathType Leaf) `
            -or (Test-Path -LiteralPath $launcherMarker)) -and $launcherAttempts -lt 100) {
        Start-Sleep -Milliseconds 50
        $launcherAttempts++
    }
    Assert-True (-not (Test-Path -LiteralPath $launcherMarker)) `
        'detached watchman honors STOP and cleans its marker'
    Assert-Equal 'owner-stop' ([IO.File]::ReadAllLines(
        $launcherReason
    )[0]) 'detached watchman records why it stood down'

    $brokenLauncherWorkspace = Join-Path $root 'broken launcher workspace'
    $null = Initialize-TestWorkspace $brokenLauncherWorkspace
    Set-TestPunch $brokenLauncherWorkspace $true
    [IO.File]::WriteAllText((Join-Path $brokenLauncherWorkspace '.nightshift/.shift-armed'), '')
    [IO.File]::WriteAllText((Join-Path $brokenLauncherWorkspace '.nightshift/rules.json'), '{')
    $brokenLaunch = Invoke-TestScript $startWatchman `
        @('-Project', $brokenLauncherWorkspace, '-HostName', 'claude') '' @{ NIGHTSHIFT_WATCH_SLEEP = '0' }
    Assert-True ($brokenLaunch.ExitCode -ne 0) 'watchman launcher reports a child that fails before publishing ownership'

    Write-Host "Windows-native verification passed ($script:Assertions assertions)."
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
