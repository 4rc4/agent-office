<#
.SYNOPSIS
  Runs the Phase 0 spikes 01-05 in order, continues on failure, writes spikes/out/summary.txt.
.DESCRIPTION
  Each spike runs in a fresh PowerShell process (same host executable as this one) so a
  failure in one cannot touch the others. Logs: spikes/out/<spike>.log.
  Usage: powershell -ExecutionPolicy Bypass -File agent_office\spikes\run_all.ps1
#>
. (Join-Path $PSScriptRoot '_common.ps1')

$scripts = @(
  '01_claude_stream.ps1',
  '02_codex_exec.ps1',
  '03_agy_headless.ps1',
  '04_chrome_cdp.ps1',
  '05_footprint.ps1'
)

$psExe = (Get-Process -Id $PID).Path
$summary = New-Object System.Collections.Generic.List[string]
$summary.Add(("Agent Office Phase 0 spikes - {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')))
$summary.Add(("host: {0} (PowerShell {1}) on {2}" -f $psExe, $PSVersionTable.PSVersion, [Environment]::OSVersion.VersionString))
$summary.Add('')

$totalFail = 0
foreach ($name in $scripts) {
  $path = Join-Path $PSScriptRoot $name
  $log = Join-Path $SpikeState.OutDir ($name -replace '\.ps1$', '.log')
  Write-Host ''
  Write-Host "##### $name #####" -ForegroundColor Cyan
  if (-not (Test-Path -LiteralPath $path)) {
    $summary.Add(("{0,-24} missing" -f $name))
    $totalFail++
    continue
  }
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  & $psExe -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $path 2>&1 |
    ForEach-Object { [string]$_ } | Tee-Object -FilePath $log
  $code = $LASTEXITCODE
  $watch.Stop()

  $lines = @()
  if (Test-Path -LiteralPath $log) { $lines = @(Get-Content -LiteralPath $log) }
  $pass = @($lines | Where-Object { $_ -match '^PASS ' }).Count
  $fail = @($lines | Where-Object { $_ -match '^FAIL ' }).Count
  $skip = @($lines | Where-Object { $_ -match '^SKIP ' }).Count
  if ($code -ne 0 -and $fail -eq 0) { $fail = 1 }   # crashed before printing a FAIL line
  $totalFail += $fail
  $summary.Add(("{0,-24} exit={1,-3} PASS={2} FAIL={3} SKIP={4} ({5}s)" -f $name, $code, $pass, $fail, $skip, [math]::Round($watch.Elapsed.TotalSeconds, 1)))
  foreach ($l in ($lines | Where-Object { $_ -match '^(PASS|FAIL|SKIP) ' })) { $summary.Add("    $l") }
  $summary.Add('')
}

$summary.Add(("TOTAL FAIL lines: {0}" -f $totalFail))
$summary.Add('Next: copy the results into agent_office/docs/verified.md (result + date columns).')

$summaryPath = Join-Path $SpikeState.OutDir 'summary.txt'
Set-Content -LiteralPath $summaryPath -Value ($summary -join "`n")
Write-Host ''
Write-Host '##### summary #####' -ForegroundColor Cyan
foreach ($l in $summary) { Write-Host $l }
Write-Host "written: $summaryPath"

if ($totalFail -gt 0) { exit 1 } else { exit 0 }
