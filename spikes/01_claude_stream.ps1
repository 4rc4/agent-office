<#
.SYNOPSIS
  Spike 01: Claude Code headless (-p) stream-json, apiKeySource, --resume and /usage.
.DESCRIPTION
  Runs the logged-in `claude` binary three times:
    1. claude -p "Reply with exactly: pong" --output-format stream-json --verbose --max-turns 1
    2. claude -p --resume <session_id> "Reply with exactly: pong again" ...
    3. claude -p "/usage" ...   (does -p return a usage report?)
  Raw JSONL goes to spikes/out/01_claude_*.jsonl. Never reads ~/.claude credentials.
#>
param([int]$TimeoutSec = 180)
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host '== 01 claude -p stream-json =='

$claude = Find-Exe 'claude'
if (-not $claude) {
  Write-Fail 'claude not found on PATH (install Claude Code, run `claude` once and /login)'
  Exit-Spike
}
Write-Info "claude: $claude"

# The office never uses an API key; the spike must not either (value is never printed).
if ($env:ANTHROPIC_API_KEY) {
  Write-Info 'ANTHROPIC_API_KEY is set in this shell; removing it for the child processes'
  Remove-Item -Path Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
}

$ver = Invoke-Spike -Exe $claude -Arguments @('--version') -Name '01_claude_version' -TimeoutSec 60
Write-Info ('claude --version: ' + (Get-FirstLine $ver.StdOut))

# --- run 1: plain prompt --------------------------------------------------------------
$run1 = Invoke-Spike -Exe $claude -Name '01_claude_run1' -StdOutFile '01_claude_run1.jsonl' `
  -TimeoutSec $TimeoutSec -Arguments @(
    '-p', 'Reply with exactly: pong',
    '--output-format', 'stream-json', '--verbose', '--max-turns', '1')
$events1 = @(Read-JsonLines $run1.StdOut)
if ($events1.Count -eq 0) {
  Write-Fail ("run1 produced no JSON lines (exit {0}); stderr: {1}" -f $run1.ExitCode, (Get-Snippet (Get-TextContent $run1.StdErr)))
  Exit-Spike
}
Write-Pass ("run1: {0} JSON lines in {1}s, exit {2}" -f $events1.Count, $run1.Seconds, $run1.ExitCode)
$types1 = Get-ClaudeEventTypes $events1
Write-Info ('run1 event types: ' + ($types1 -join ', '))
Set-Content -LiteralPath (Join-Path $SpikeState.OutDir '01_claude_event_types.txt') -Value ($types1 -join "`n")

$sessionId = $null
$init = $events1 | Where-Object { (Get-Prop $_ 'type') -eq 'system' -and (Get-Prop $_ 'subtype') -eq 'init' } |
  Select-Object -First 1
if ($null -eq $init) {
  Write-Fail 'run1: no system/init event'
} else {
  $sessionId = Get-Prop $init 'session_id'
  $apiKeySource = Get-Prop $init 'apiKeySource'
  if ($sessionId) { Write-Pass "init has session_id $sessionId" } else { Write-Fail 'init has no session_id' }
  if ($apiKeySource -eq 'none') {
    Write-Pass 'init apiKeySource = none (subscription login, no API key)'
  } else {
    Write-Fail "init apiKeySource = '$apiKeySource' (expected none; the office must refuse to run)"
  }
  Write-Info ('init: model={0} version={1} permissionMode={2}' -f (Get-Prop $init 'model'), (Get-Prop $init 'claude_code_version'), (Get-Prop $init 'permissionMode'))
  Write-Info ('init keys: ' + (@($init.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '))
}

$result1 = $events1 | Where-Object { (Get-Prop $_ 'type') -eq 'result' } | Select-Object -Last 1
if ($null -eq $result1) {
  Write-Fail 'run1: no result event'
} else {
  $text1 = [string](Get-Prop $result1 'result')
  $isError1 = Get-Prop $result1 'is_error'
  if ($isError1 -eq $true) {
    Write-Fail ('run1 result is_error=true: ' + (Get-Snippet $text1))
  } elseif ($text1 -match '(?i)pong') {
    Write-Pass ('run1 result contains pong: ' + (Get-Snippet $text1 80))
  } else {
    Write-Fail ('run1 result does not contain pong: ' + (Get-Snippet $text1))
  }
  Write-Info ('result keys: ' + (@($result1.PSObject.Properties | ForEach-Object { $_.Name }) -join ', '))
}

# --- run 2: resume the same session ---------------------------------------------------
if ($sessionId) {
  $run2 = Invoke-Spike -Exe $claude -Name '01_claude_run2' -StdOutFile '01_claude_run2.jsonl' `
    -TimeoutSec $TimeoutSec -Arguments @(
      '-p', '--resume', $sessionId, 'Reply with exactly: pong again',
      '--output-format', 'stream-json', '--verbose', '--max-turns', '1')
  $events2 = @(Read-JsonLines $run2.StdOut)
  if ($events2.Count -eq 0) {
    Write-Fail ("run2 (--resume) produced no JSON lines (exit {0}); stderr: {1}" -f $run2.ExitCode, (Get-Snippet (Get-TextContent $run2.StdErr)))
  } else {
    $init2 = $events2 | Where-Object { (Get-Prop $_ 'type') -eq 'system' -and (Get-Prop $_ 'subtype') -eq 'init' } |
      Select-Object -First 1
    $sessionId2 = Get-Prop $init2 'session_id'
    if ($sessionId2 -eq $sessionId) {
      Write-Pass "resume kept session id $sessionId"
    } else {
      Write-Info "resume answered with session id '$sessionId2' (differs from $sessionId; fork?)"
    }
    $result2 = $events2 | Where-Object { (Get-Prop $_ 'type') -eq 'result' } | Select-Object -Last 1
    $text2 = [string](Get-Prop $result2 'result')
    if ((Get-Prop $result2 'is_error') -eq $true) {
      Write-Fail ('run2 result is_error=true: ' + (Get-Snippet $text2))
    } elseif ($text2.Trim() -ne '') {
      # Resume is proven by the session id above; the wording is up to the model.
      Write-Pass ('run2 (--resume) produced a result: ' + (Get-Snippet $text2 80))
      if ($text2 -notmatch '(?i)pong again') { Write-Info 'run2 did not say "pong again" (model wording, not a resume failure)' }
    } else {
      Write-Fail 'run2 (--resume) produced an empty result'
    }
  }
} else {
  Write-Skip 'run2 (--resume) skipped: no session id from run1'
}

# --- run 3: does /usage work in -p mode? ----------------------------------------------
$run3 = Invoke-Spike -Exe $claude -Name '01_claude_usage' -StdOutFile '01_claude_usage.jsonl' `
  -TimeoutSec $TimeoutSec -Arguments @(
    '-p', '/usage', '--output-format', 'stream-json', '--verbose', '--max-turns', '1')
$events3 = @(Read-JsonLines $run3.StdOut)
$usageText = @()
foreach ($e in $events3) {
  if ((Get-Prop $e 'type') -eq 'result') { $usageText += [string](Get-Prop $e 'result') }
  if ((Get-Prop $e 'type') -eq 'assistant') {
    foreach ($block in @(Get-Prop (Get-Prop $e 'message') 'content')) {
      if ((Get-Prop $block 'type') -eq 'text') { $usageText += [string](Get-Prop $block 'text') }
    }
  }
}
$usageJoined = ($usageText -join "`n")
if ($events3.Count -eq 0) {
  Write-Fail ("/usage run produced no JSON lines (exit {0}); stderr: {1}" -f $run3.ExitCode, (Get-Snippet (Get-TextContent $run3.StdErr)))
} elseif ($usageJoined -match '(?i)(usage|limit|reset|remaining|\d+\s*%)') {
  Write-Pass ('/usage in -p mode returned usage-looking text: ' + (Get-Snippet $usageJoined 200))
} else {
  Write-Fail ('/usage in -p mode returned nothing usage-like (gauges need another source): ' + (Get-Snippet $usageJoined 200))
}

Exit-Spike
