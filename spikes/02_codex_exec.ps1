<#
.SYNOPSIS
  Spike 02: Codex CLI login status, `codex exec --json` event shapes, thread_id and resume.
.DESCRIPTION
  1. codex login status
  2. codex exec --json -C <temp git repo> -s read-only --skip-git-repo-check "Say pong"
  3. codex exec resume <thread_id> --json "Say pong again"   (falls back to flags-before-resume)
  Raw JSONL goes to spikes/out/02_codex_*.jsonl. Never reads ~/.codex/auth.json.
#>
param([int]$TimeoutSec = 240)
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host '== 02 codex exec --json =='

$codex = Find-Exe 'codex'
if (-not $codex) {
  Write-Fail 'codex not found on PATH (npm i -g @openai/codex, then `codex login`)'
  Exit-Spike
}
Write-Info "codex: $codex"

$ver = Invoke-Spike -Exe $codex -Arguments @('--version') -Name '02_codex_version' -TimeoutSec 60
Write-Info ('codex --version: ' + (Get-FirstLine $ver.StdOut))

# --- login status (prints a status line only, never a token) --------------------------
$login = Invoke-Spike -Exe $codex -Arguments @('login', 'status') -Name '02_codex_login_status' -TimeoutSec 60
$loginLine = Get-FirstLine $login.StdOut
if ($loginLine -eq '(empty)') { $loginLine = Get-FirstLine $login.StdErr }
$loginExitOk = ($null -eq $login.ExitCode) -or ($login.ExitCode -eq 0)
if ($loginExitOk -and $loginLine -match '(?i)logged in' -and $loginLine -notmatch '(?i)not logged') {
  Write-Pass "codex login status: $loginLine"
} else {
  Write-Fail ('codex login status exit {0}: {1} (run codex login first)' -f $login.ExitCode, $loginLine)
  Exit-Spike
}

# --- temporary git repo for the worker ------------------------------------------------
$repo = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-office-spike-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $repo -Force | Out-Null
Set-Content -LiteralPath (Join-Path $repo 'README.md') -Value "# spike`n`nTemporary repo for the Agent Office codex spike."
$git = Find-Exe 'git'
if ($git) {
  & $git -C $repo init -q 2>&1 | Out-Null
  & $git -C $repo -c user.name=spike -c user.email=spike@example.invalid add . 2>&1 | Out-Null
  & $git -C $repo -c user.name=spike -c user.email=spike@example.invalid commit -q -m 'init' 2>&1 | Out-Null
  Write-Info "temp git repo: $repo"
} else {
  Write-Info "git not found; using plain folder $repo (--skip-git-repo-check covers it)"
}

$allEvents = @()
$threadId = $null
try {
  # --- run 1: exec --json -----------------------------------------------------------
  $run1 = Invoke-Spike -Exe $codex -Name '02_codex_run1' -StdOutFile '02_codex_run1.jsonl' `
    -WorkingDirectory $repo -TimeoutSec $TimeoutSec -Arguments @(
      'exec', '--json', '-C', $repo, '-s', 'read-only', '--skip-git-repo-check', 'Say pong')
  $events1 = @(Read-JsonLines $run1.StdOut)
  $allEvents += $events1
  if ($events1.Count -eq 0) {
    Write-Fail ("run1 produced no JSON lines (exit {0}); stderr: {1}" -f $run1.ExitCode, (Get-Snippet (Get-TextContent $run1.StdErr)))
  } else {
    Write-Pass ("run1: {0} JSON lines in {1}s, exit {2}" -f $events1.Count, $run1.Seconds, $run1.ExitCode)
    Write-Info ('run1 event types: ' + ((Get-CodexEventTypes $events1) -join ', '))

    $started = $events1 | Where-Object { (Get-Prop $_ 'type') -eq 'thread.started' } | Select-Object -First 1
    $threadId = Get-Prop $started 'thread_id'
    if ($threadId) { Write-Pass "thread.started has thread_id $threadId" } else { Write-Fail 'no thread.started / thread_id event' }

    $text1 = Get-CodexAgentText $events1
    if ($text1 -match '(?i)pong') { Write-Pass ('agent_message contains pong: ' + (Get-Snippet $text1 80)) }
    else { Write-Fail ('no agent_message containing pong: ' + (Get-Snippet $text1)) }

    $completed = $events1 | Where-Object { (Get-Prop $_ 'type') -eq 'turn.completed' } | Select-Object -Last 1
    if ($completed) {
      $usage = Get-Prop $completed 'usage'
      Write-Pass ('turn.completed seen; usage: ' + (Get-Snippet ($usage | ConvertTo-Json -Compress -Depth 3) 120))
    } else {
      $failed = $events1 | Where-Object { (Get-Prop $_ 'type') -in @('turn.failed', 'error') } | Select-Object -Last 1
      Write-Fail ('no turn.completed event; last error: ' + (Get-Snippet ($failed | ConvertTo-Json -Compress -Depth 4)))
    }
  }

  # --- run 2: resume, trying both flag orders -----------------------------------------
  if ($threadId) {
    $orders = @(
      @{ Name = '02_codex_resume_a'; Label = 'codex exec resume <thread_id> --json "<prompt>"';
         Args = @('exec', 'resume', $threadId, '--json', 'Say pong again') },
      @{ Name = '02_codex_resume_b'; Label = 'codex exec --json resume <thread_id> "<prompt>" (flags before resume)';
         Args = @('exec', '--json', 'resume', $threadId, 'Say pong again') }
    )
    $resumed = $false
    foreach ($order in $orders) {
      $run2 = Invoke-Spike -Exe $codex -Name $order.Name -StdOutFile ($order.Name + '.jsonl') `
        -WorkingDirectory $repo -TimeoutSec $TimeoutSec -Arguments $order.Args
      $events2 = @(Read-JsonLines $run2.StdOut)
      $allEvents += $events2
      $text2 = Get-CodexAgentText $events2
      if ($events2.Count -gt 0 -and $text2 -match '(?i)pong again') {
        Write-Pass ('resume works with: ' + $order.Label)
        $started2 = $events2 | Where-Object { (Get-Prop $_ 'type') -eq 'thread.started' } | Select-Object -First 1
        $threadId2 = Get-Prop $started2 'thread_id'
        if ($threadId2 -eq $threadId) { Write-Pass "resume kept thread id $threadId" }
        else { Write-Info "resumed run reported thread id '$threadId2'" }
        $resumed = $true
        break
      }
      Write-Info ("order failed (exit {0}): {1}; stderr: {2}" -f $run2.ExitCode, $order.Label, (Get-Snippet (Get-TextContent $run2.StdErr) 200))
    }
    if (-not $resumed) { Write-Fail 'resume failed in both flag orders; see out/02_codex_resume_*.stderr.txt' }
  } else {
    Write-Skip 'resume skipped: no thread_id from run1'
  }
} finally {
  Remove-Item -LiteralPath $repo -Recurse -Force -ErrorAction SilentlyContinue
}

$distinct = Get-CodexEventTypes $allEvents
Write-Info ('distinct event types across all runs: ' + ($distinct -join ', '))
Set-Content -LiteralPath (Join-Path $SpikeState.OutDir '02_codex_event_types.txt') -Value ($distinct -join "`n")

Exit-Spike
