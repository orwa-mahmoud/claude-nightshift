# Local gate: can this host deliver hook JSON into hardhat.ps1?
# Run: pwsh -File tests/windows/probe-payload.ps1
# On macOS the lease mutex is unavailable, so a "lease could not be created"
# deny still counts as success. "payload is unreadable" or InputObjectNotBound
# does not.
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$hardhat = Join-Path $repository 'plugins/nightshift/hooks/windows/hardhat.ps1'
$setup = Join-Path $repository 'plugins/nightshift/runtime/windows/setup.ps1'
$module = Join-Path $repository 'plugins/nightshift/lib/Nightshift.psm1'
Import-Module $module -Force -DisableNameChecking

$root = Join-Path ([IO.Path]::GetTempPath()) ('ns-payload-probe-' + [guid]::NewGuid().ToString('N'))
$workspace = Join-Path $root 'workspace'
$repo = Join-Path $workspace 'code repo'
try {
    $null = New-Item -ItemType Directory -Path $repo -Force
    $null = Invoke-NSGitCommand $repo @('init', '--quiet')
    $null = Invoke-NSGitCommand $repo @('config', 'user.email', 'dev@example.com')
    $null = Invoke-NSGitCommand $repo @('config', 'user.name', 'Nightshift Test')
    [IO.File]::WriteAllText((Join-Path $repo 'README.md'), "probe`n")
    $null = Invoke-NSGitCommand $repo @('add', '--', 'README.md')
    $null = Invoke-NSGitCommand $repo @('commit', '--quiet', '-m', 'init')
    $null = & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $setup -Project $workspace -WorkTarget $repo
    [IO.File]::WriteAllText((Join-Path $workspace '.nightshift/punch-list.md'), "# Contract`n`n## Items`n- [ ] probe`n")
    [IO.File]::WriteAllText((Join-Path $workspace '.nightshift/.shift-armed'), '')

    $payload = @{
        session_id = '11111111-1111-1111-1111-111111111111'
        transcript_path = ''
        cwd = $workspace
        tool_name = 'Bash'
        tool_input = @{ command = "`$null = 'nightshift-binding-probe'" }
    } | ConvertTo-Json -Compress -Depth 10

    $env:CODEX_PROJECT_DIR = $workspace
    $previous = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @($payload | & (Get-Process -Id $PID).Path -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $hardhat -HostName codex 2>&1)
    }
    finally {
        $ErrorActionPreference = $previous
        Remove-Item Env:CODEX_PROJECT_DIR -ErrorAction SilentlyContinue
    }
    $text = ($output | ForEach-Object { [string]$_ }) -join "`n"
    Write-Host $text
    if ($text -match 'payload is unreadable' -or $text -match 'InputObjectNotBound') {
        throw "hook JSON never reached hardhat.ps1: $text"
    }
    Write-Host 'probe-payload: hook JSON was accepted'
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
