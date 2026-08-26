# Portable PowerShell coverage for Windows Codex identity classification.
# Run on macOS or Windows: pwsh -File tests/windows/codex-identity-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $repository 'plugins/nightshift/lib/Nightshift.psm1') -Force -DisableNameChecking
$failures = New-Object 'System.Collections.Generic.List[string]'

function Expect-Equal {
    param($Expected, $Actual, [string]$Message)
    if ([string]$Expected -ne [string]$Actual) {
        $failures.Add("$Message (expected '$Expected', got '$Actual')")
        Write-Host "FAIL: $Message (expected '$Expected', got '$Actual')"
    }
}

Expect-Equal 'missing' (Get-NSCodexIdentityKind '') 'empty id'
Expect-Equal 'resumable' (Get-NSCodexIdentityKind 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee') 'UUID'
Expect-Equal 'resumable' (Get-NSCodexIdentityKind 'deadbeefdeadbeefdeadbeefdeadbeef') 'long hex'
Expect-Equal 'unsupported' (Get-NSCodexIdentityKind 'thread_abc') 'ChatGPT thread handle'
Expect-Equal 'malformed' (Get-NSCodexIdentityKind 'id with space') 'whitespace'
Expect-Equal 'malformed' (Get-NSCodexIdentityKind '/tmp/rollout.jsonl') 'rollout path'
Expect-Equal 'unsupported' (Get-NSCodexIdentityKind 'local') 'local token'
Expect-Equal 'unsupported' (Get-NSCodexIdentityKind 'unknown') 'unknown token'

if ($failures.Count -gt 0) {
    Write-Host "codex-identity-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'codex-identity-logic passed'
exit 0
