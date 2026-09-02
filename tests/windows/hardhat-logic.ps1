# Portable PowerShell probe for Windows hardhat command guards.
# Run on macOS or Windows before pushing: pwsh -File tests/windows/hardhat-logic.ps1
# It does not replace windows-native CI (ACLs, mutexes, dispatchers), and Windows CI
# also runs it via tests/windows/run.ps1.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$hardhat = Join-Path $repository 'plugins/nightshift/hooks/windows/hardhat.ps1'
$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

$env:NIGHTSHIFT_HARDHAT_LIB = '1'
. $hardhat -HostName codex

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-hardhat-logic-" + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root -Force
try {
    Set-Location $root
    $null = & git init --quiet
    $null = & git config user.email dev@example.com
    $null = & git config user.name tester
    $null = & git config core.autocrlf false
    [IO.File]::WriteAllText((Join-Path $root 'tracked.txt'), "seed`n")
    $null = & git add -- tracked.txt
    $null = & git commit --quiet -m init

    $script:cwd = $root
    $script:ns = Join-Path $root '.nightshift'

    Expect-True (Test-NSControlTarget 'Remove-Item -Force .nightshift\.shift-armed') `
        'backslash control path is denied'
    Expect-True (Test-NSControlTarget 'cd .nightshift && unlink .shift-armed') `
        'cd .nightshift && unlink .shift-armed is a control target'
    Expect-True (-not (Test-NSLeaseTarget 'cd .nightshift && unlink .shift-armed')) `
        'cd .nightshift && unlink .shift-armed is not rm .nightshift'
    Expect-True (Test-NSControlTarget 'cd .nightshift && touch STOP') `
        'cd .nightshift && touch STOP is a control target'
    Expect-True (-not (Test-NSControlTarget 'touch STOP')) `
        'touch STOP at repo root is not a control target'
    Expect-True (Test-NSLeaseTarget 'rm -rf .nightshift') `
        'rm -rf .nightshift is a lease target'
    Expect-True (Test-NSLeaseTarget 'Remove-Item -Force .nightshift\.shift-*') `
        'indirect lease glob is a lease target'

    $null = New-Item -ItemType Directory -Path (Join-Path $root 'ai_docs') -Force
    [IO.File]::WriteAllText((Join-Path $root 'ai_docs/secret.txt'), "secret`n")
    $addAll = Get-NSCommandDenyReason -Command 'git add -A' -Scrubbed 'git add -A' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories 'ai_docs' `
        -ExpectedEmail '' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ($addAll -match 'protected directory') "git add -A: $addAll"

    $null = & git add -- ai_docs/secret.txt
    $null = & git commit --quiet -m protected
    Remove-Item -LiteralPath (Join-Path $root 'ai_docs/secret.txt') -Force
    $addDeleted = Get-NSCommandDenyReason -Command 'git add -A' -Scrubbed 'git add -A' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories 'ai_docs' `
        -ExpectedEmail '' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ($addDeleted -match 'protected directory') "git add -A deletion: $addDeleted"

    $gitDirAdd = Get-NSCommandDenyReason -Command 'git --git-dir=C:\elsewhere\.git add x' `
        -Scrubbed 'git --git-dir=C:\elsewhere\.git add x' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories 'ai_docs' `
        -ExpectedEmail '' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ($gitDirAdd -match 'protected-directory guard cannot verify') "git-dir add: $gitDirAdd"

    $workTreeCommit = Get-NSCommandDenyReason -Command 'git --work-tree=C:\elsewhere commit -am x' `
        -Scrubbed 'git --work-tree=C:\elsewhere commit -am MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories 'ai_docs' `
        -ExpectedEmail '' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ($workTreeCommit -match 'protected-directory guard cannot verify') "work-tree commit: $workTreeCommit"

    [IO.File]::WriteAllText((Join-Path $root 'secret.txt'), "placeholder`n")
    $null = & git add -- secret.txt
    $null = & git commit --quiet -m secret-seed
    [IO.File]::WriteAllText((Join-Path $root 'secret.txt'), "SECRET_KEY=abc`n")
    $null = & git add -- secret.txt
    $commitStaged = Get-NSCommandDenyReason -Command 'git commit -m x' -Scrubbed 'git commit -m MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail '' -NeverCommitPatterns 'secret_key' -ForbiddenCommands ''
    Expect-True ($commitStaged -match 'never-commit pattern') "staged never-commit: $commitStaged"

    $null = & git reset --quiet HEAD -- secret.txt
    $commitAm = Get-NSCommandDenyReason -Command 'git commit -am x' -Scrubbed 'git commit -am MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail '' -NeverCommitPatterns 'secret_key' -ForbiddenCommands ''
    Expect-True ($commitAm -notmatch 'cannot verify') "git commit -am is modeled: $commitAm"
    Expect-True ($commitAm -match 'never-commit pattern') "git commit -am never-commit: $commitAm"

    Remove-Item -LiteralPath (Join-Path $root 'secret.txt') -Force
    $commitClean = Get-NSCommandDenyReason -Command 'git commit -am x' -Scrubbed 'git commit -am MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail '' -NeverCommitPatterns 'secret_key' -ForbiddenCommands ''
    Expect-True ([string]::IsNullOrWhiteSpace($commitClean)) "clean git commit -am: $commitClean"

    $push = Get-NSCommandDenyReason -Command 'git push origin HEAD' -Scrubbed 'git push origin HEAD' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail '' -NeverCommitPatterns '' -ForbiddenCommands 'git .*push'
    Expect-True ($push -match 'forbidden list') "forbidden push: $push"
    Expect-True ($push -match 'parking-lot.md') "forbidden push names parking lot: $push"

    $badForbidden = Get-NSCommandDenyReason -Command 'git status' -Scrubbed 'git status' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail '' -NeverCommitPatterns '' -ForbiddenCommands '[[:punct:]]'
    Expect-True ($badForbidden -match 'NIGHTSHIFT_FORBIDDEN_COMMANDS is not a valid extended regular expression') `
        "invalid forbidden pattern: $badForbidden"
    Expect-True ($badForbidden -match 'Fix the pattern in your session settings') `
        "invalid forbidden pattern names session settings: $badForbidden"

    $wrongEmail = Get-NSCommandDenyReason -Command 'git commit -m x' -Scrubbed 'git commit -m MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail 'owner@nope.io' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ($wrongEmail -match "committer identity \('dev@example.com'\) is not the expected 'owner@nope.io'") `
        "wrong expectedEmail: $wrongEmail"
    Expect-True ($wrongEmail -match 'Fix git config user.email') "wrong expectedEmail names git config: $wrongEmail"

    $rightEmail = Get-NSCommandDenyReason -Command 'git commit -m x' -Scrubbed 'git commit -m MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail 'dev@example.com' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ([string]::IsNullOrWhiteSpace($rightEmail)) "expected identity is allowed: $rightEmail"

    $overrideEmail = Get-NSCommandDenyReason -Command 'git -c user.email=other@example.com commit -m x' `
        -Scrubbed 'git -c user.email=other@example.com commit -m MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail 'dev@example.com' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ($overrideEmail -match "repository's configured identity") `
        "command-line identity override: $overrideEmail"

    $gitDirCommit = Get-NSCommandDenyReason -Command 'git --git-dir=C:\elsewhere\.git commit -m x' `
        -Scrubbed 'git --git-dir=C:\elsewhere\.git commit -m MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail 'dev@example.com' -NeverCommitPatterns '' -ForbiddenCommands ''
    Expect-True ($gitDirCommit -match 'configured commit guards cannot verify') `
        "git-dir commit under expectedEmail: $gitDirCommit"

    $workTreeNever = Get-NSCommandDenyReason -Command 'git --work-tree=C:\elsewhere commit -am x' `
        -Scrubbed 'git --work-tree=C:\elsewhere commit -am MSG' `
        -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
        -ExpectedEmail '' -NeverCommitPatterns 'secret_key' -ForbiddenCommands ''
    Expect-True ($workTreeNever -match 'configured commit guards cannot verify') `
        "work-tree commit under never-commit: $workTreeNever"

    # --- the policy files are control files ---

    foreach ($file in @('shift-policy.json', 'shift-defaults.json', 'deadline')) {
        Expect-True (Test-NSControlTarget "printf forged > .nightshift/$file") `
            "$file path rewrite is a control target"
        Expect-True (Test-NSControlTarget "Remove-Item -Force .nightshift\$file") `
            "$file backslash delete is a control target"
        Expect-True (Test-NSControlTarget "cd .nightshift && rm -f $file") `
            "$file name delete in the nightshift directory is a control target"
    }
    Expect-True (-not (Test-NSControlTarget 'printf x > deadline')) `
        'a deadline file outside .nightshift is not a control target'

    # --- elevation categories ---

    $nightshift = Join-Path $root '.nightshift'
    $null = New-Item -ItemType Directory -Path $nightshift -Force
    $rulesPath = Join-Path $nightshift 'rules.json'
    $policyPath = Join-Path $nightshift 'shift-policy.json'
    $template = Join-Path $repository 'plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json'
    Copy-Item -LiteralPath $template -Destination $rulesPath -Force

    function Get-ElevationReason {
        param([Parameter(Mandatory = $true)][string]$Command)
        return Get-NSCommandDenyReason -Command $Command -Scrubbed (Remove-NSCommitMessage $Command) `
            -CurrentDirectory $root -Workspace $root -ProtectedDirectories '' `
            -ExpectedEmail '' -NeverCommitPatterns '' -ForbiddenCommands ''
    }

    $categoryCommands = @{
        'sudo' = 'sudo apt-get install -y jq'
        'containers' = 'docker compose up -d'
        'global-packages' = 'brew install shellcheck'
        'daemons' = 'systemctl start nginx'
        'external-services' = 'gh auth login'
    }
    foreach ($category in @('sudo', 'containers', 'global-packages', 'daemons', 'external-services')) {
        $reason = Get-ElevationReason $categoryCommands[$category]
        $expected = "BLOCKED: this command needs the '$category' elevation category, which is denied for this shift. The owner allows it in .nightshift/rules.json (elevation.$category.policy) or for one shift in shift-policy.json before arming. Park the item in .nightshift/parking-lot.md as `"needs allowance: $category`" and keep working."
        Expect-True ($reason -ceq $expected) "$category default deny: $reason"
    }

    foreach ($command in @("psql -c 'select 1'", 'curl http://localhost:3000', 'npm test')) {
        $reason = Get-ElevationReason $command
        Expect-True ([string]::IsNullOrEmpty($reason)) "using what already runs is never elevation: $command -> $reason"
    }
    $messageOnly = Get-ElevationReason "git commit -m 'sudo apt-get install jq and docker compose up'"
    Expect-True ([string]::IsNullOrEmpty($messageOnly)) "a commit message names no category: $messageOnly"

    $rules = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json
    $rules.elevation.containers.policy = 'allow'
    [IO.File]::WriteAllText($rulesPath, ($rules | ConvertTo-Json -Depth 10))
    Expect-True ([string]::IsNullOrEmpty((Get-ElevationReason 'docker compose up -d'))) `
        'a rules allowance lifts its category'
    Expect-True ((Get-ElevationReason 'sudo id') -match 'needs allowance: sudo') `
        'a rules allowance lifts nothing else'
    $rules.elevation.containers.policy = 'deny'
    [IO.File]::WriteAllText($rulesPath, ($rules | ConvertTo-Json -Depth 10))

    $oneShift = @'
{"schemaVersion":1,"shiftId":"9f2c40ab77e51d63","createdAt":"2026-09-02T02:30:00Z",
 "source":"composition","deadlineEpoch":null,"verificationLevel":"final",
 "toolingPolicy":"existing-tools",
 "allowances":[{"category":"containers","scope":"category","provenance":"one-shift"}]}
'@
    [IO.File]::WriteAllText($policyPath, $oneShift)
    Expect-True ([string]::IsNullOrEmpty((Get-ElevationReason 'docker compose up -d'))) `
        'a one-shift allowance lifts the category'

    $workTarget = Get-NSAbsolutePath (Resolve-NSWorkTarget $root)
    $digest = Get-NSPolicyPlanDigest -Commands @('docker compose up -d') -WorkTarget $workTarget -ShiftId '9f2c40ab77e51d63'
    $exactPlan = @'
{"schemaVersion":1,"shiftId":"9f2c40ab77e51d63","createdAt":"2026-09-02T02:30:00Z",
 "source":"composition","deadlineEpoch":null,"verificationLevel":"final",
 "toolingPolicy":"existing-tools",
 "allowances":[{"category":"containers","scope":"exact-plan","provenance":"one-shift",
   "plan":{"commands":["docker compose up -d"],"workTarget":"__TARGET__","digest":"__DIGEST__"}}]}
'@
    $escapedTarget = $workTarget.Replace('\', '\\')
    [IO.File]::WriteAllText($policyPath, $exactPlan.Replace('__TARGET__', $escapedTarget).Replace('__DIGEST__', $digest))
    Expect-True ([string]::IsNullOrEmpty((Get-ElevationReason 'docker compose up -d'))) `
        'an exact plan permits the command it lists'
    $mismatch = Get-ElevationReason 'docker compose down'
    Expect-True ($mismatch -ceq "BLOCKED: this command needs the 'containers' elevation category, which is denied for this shift. An exact-plan allowance exists but this command is not one of its approved commands.") `
        "a neighbouring command is an exact-plan mismatch: $mismatch"

    [IO.File]::WriteAllText($policyPath, $exactPlan.Replace('__TARGET__', $escapedTarget).Replace('__DIGEST__', ('0' * 64)))
    Expect-True ((Get-ElevationReason 'docker compose up -d') -match 'not one of its approved commands') `
        'a plan whose digest does not cover it is not the approved plan'
    Remove-Item -LiteralPath $policyPath -Force

    $rules.elevation.daemons.pattern = '(unclosed'
    [IO.File]::WriteAllText($rulesPath, ($rules | ConvertTo-Json -Depth 10))
    $broken = Get-ElevationReason 'git status'
    Expect-True ($broken -match 'elevation\.daemons\.pattern is not a valid extended regular expression') `
        "an invalid elevation pattern fails closed: $broken"
    Expect-True ($broken -match 'so the guard it configures cannot run') `
        "an invalid elevation pattern uses the shared wording: $broken"
}
finally {
    Set-Location $repository
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:NIGHTSHIFT_HARDHAT_LIB -ErrorAction SilentlyContinue
}

if ($failures.Count -gt 0) {
    Write-Host "hardhat-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'hardhat-logic passed'
exit 0
