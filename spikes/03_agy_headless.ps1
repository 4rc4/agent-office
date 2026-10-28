<#
.SYNOPSIS
  Spike 03: Antigravity CLI (agy) headless output, only if agy is installed.
.DESCRIPTION
  agy -p "Say pong" --output-format stream-json  -> spikes/out/03_agy.jsonl
  Google says wrapping agy inside third-party agents is unsupported. This spike only
  checks what the binary prints; it does not automate anything.
#>
param([int]$TimeoutSec = 180)
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host '== 03 agy (Antigravity CLI) headless =='
Write-Info 'Read https://antigravity.google/docs/faq and https://antigravity.google/terms yourself before any automation:'
Write-Info 'Google calls third-party wrapping unsupported and may suspend the Google account. v1 keeps the Gemini seat manual.'

$agy = Find-Exe 'agy'
if (-not $agy) {
  Write-Skip 'agy not found on PATH; nothing to test (Gemini seat stays manual)'
  Exit-Spike
}
Write-Info "agy: $agy"

$ver = Invoke-Spike -Exe $agy -Arguments @('--version') -Name '03_agy_version' -TimeoutSec 60
Write-Info ('agy --version: ' + (Get-FirstLine $ver.StdOut))

$help = Invoke-Spike -Exe $agy -Arguments @('--help') -Name '03_agy_help' -StdOutFile '03_agy_help.txt' -TimeoutSec 60
$helpText = (Get-TextContent $help.StdOut) + (Get-TextContent $help.StdErr)
$flags = @()
if ($helpText -match '(^|\s)-p[,\s]') { $flags += '-p' }
if ($helpText -match '--prompt') { $flags += '--prompt' }
if ($helpText -match '--output-format') { $flags += '--output-format' }
if ($helpText -match 'stream-json') { $flags += 'stream-json' }
if ($flags.Count -gt 0) { Write-Info ('agy --help mentions: ' + ($flags -join ', ')) }
else { Write-Info 'agy --help mentions none of -p / --prompt / --output-format / stream-json; read out/03_agy_help.txt' }

$run = Invoke-Spike -Exe $agy -Name '03_agy' -StdOutFile '03_agy.jsonl' -TimeoutSec $TimeoutSec `
  -Arguments @('-p', 'Say pong', '--output-format', 'stream-json')
$events = @(Read-JsonLines $run.StdOut)
$raw = Get-TextContent $run.StdOut
if ($events.Count -gt 0) {
  $types = @()
  foreach ($e in $events) {
    $t = Get-Prop $e 'type'
    if ($t) { $types += [string]$t }
  }
  $types = @($types | Sort-Object -Unique)
  Write-Pass ("agy -p produced {0} JSON lines in {1}s, exit {2}" -f $events.Count, $run.Seconds, $run.ExitCode)
  Write-Info ('agy event types: ' + ($types -join ', '))
  Set-Content -LiteralPath (Join-Path $SpikeState.OutDir '03_agy_event_types.txt') -Value ($types -join "`n")
  if ($raw -match '(?i)pong') { Write-Pass 'agy output contains pong' } else { Write-Info 'agy output does not contain pong' }
} elseif ($run.ExitCode -eq 0 -and $raw.Trim() -ne '') {
  Write-Fail ('agy -p exited 0 but output is not JSONL (flags differ?): ' + (Get-Snippet $raw 200))
} else {
  Write-Fail ("agy -p failed (exit {0}); stderr: {1}" -f $run.ExitCode, (Get-Snippet (Get-TextContent $run.StdErr) 200))
}

Exit-Spike
