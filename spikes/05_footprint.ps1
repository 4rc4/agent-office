<#
.SYNOPSIS
  Spike 05: RAM and CPU of running claude / codex / agy / chrome / node / office processes.
.DESCRIPTION
  Two Get-Process samples a few seconds apart give working set, private bytes and CPU %.
  Writes spikes/out/05_footprint.txt and a Markdown table 05_footprint.md for the plan's
  footprint table. Process command lines are deliberately NOT read (they may carry tokens).
#>
param([int]$SampleSec = 3)
. (Join-Path $PSScriptRoot '_common.ps1')

Write-Host '== 05 footprint (RAM / CPU) =='

$pattern = '^(claude|codex.*|agy|chrome|msedge|node|dart|agent_office|office_core)$'
$cores = [Environment]::ProcessorCount

$first = @{}
foreach ($p in Get-Process | Where-Object { $_.ProcessName -match $pattern }) {
  $cpu = 0.0
  try { $cpu = [double]$p.TotalProcessorTime.TotalSeconds } catch { }
  $first[$p.Id] = $cpu
}
if ($first.Count -eq 0) {
  Write-Info 'no claude/codex/agy/chrome/node/dart processes are running; start a job and rerun for real numbers'
}
Start-Sleep -Seconds $SampleSec

$rows = @()
foreach ($p in Get-Process | Where-Object { $_.ProcessName -match $pattern }) {
  $cpuNow = 0.0
  try { $cpuNow = [double]$p.TotalProcessorTime.TotalSeconds } catch { }
  $cpuBefore = $cpuNow
  if ($first.ContainsKey($p.Id)) { $cpuBefore = $first[$p.Id] }
  $cpuPct = 0.0
  if ($cores -gt 0 -and $SampleSec -gt 0) { $cpuPct = (($cpuNow - $cpuBefore) / $SampleSec / $cores) * 100.0 }
  $started = ''
  try { $started = $p.StartTime.ToString('HH:mm:ss') } catch { }
  $rows += [pscustomobject]@{
    Name      = $p.ProcessName
    Pid       = $p.Id
    WorkingMB = [math]::Round($p.WorkingSet64 / 1MB, 1)
    PrivateMB = [math]::Round($p.PrivateMemorySize64 / 1MB, 1)
    CpuPct    = [math]::Round([math]::Max($cpuPct, 0.0), 1)
    Started   = $started
  }
}

$os = $null
try { $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop } catch { }
$memLine = 'system memory: unknown'
if ($os) {
  $totalGB = [math]::Round($os.TotalVisibleMemorySize / 1MB, 1)
  $freeGB = [math]::Round($os.FreePhysicalMemory / 1MB, 1)
  $memLine = "system memory: $totalGB GB total, $freeGB GB free, $cores logical cores"
}
Write-Info $memLine

$lines = @()
$lines += ("Agent Office footprint - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'))
$lines += $memLine
$lines += ''
if ($rows.Count -gt 0) {
  $lines += ($rows | Sort-Object Name, Pid | Format-Table -AutoSize | Out-String).TrimEnd()
  $lines += ''
  $lines += 'Totals per process name:'
  foreach ($g in ($rows | Group-Object Name | Sort-Object Name)) {
    $ws = [math]::Round(($g.Group | Measure-Object WorkingMB -Sum).Sum, 1)
    $pm = [math]::Round(($g.Group | Measure-Object PrivateMB -Sum).Sum, 1)
    $cp = [math]::Round(($g.Group | Measure-Object CpuPct -Sum).Sum, 1)
    $lines += ("  {0,-14} {1,3} proc  working {2,8} MB  private {3,8} MB  cpu {4,5} %" -f $g.Name, $g.Count, $ws, $pm, $cp)
  }
} else {
  $lines += '(no matching processes)'
}
$txt = Join-Path $SpikeState.OutDir '05_footprint.txt'
Set-Content -LiteralPath $txt -Value ($lines -join "`n")

$md = @()
$md += '| Process | Count | Working set MB | Private MB | CPU % |'
$md += '|---|---|---|---|---|'
foreach ($g in ($rows | Group-Object Name | Sort-Object Name)) {
  $ws = [math]::Round(($g.Group | Measure-Object WorkingMB -Sum).Sum, 1)
  $pm = [math]::Round(($g.Group | Measure-Object PrivateMB -Sum).Sum, 1)
  $cp = [math]::Round(($g.Group | Measure-Object CpuPct -Sum).Sum, 1)
  $md += ("| {0} | {1} | {2} | {3} | {4} |" -f $g.Name, $g.Count, $ws, $pm, $cp)
}
$mdPath = Join-Path $SpikeState.OutDir '05_footprint.md'
Set-Content -LiteralPath $mdPath -Value ($md -join "`n")

foreach ($l in $lines) { Write-Host $l }
Write-Pass ("footprint written: {0} process(es) -> {1} and {2}" -f $rows.Count, $txt, $mdPath)

Exit-Spike
