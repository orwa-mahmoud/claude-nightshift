# Portable PowerShell coverage for Windows Doctor leftover-contract and staged-work counts.
# Run on macOS or Windows: pwsh -File tests/windows/doctor-logic.ps1
Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repository = Resolve-Path (Join-Path $PSScriptRoot '../..')
$helper = Join-Path $repository 'plugins/nightshift/runtime/windows/doctor.ps1'
$rulesTemplate = Join-Path $repository 'plugins/nightshift/skills/nightshift/references/nightshift-rules-template.json'
$draftTemplate = Join-Path $repository 'plugins/nightshift/skills/nightshift/references/drafting-table-template.md'
$hostExecutable = (Get-Process -Id $PID).Path
$failures = New-Object 'System.Collections.Generic.List[string]'
$onWin32 = [Environment]::OSVersion.Platform -eq 'Win32NT'

function Expect-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) {
        $failures.Add($Message)
        Write-Host "FAIL: $Message"
    }
}

function Get-TreeStamp {
    param([Parameter(Mandatory = $true)][string]$Path)
    $lines = New-Object 'System.Collections.Generic.List[string]'
    Get-ChildItem -LiteralPath $Path -Recurse -File -Force | Sort-Object FullName | ForEach-Object {
        $rel = $_.FullName.Substring($Path.Length).TrimStart('\', '/')
        $hash = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash
        $null = $lines.Add("$hash $rel")
    }
    return ($lines -join "`n")
}

function Invoke-Doctor {
    param([Parameter(Mandatory = $true)][string]$Project)
    $argList = @(
        '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass',
        '-File', $helper, '-Project', $Project
    )
    $stdout = [Collections.Generic.List[string]]::new()
    $stderr = [Collections.Generic.List[string]]::new()
    foreach ($item in @(& $hostExecutable @argList 2>&1)) {
        if ($item -is [Management.Automation.ErrorRecord]) {
            $stderr.Add([string]$item)
        }
        else {
            $stdout.Add([string]$item)
        }
    }
    return [pscustomobject]@{
        ExitCode = [int]$LASTEXITCODE
        Stdout = ($stdout -join "`n")
        Stderr = ($stderr -join "`n")
    }
}

$root = Join-Path ([IO.Path]::GetTempPath()) ("ns-doctor-logic-" + [guid]::NewGuid().ToString('N'))
$notes = $null
$linkNotes = $null
$null = New-Item -ItemType Directory -Path (Join-Path $root '.nightshift') -Force
try {
    $ns = Join-Path $root '.nightshift'
    Copy-Item -LiteralPath $rulesTemplate -Destination (Join-Path $ns 'rules.json')
    & git -C $root init --quiet
    if ($LASTEXITCODE -ne 0) { throw "git init failed in $root" }
    & git -C $root -c user.name=t -c user.email=t@example.com commit --allow-empty -q -m init
    if ($LASTEXITCODE -ne 0) { throw "git commit failed in $root" }

    $punch = Join-Path $ns 'punch-list.md'
    [IO.File]::WriteAllText($punch,
        "## Shift contract`n- leftover campaign`n`n## Gates`n- none`n`n## Items`n`n")
    $before = Get-TreeStamp $root
    $leftover = Invoke-Doctor $root
    Expect-True ($leftover.ExitCode -eq 0) "leftover contract exits 0 (got $($leftover.ExitCode) $($leftover.Stderr))"
    Expect-True ($leftover.Stdout -match 'leftover Shift contract and Gates') `
        'empty punch list names leftover contract'
    Expect-True ($leftover.Stdout -notmatch 'work mode is unset; Setup would propose artifact') `
        'a git workspace does not warn that Setup would propose artifact'
    Expect-True ($leftover.Stdout -notmatch 'persist the proposed artifact mode with Setup; Doctor does not write work-mode') `
        'a git workspace does not offer to persist artifact mode'
    Expect-True ($leftover.Stdout -match 'empty punch list will inherit the current contract') `
        'unarmed empty list warns that the contract is inherited'
    Expect-True ($leftover.Stdout -match '\[confirm\].*review punch-list.md contract') `
        'leftover contract is a confirm action'
    Expect-True ((Get-TreeStamp $root) -eq $before) 'Doctor leaves leftover-contract state untouched'
    Expect-True ([IO.File]::ReadAllText($punch) -match 'leftover campaign') `
        'leftover campaign text stays in the punch list'

    Copy-Item -LiteralPath $draftTemplate -Destination (Join-Path $ns 'drafting-table.md')
    $example = Invoke-Doctor $root
    Expect-True ($example.ExitCode -eq 0) "drafting example exits 0 (got $($example.ExitCode) $($example.Stderr))"
    Expect-True ($example.Stdout -notmatch 'staged drafting-table items=') `
        'fenced item-shape example is not a staged draft'

    $draft = Join-Path $ns 'drafting-table.md'
    [IO.File]::WriteAllText($draft, @'
# Drafting Table

```text
- [ ] **1. example only.**
```

---

- [ ] **Real draft.**
  - Verify: true
  - Commit: `fix: x`
'@)
    $counted = Invoke-Doctor $root
    Expect-True ($counted.ExitCode -eq 0) "real draft exits 0 (got $($counted.ExitCode) $($counted.Stderr))"
    Expect-True ($counted.Stdout -match 'staged drafting-table items=1') `
        'drafts after the rule are counted'
    Expect-True ($counted.Stdout -match '\[confirm\].*drafting-table items') `
        'staged drafts are a confirm action'

    [IO.File]::WriteAllText((Join-Path $ns 'work-orders.md'),
        "# Work Orders`n`n## Work order — test`nHours: 2`n`n- [ ] **Coverage hunt.**`n")
    $orders = Invoke-Doctor $root
    Expect-True ($orders.ExitCode -eq 0) "work orders exit 0 (got $($orders.ExitCode) $($orders.Stderr))"
    Expect-True ($orders.Stdout -match 'pending Hunt work orders=1') `
        'open work-order boxes are counted'
    Expect-True ($orders.Stdout -match '\[confirm\].*promote a parked Hunt order') `
        'parked Hunt orders are a confirm action'

    $null = New-Item -ItemType File -Force (Join-Path $ns 'STOP')
    $stop = Invoke-Doctor $root
    Expect-True ($stop.ExitCode -eq 0) "unarmed STOP exits 0 (got $($stop.ExitCode) $($stop.Stderr))"
    Expect-True ($stop.Stdout -match 'STOP leftover') 'unarmed STOP is reported as leftover'
    Expect-True ($stop.Stdout -match '\[confirm\].*stale STOP') 'unarmed STOP is a confirm action'

    $rulesPath = Join-Path $ns 'rules.json'
    $rules = Get-Content -LiteralPath $rulesPath -Raw | ConvertFrom-Json
    $rules.revivalPrompt = ''
    $rules | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $rulesPath -Encoding utf8
    $emptyPrompt = Invoke-Doctor $root
    Expect-True ($emptyPrompt.ExitCode -eq 0) "empty revivalPrompt exits 0 (got $($emptyPrompt.ExitCode) $($emptyPrompt.Stderr))"
    Expect-True ($emptyPrompt.Stdout -match 'revivalPrompt is empty') `
        'empty revivalPrompt is a warning'
    Expect-True ($emptyPrompt.Stdout -match 'watchman will refuse to arm') `
        'empty revivalPrompt names the watchman refuse'

    $notes = $root + '-notes'
    $null = New-Item -ItemType Directory -Path (Join-Path $notes '.nightshift') -Force
    Copy-Item -LiteralPath $rulesTemplate -Destination (Join-Path $notes '.nightshift/rules.json')
    $null = New-Item -ItemType Directory -Path (Join-Path $notes 'research') -Force
    [IO.File]::WriteAllText((Join-Path $notes 'research/topic.md'), "notes`n")
    $unset = Invoke-Doctor $notes
    Expect-True ($unset.ExitCode -eq 0) "unset notes doctor exits 0 (got $($unset.ExitCode) $($unset.Stderr))"
    Expect-True ($unset.Stdout -match 'work mode is unset; Setup would propose artifact') `
        'an unset notes folder warns that Setup would propose artifact'
    Expect-True ($unset.Stdout -match 'persist the proposed artifact mode with Setup; Doctor does not write work-mode') `
        'an unset notes folder offers Setup as a confirm action'

    $linkNotes = $root + '-mode-link'
    $linkNs = Join-Path $linkNotes '.nightshift'
    $null = New-Item -ItemType Directory -Path $linkNs, (Join-Path $linkNotes 'research') -Force
    Copy-Item -LiteralPath $rulesTemplate -Destination (Join-Path $linkNs 'rules.json')
    [IO.File]::WriteAllText((Join-Path $linkNotes 'research/topic.md'), "notes`n")
    $plant = Join-Path $linkNs 'mode-plant'
    [IO.File]::WriteAllText($plant, "artifact`n")
    $modeLink = Join-Path $linkNs 'work-mode'
    try {
        $null = New-Item -ItemType SymbolicLink -Path $modeLink -Target $plant -ErrorAction Stop
    }
    catch {
        if ($onWin32) {
            Write-Host 'skip symlink work-mode (cannot create)'
        }
        else {
            throw
        }
    }
    if (Test-Path -LiteralPath $modeLink) {
        $malformed = Invoke-Doctor $linkNotes
        Expect-True ($malformed.ExitCode -eq 0) `
            "symlink work-mode doctor exits 0 (got $($malformed.ExitCode) $($malformed.Stderr))"
        Expect-True ($malformed.Stdout -match 'work mode is malformed; treating the site as unusable until Setup rewrites it') `
            'a symlink work-mode is reported as malformed'
        Expect-True ($malformed.Stdout -notmatch 'work mode is unset; Setup would propose artifact') `
            'a symlink work-mode is not reported as unset'
        Expect-True ($malformed.Stdout -notmatch 'work mode artifact') `
            'a symlink work-mode does not report artifact'
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
    if ($null -ne $notes) {
        Remove-Item -LiteralPath $notes -Recurse -Force -ErrorAction SilentlyContinue
    }
    if ($null -ne $linkNotes) {
        Remove-Item -LiteralPath $linkNotes -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures.Count -gt 0) {
    Write-Host "doctor-logic failed ($($failures.Count)):"
    foreach ($failure in $failures) { Write-Host " - $failure" }
    exit 1
}
Write-Host 'doctor-logic passed'
exit 0
