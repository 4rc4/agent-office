<#
.SYNOPSIS
  Runs the Agent Office engine on Windows with the user's own Claude login.
.DESCRIPTION
  One command does the setup and the run:
    .\run_office.ps1 ask claude "Say hello"            # one desk alone
    .\run_office.ps1 run "Add a dark mode toggle"      # Claude plans, workers run
    .\run_office.ps1 reconcile                         # resume after a restart
  Defaults: --cwd is the folder you run this script from (the project the
  agents should work in), --brain is brain\brain.md next to this script, and
  --claude/--codex are resolved from PATH (npm installs them as .cmd files).
  Any other office_core option can be appended.
  First run: dart pub get, and sqlite3.dll is downloaded from sqlite.org into
  packages\office_core\.local (the plain Dart CLI needs it on Windows).
#>
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot
$invokedFrom = (Get-Location).Path
$pkg = Join-Path $root 'packages\office_core'
$local = Join-Path $pkg '.local'

function Find-Dart {
  $dart = Get-Command dart -ErrorAction SilentlyContinue
  if ($dart) { return $dart.Source }
  $flutter = Get-Command flutter -ErrorAction SilentlyContinue
  if ($flutter) {
    $candidate = Join-Path (Split-Path $flutter.Source) 'dart.bat'
    if (Test-Path $candidate) { return $candidate }
  }
  throw 'dart not found. Install Flutter (which bundles dart) or the Dart SDK.'
}

function Ensure-Sqlite {
  $dll = Join-Path $local 'sqlite3.dll'
  if (Test-Path $dll) { return $dll }
  New-Item -ItemType Directory -Path $local -Force | Out-Null
  Write-Host 'sqlite3.dll missing; reading the file list on sqlite.org ...'
  $page = (Invoke-WebRequest -UseBasicParsing 'https://www.sqlite.org/download.html').Content
  if ($page -notmatch 'PRODUCT,[^,]+,(\d{4}/sqlite-dll-win-x64-\d+\.zip)') {
    throw 'could not find the win-x64 DLL on sqlite.org/download.html; download sqlite-dll-win-x64-*.zip by hand and put sqlite3.dll into ' + $local
  }
  $zipUrl = 'https://www.sqlite.org/' + $Matches[1]
  $zip = Join-Path $local 'sqlite-dll.zip'
  Write-Host "downloading $zipUrl"
  Invoke-WebRequest -UseBasicParsing $zipUrl -OutFile $zip
  Expand-Archive -LiteralPath $zip -DestinationPath $local -Force
  Remove-Item $zip -Force
  if (-not (Test-Path $dll)) { throw 'sqlite3.dll not found after extracting ' + $zipUrl }
  return $dll
}

$dartExe = Find-Dart
Push-Location $pkg
try {
  if (-not (Test-Path (Join-Path $pkg '.dart_tool\package_config.json'))) {
    Write-Host 'dart pub get ...'
    & $dartExe pub get | Out-Host
  }
  $env:OFFICE_SQLITE_DLL = Ensure-Sqlite
  $cli = @()
  if ($Args) { $cli += $Args }
  if ($cli -notcontains '--cwd') { $cli += @('--cwd', $invokedFrom) }
  foreach ($tool in @('claude', 'codex')) {
    if ($cli -notcontains "--$tool") {
      $found = Get-Command $tool -ErrorAction SilentlyContinue
      if ($found) { $cli += @("--$tool", $found.Source) }
    }
  }
  if ($cli -notcontains '--brain') { $cli += @('--brain', (Join-Path $root 'brain\brain.md')) }
  Write-Host ("office_core " + ($cli -join ' '))
  & $dartExe run bin/office_core.dart @cli
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
