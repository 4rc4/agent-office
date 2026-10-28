<#
.SYNOPSIS
  Spike 04: headless Chrome/Edge with --remote-debugging-port and a dedicated --user-data-dir.
.DESCRIPTION
  Chrome 136+ ignores --remote-debugging-port unless a non-default --user-data-dir is given.
  Launches the browser headless with a profile under %LOCALAPPDATA%\AgentOffice\chrome-spike,
  GETs http://127.0.0.1:<port>/json/version, prints PASS when webSocketDebuggerUrl comes back,
  then kills the browser process tree.
#>
param([int]$Port = 9222, [int]$WaitSec = 20)
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host '== 04 chrome remote debugging (CDP) =='

function Find-Browser {
  foreach ($name in @('chrome', 'msedge')) {
    $found = Find-Exe $name
    if ($found) { return $found }
  }
  $pf = $env:ProgramFiles
  $pf86 = ${env:ProgramFiles(x86)}
  $candidates = @(
    (Join-Path $pf 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $env:LOCALAPPDATA 'Google\Chrome\Application\chrome.exe'),
    (Join-Path $pf 'Microsoft\Edge\Application\msedge.exe')
  )
  if ($pf86) {
    $candidates += (Join-Path $pf86 'Google\Chrome\Application\chrome.exe')
    $candidates += (Join-Path $pf86 'Microsoft\Edge\Application\msedge.exe')
  }
  foreach ($key in @('chrome.exe', 'msedge.exe')) {
    $reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\$key" -ErrorAction SilentlyContinue
    $regPath = Get-Prop $reg '(default)'
    if ($regPath) { $candidates += [string]$regPath }
  }
  foreach ($c in $candidates) {
    if ($c -and (Test-Path -LiteralPath $c)) { return $c }
  }
  return $null
}

function Test-TcpPort {
  param([string]$HostName, [int]$PortNumber)
  $client = New-Object System.Net.Sockets.TcpClient
  try {
    $async = $client.BeginConnect($HostName, $PortNumber, $null, $null)
    if ($async.AsyncWaitHandle.WaitOne(500) -and $client.Connected) { return $true }
    return $false
  } catch {
    return $false
  } finally {
    $client.Close()
  }
}

$browser = Find-Browser
if (-not $browser) {
  Write-Fail 'no Chrome or Edge found (PATH, Program Files, App Paths registry)'
  Exit-Spike
}
$version = (Get-Item -LiteralPath $browser).VersionInfo.ProductVersion
$major = 0
try { $major = [int](([string]$version).Split('.')[0]) } catch { }
Write-Info "browser: $browser ($version)"
if ($major -ge 136) {
  Write-Info 'Chromium >= 136: --remote-debugging-port works only with a non-default --user-data-dir (passed below)'
}

$profileDir = Join-Path $env:LOCALAPPDATA 'AgentOffice\chrome-spike'
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
Write-Info "user-data-dir: $profileDir"

if (Test-TcpPort -HostName '127.0.0.1' -PortNumber $Port) {
  Write-Fail "port $Port is already in use (another debugging browser?); close it or run with -Port 9223"
  Exit-Spike
}

$stdout = Join-Path $SpikeState.OutDir '04_chrome.stdout.txt'
$stderr = Join-Path $SpikeState.OutDir '04_chrome.stderr.txt'
$proc = Start-SpikeProcess -Exe $browser -StdOut $stdout -StdErr $stderr -Arguments @(
  '--headless=new',
  "--remote-debugging-port=$Port",
  "--user-data-dir=$profileDir",
  '--no-first-run', '--no-default-browser-check', '--disable-extensions',
  'about:blank')
Write-Info "browser pid $($proc.Id) started; polling http://127.0.0.1:$Port/json/version for up to $WaitSec s"

$info = $null
$deadline = (Get-Date).AddSeconds($WaitSec)
try {
  while ((Get-Date) -lt $deadline) {
    if ($proc.HasExited) { break }
    try {
      $info = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/version" -TimeoutSec 2
      if ($info) { break }
    } catch {
      Start-Sleep -Milliseconds 500
    }
  }

  if ($null -eq $info) {
    if ($proc.HasExited) {
      Write-Fail ("browser exited early with code {0}; stderr: {1}" -f $proc.ExitCode, (Get-Snippet (Get-TextContent $stderr) 200))
    } else {
      Write-Fail "no answer on http://127.0.0.1:$Port/json/version within $WaitSec s"
    }
  } else {
    ($info | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $SpikeState.OutDir '04_chrome_version.json')
    $ws = Get-Prop $info 'webSocketDebuggerUrl'
    if ($ws) { Write-Pass "webSocketDebuggerUrl: $ws" } else { Write-Fail '/json/version answered without webSocketDebuggerUrl' }
    Write-Info ('Browser: {0}; Protocol-Version: {1}' -f (Get-Prop $info 'Browser'), (Get-Prop $info 'Protocol-Version'))
    try {
      $targets = Invoke-RestMethod -Uri "http://127.0.0.1:$Port/json/list" -TimeoutSec 2
      ($targets | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (Join-Path $SpikeState.OutDir '04_chrome_targets.json')
      Write-Info ("/json/list: {0} target(s)" -f @($targets).Count)
    } catch {
      Write-Info '/json/list not readable'
    }
  }
} finally {
  if (-not $proc.HasExited) { Stop-ProcessTree -ProcessId $proc.Id }
  try { [void]$proc.WaitForExit(5000) } catch { }
  if ($proc.HasExited) { Write-Info 'browser process tree stopped' } else { Write-Fail "browser pid $($proc.Id) is still running" }
}

Exit-Spike
