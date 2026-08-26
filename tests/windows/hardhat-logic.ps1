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
