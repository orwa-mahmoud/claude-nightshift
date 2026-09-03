<#
.SYNOPSIS
  Records one baseline per originating source for native Windows.

.DESCRIPTION
  Mirrors runtime/evidence-baseline.sh. Writes a domain "baseline" record
  through the ledger: source class, exact command, tool versions, scope, the
  environment digest over sorted tool/version lines, and the digest of the raw
  output the ledger stores. Written before the first fix; nothing is
  copied out of the work target.
  Exit: 0 written - 1 usage / no .nightshift - 2 contract failure
#>
param()

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$pluginRoot = Resolve-Path (Join-Path $PSScriptRoot '../..')
Import-Module (Join-Path $pluginRoot 'lib/Nightshift.psm1') -Force -DisableNameChecking

[Console]::OutputEncoding = New-Object Text.UTF8Encoding($false)

$cli = ConvertFrom-NSEvidenceBaselineCli $args
if ($null -eq $cli) { exit (Write-NSEvidenceBaselineUsage) }

exit (Invoke-NSEvidenceBaselineCommand -Project $cli.Project -Id $cli.Id `
        -SourceClass $cli.SourceClass -Command $cli.Command -Versions $cli.Versions `
        -Scope $cli.Scope -Seen $cli.Seen -Raw $cli.Raw -Locator $cli.Locator `
        -HostLabel $cli.HostLabel)
