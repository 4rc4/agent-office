# Shared helpers for the Agent Office Phase 0 spikes (Windows, PowerShell 5.1 or 7).
# Dot-source from a spike:   . (Join-Path $PSScriptRoot '_common.ps1')
#
# Rules every spike follows:
# - Raw output goes under spikes/out/ (git-ignored).
# - Every check prints one line starting with PASS, FAIL, SKIP or INFO.
# - Binaries are resolved with Get-Command and called by absolute path.
# - No credential file is ever read (~/.claude/.credentials.json, ~/.codex/auth.json, ...).
# - No signals: a stuck process is stopped with taskkill /T /F.

$ErrorActionPreference = 'Continue'

$SpikeState = @{
  OutDir   = (Join-Path $PSScriptRoot 'out')
  Failures = 0
}
if (-not (Test-Path -LiteralPath $SpikeState.OutDir)) {
  New-Item -ItemType Directory -Path $SpikeState.OutDir -Force | Out-Null
}

function Write-Pass { param([string]$Message) Write-Host "PASS  $Message" -ForegroundColor Green }
function Write-Fail {
  param([string]$Message)
  $SpikeState.Failures = $SpikeState.Failures + 1
  Write-Host "FAIL  $Message" -ForegroundColor Red
}
function Write-Skip { param([string]$Message) Write-Host "SKIP  $Message" -ForegroundColor Yellow }
function Write-Info { param([string]$Message) Write-Host "INFO  $Message" -ForegroundColor Gray }

# Ends the spike: exit 1 when any FAIL line was printed, else 0.
function Exit-Spike {
  if ($SpikeState.Failures -gt 0) {
    Write-Host ("== {0} FAIL line(s). Raw output: {1}" -f $SpikeState.Failures, $SpikeState.OutDir)
    exit 1
  }
  Write-Host ("== all checks passed. Raw output: {0}" -f $SpikeState.OutDir)
  exit 0
}

# Absolute path of an executable on PATH (claude.exe, codex.cmd, ...), or $null.
function Find-Exe {
  param([Parameter(Mandatory = $true)][string]$Name)
  $cmd = Get-Command -Name $Name -CommandType Application -ErrorAction SilentlyContinue |
    Select-Object -First 1
  if ($null -eq $cmd) { return $null }
  return $cmd.Source
}

# Reads a property without throwing when it is missing.
function Get-Prop {
  param($Object, [Parameter(Mandatory = $true)][string]$Name)
  if ($null -eq $Object) { return $null }
  $prop = $Object.PSObject.Properties[$Name]
  if ($null -eq $prop) { return $null }
  return $prop.Value
}

# Joins arguments into one Windows command line following CommandLineToArgvW rules.
function ConvertTo-ArgString {
  param([string[]]$Arguments)
  $parts = @()
  foreach ($a in $Arguments) {
    if ($null -eq $a) { continue }
    if ($a -eq '' -or $a -match '[\s"]') {
      $escaped = $a -replace '(\\*)"', '$1$1\"'
      $escaped = $escaped -replace '(\\+)$', '$1$1'
      $parts += ('"' + $escaped + '"')
    } else {
      $parts += $a
    }
  }
  return ($parts -join ' ')
}

# Starts a process without waiting. npm .cmd shims go through cmd.exe explicitly.
function Start-SpikeProcess {
  param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [string[]]$Arguments = @(),
    [string]$StdOut,
    [string]$StdErr,
    [string]$WorkingDirectory
  )
  $argString = ConvertTo-ArgString -Arguments $Arguments
  $file = $Exe
  if ($Exe -match '\.(cmd|bat)$') {
    $file = Join-Path $env:SystemRoot 'System32\cmd.exe'
    $inner = (ConvertTo-ArgString -Arguments @($Exe)) + ' ' + $argString
    $argString = '/d /c "' + $inner.TrimEnd() + '"'
  }
  $params = @{ FilePath = $file; PassThru = $true; NoNewWindow = $true }
  if ($argString -ne '') { $params.ArgumentList = $argString }
  if ($StdOut) { $params.RedirectStandardOutput = $StdOut }
  if ($StdErr) { $params.RedirectStandardError = $StdErr }
  if ($WorkingDirectory) { $params.WorkingDirectory = $WorkingDirectory }
  return Start-Process @params
}

# Kills a process and everything it started (no signals on Windows).
function Stop-ProcessTree {
  param([Parameter(Mandatory = $true)][int]$ProcessId)
  $taskkill = Join-Path $env:SystemRoot 'System32\taskkill.exe'
  & $taskkill /PID $ProcessId /T /F 2>&1 | Out-Null
}

# Runs a command to completion with a timeout. stdout/stderr land in out/.
# Returns an object: Name, ExitCode, TimedOut, StdOut, StdErr, Seconds.
function Invoke-Spike {
  param(
    [Parameter(Mandatory = $true)][string]$Exe,
    [string[]]$Arguments = @(),
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$StdOutFile,
    [string]$WorkingDirectory,
    [int]$TimeoutSec = 180
  )
  if (-not $StdOutFile) { $StdOutFile = "$Name.stdout.txt" }
  $stdout = Join-Path $SpikeState.OutDir $StdOutFile
  $stderr = Join-Path $SpikeState.OutDir "$Name.stderr.txt"
  Write-Info ('run: ' + (Split-Path -Leaf $Exe) + ' ' + (ConvertTo-ArgString -Arguments $Arguments))
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  $proc = Start-SpikeProcess -Exe $Exe -Arguments $Arguments -StdOut $stdout -StdErr $stderr `
    -WorkingDirectory $WorkingDirectory
  $finished = $proc.WaitForExit($TimeoutSec * 1000)
  if (-not $finished) {
    Stop-ProcessTree -ProcessId $proc.Id
    Write-Fail "$Name timed out after $TimeoutSec s (process tree killed)"
  }
  # A timed WaitForExit can return before redirected streams are flushed; wait again briefly.
  try { [void]$proc.WaitForExit(5000) } catch { }
  $watch.Stop()
  $exitCode = -1
  if ($finished) { try { $exitCode = $proc.ExitCode } catch { } }
  return [pscustomobject]@{
    Name     = $Name
    ExitCode = $exitCode
    TimedOut = (-not $finished)
    StdOut   = $stdout
    StdErr   = $stderr
    Seconds  = [math]::Round($watch.Elapsed.TotalSeconds, 1)
  }
}

# Whole text of a file, or '' when it does not exist.
function Get-TextContent {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return '' }
  return [System.IO.File]::ReadAllText($Path)
}

# First non-empty line of a file, or '(empty)'.
function Get-FirstLine {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return '(missing)' }
  foreach ($line in [System.IO.File]::ReadLines($Path)) {
    if ($line.Trim() -ne '') { return $line.Trim() }
  }
  return '(empty)'
}

# Parses a JSONL file; non-JSON lines are skipped. Returns an array of objects.
function Read-JsonLines {
  param([Parameter(Mandatory = $true)][string]$Path)
  $events = New-Object System.Collections.ArrayList
  if (-not (Test-Path -LiteralPath $Path)) { return @() }
  foreach ($line in [System.IO.File]::ReadLines($Path)) {
    $t = $line.Trim()
    if ($t -eq '' -or -not $t.StartsWith('{')) { continue }
    try { [void]$events.Add(($t | ConvertFrom-Json)) } catch { }
  }
  return @($events.ToArray())
}

# Distinct "type" (and "type/subtype") labels of Claude stream-json events.
function Get-ClaudeEventTypes {
  param($Events)
  $labels = @()
  foreach ($e in @($Events)) {
    $type = Get-Prop $e 'type'
    $sub = Get-Prop $e 'subtype'
    if ($null -eq $type) { continue }
    if ($type -eq 'stream_event') {
      $inner = Get-Prop (Get-Prop $e 'event') 'type'
      $labels += "stream_event/$inner"
    } elseif ($sub) {
      $labels += "$type/$sub"
    } else {
      $labels += "$type"
    }
  }
  return @($labels | Sort-Object -Unique)
}

# Distinct "type" (and "type/item.type") labels of Codex exec --json events.
function Get-CodexEventTypes {
  param($Events)
  $labels = @()
  foreach ($e in @($Events)) {
    $type = Get-Prop $e 'type'
    if ($null -eq $type) { continue }
    $itemType = Get-Prop (Get-Prop $e 'item') 'type'
    if ($itemType) { $labels += "$type/$itemType" } else { $labels += "$type" }
  }
  return @($labels | Sort-Object -Unique)
}

# Concatenated agent text of Codex events (item.completed / agent_message).
function Get-CodexAgentText {
  param($Events)
  $texts = @()
  foreach ($e in @($Events)) {
    if ((Get-Prop $e 'type') -ne 'item.completed') { continue }
    $item = Get-Prop $e 'item'
    if ((Get-Prop $item 'type') -eq 'agent_message') { $texts += [string](Get-Prop $item 'text') }
  }
  return ($texts -join "`n")
}

# Shortens text for a single INFO line.
function Get-Snippet {
  param([string]$Text, [int]$Max = 160)
  if ($null -eq $Text) { return '' }
  $one = ($Text -replace '\s+', ' ').Trim()
  if ($one.Length -le $Max) { return $one }
  return $one.Substring(0, $Max) + '...'
}
