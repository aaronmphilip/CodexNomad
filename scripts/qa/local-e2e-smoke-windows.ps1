param(
  [int]$Port = 18080,
  [int]$TimeoutSeconds = 45,
  [string]$Marker = 'E2EE_SMOKE_SECRET_12345'
)

$ErrorActionPreference = 'Stop'

function New-QuotedCommand {
  param([string[]]$Lines)
  return ($Lines -join "`r`n")
}

function Wait-HttpReady {
  param(
    [string]$Url,
    [int]$Seconds
  )
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    try {
      Invoke-WebRequest -UseBasicParsing -Uri $Url -TimeoutSec 1 | Out-Null
      return
    } catch {
      Start-Sleep -Milliseconds 300
    }
  }
  throw "Timed out waiting for $Url"
}

function Wait-FileText {
  param(
    [string]$Path,
    [string]$Pattern,
    [int]$Seconds
  )
  $deadline = (Get-Date).AddSeconds($Seconds)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path $Path) {
      $text = Get-Content -Raw -ErrorAction SilentlyContinue -Path $Path
      if ($text -match $Pattern) {
        return $Matches[1]
      }
    }
    Start-Sleep -Milliseconds 300
  }
  throw "Timed out waiting for $Pattern in $Path"
}

function Stop-Tree {
  param([System.Diagnostics.Process]$Process)
  if ($null -eq $Process -or $Process.HasExited) {
    return
  }
  try {
    & taskkill.exe /PID $Process.Id /T /F | Out-Null
  } catch {
    Stop-Process -Id $Process.Id -Force -ErrorAction SilentlyContinue
  }
}

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$binDir = Join-Path $repo 'bin'
$relayExe = Join-Path $binDir 'codexnomad-relay.exe'
$daemonExe = Join-Path $binDir 'codexnomad.exe'
$logDir = Join-Path $repo '.tools\qa'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

$relayOut = Join-Path $logDir 'relay.out.log'
$relayErr = Join-Path $logDir 'relay.err.log'
$daemonOut = Join-Path $logDir 'daemon.out.log'
$daemonErr = Join-Path $logDir 'daemon.err.log'
$mobileOut = Join-Path $logDir 'mobile.out.log'
$mobileErr = Join-Path $logDir 'mobile.err.log'
Remove-Item -Force -ErrorAction SilentlyContinue $relayOut, $relayErr, $daemonOut, $daemonErr, $mobileOut, $mobileErr

Write-Host 'Building relay and daemon binaries...'
& (Join-Path $repo 'scripts\dev\build-relay-windows.ps1')
& (Join-Path $repo 'scripts\dev\build-daemon-windows.ps1')

if (-not (Test-Path $relayExe)) {
  throw "Relay binary missing: $relayExe"
}
if (-not (Test-Path $daemonExe)) {
  throw "Daemon binary missing: $daemonExe"
}

$relayURL = "ws://127.0.0.1`:$Port/v1/relay"
$backendURL = "http://127.0.0.1`:$Port"
$healthURL = "http://127.0.0.1`:$Port/healthz"
$expected = "SMOKE_ECHO:$Marker"
$sendCommand = "echo $expected"

$relayCommand = New-QuotedCommand @(
  "`$env:PORT = '$Port'",
  "`$env:PUBLIC_BASE_URL = '$backendURL'",
  "`$env:CODEXNOMAD_RELAY_DEBUG_FRAMES = '1'",
  "`$env:CODEXNOMAD_RELAY_LEAK_MARKERS = '$Marker'",
  "& '$relayExe'"
)

$daemonCommand = New-QuotedCommand @(
  "`$env:CODEXNOMAD_RELAY_URL = '$relayURL'",
  "`$env:CODEXNOMAD_REQUIRE_RELAY = '1'",
  "`$env:CODEXNOMAD_PRINT_PAIRING_URI = '1'",
  "`$env:CODEXNOMAD_SUPPRESS_TERMINAL_QR = '1'",
  "`$env:CODEXNOMAD_CODEX_BIN = 'cmd.exe'",
  "& '$daemonExe' codex /Q /K echo SMOKE_AGENT_READY"
)

$relay = $null
$daemon = $null
try {
  Write-Host "Starting relay at $relayURL..."
  $relay = Start-Process powershell.exe -WindowStyle Hidden -PassThru `
    -RedirectStandardOutput $relayOut `
    -RedirectStandardError $relayErr `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $relayCommand)

  Wait-HttpReady -Url $healthURL -Seconds 15

  Write-Host 'Starting demo daemon session...'
  $daemon = Start-Process powershell.exe -WindowStyle Hidden -PassThru `
    -WorkingDirectory $repo `
    -RedirectStandardOutput $daemonOut `
    -RedirectStandardError $daemonErr `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $daemonCommand)

  $pairingURI = Wait-FileText -Path $daemonOut -Pattern 'Pairing URI:\s*(codexnomad://pair\?data=\S+)' -Seconds 20
  Write-Host 'Pairing URI captured.'

  Push-Location (Join-Path $repo 'daemon')
  try {
    $previousErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
      $mobileOutput = & go run .\cmd\mobile-smoke `
        -pairing-uri $pairingURI `
        -send $sendCommand `
        -expect $expected `
        -timeout "$TimeoutSeconds`s" `
        -verbose 2>&1
    } finally {
      $ErrorActionPreference = $previousErrorActionPreference
    }
    $mobileOutput | ForEach-Object { "$_" } | Set-Content -Encoding UTF8 -Path $mobileOut
    if ($LASTEXITCODE -ne 0) {
      throw "mobile-smoke exited with code $LASTEXITCODE"
    }
  } finally {
    Pop-Location
  }

  $mobileText = Get-Content -Raw -Path $mobileOut
  if ($mobileText -notmatch [regex]::Escape($expected)) {
    throw "Mobile smoke output did not include expected terminal echo: $expected"
  }

  $relayText = ''
  if (Test-Path $relayOut) {
    $relayText += Get-Content -Raw -Path $relayOut
  }
  if (Test-Path $relayErr) {
    $relayText += Get-Content -Raw -Path $relayErr
  }
  if ($relayText -match 'POSSIBLE PLAINTEXT LEAK') {
    throw 'Relay logged POSSIBLE PLAINTEXT LEAK. E2EE smoke failed.'
  }

  Write-Host ''
  Write-Host 'Local E2E smoke passed.'
  Write-Host "Relay:   $relayURL"
  Write-Host "Marker:  $Marker"
  Write-Host "Logs:    $logDir"
} finally {
  Stop-Tree $daemon
  Stop-Tree $relay
}
