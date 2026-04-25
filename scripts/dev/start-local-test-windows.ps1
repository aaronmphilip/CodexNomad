param(
  [ValidateSet('codex', 'claude', 'demo')]
  [string]$Agent = 'codex',

  [switch]$RunApp,
  [switch]$UseAdbReverse,
  [switch]$SkipBuild,
  [switch]$DryRun,
  [switch]$NoAdbReverse,
  [switch]$AllowAppsMcp,

  [string]$Workspace = '.',

  [int]$Port = 8080
)

$ErrorActionPreference = 'Stop'

function New-QuotedCommand {
  param([string[]]$Lines)
  return ($Lines -join "`r`n")
}

function ConvertTo-PSStringLiteral {
  param([string]$Value)
  return "'" + $Value.Replace("'", "''") + "'"
}

function Resolve-AgentBinary {
  param([string]$AgentName)

  if ($AgentName -eq 'demo') {
    $powershell = Get-Command powershell.exe -ErrorAction Stop
    return $powershell.Source
  }

  $envName = if ($AgentName -eq 'claude') { 'CODEXNOMAD_CLAUDE_BIN' } else { 'CODEXNOMAD_CODEX_BIN' }
  $override = [Environment]::GetEnvironmentVariable($envName)
  if (-not [string]::IsNullOrWhiteSpace($override)) {
    return $override
  }

  $cmdName = if ($AgentName -eq 'claude') { 'claude' } else { 'codex' }
  if ($AgentName -eq 'claude') {
    $claudeCmd = Join-Path $env:APPDATA 'npm\claude.cmd'
    if (Test-Path $claudeCmd) {
      return $claudeCmd
    }
  } else {
    $codexCmd = Join-Path $env:APPDATA 'npm\codex.cmd'
    if (Test-Path $codexCmd) {
      return $codexCmd
    }
  }

  $cmd = Get-Command $cmdName -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd) {
    if ($AgentName -eq 'codex' -and $cmd.Source -like '*\WindowsApps\OpenAI.Codex_*\app\resources\codex.exe') {
      return $null
    }
    return $cmd.Source
  }

  $whereResult = & where.exe $cmdName 2>$null | Select-Object -First 1
  if (-not [string]::IsNullOrWhiteSpace($whereResult)) {
    if ($AgentName -eq 'codex' -and $whereResult -like '*\WindowsApps\OpenAI.Codex_*\app\resources\codex.exe') {
      return $null
    }
    return $whereResult
  }

  return $null
}

function Resolve-Adb {
  $adb = Get-Command adb -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($adb) {
    return $adb.Source
  }
  $sdkAdb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
  if (Test-Path $sdkAdb) {
    return $sdkAdb
  }
  return $null
}

function Get-ConnectedAdbDevice {
  param([string]$Adb)
  if ([string]::IsNullOrWhiteSpace($Adb)) {
    return $null
  }
  try {
    $devices = & $Adb devices 2>&1
  } catch {
    return $null
  }
  if ($LASTEXITCODE -ne 0) {
    return $null
  }
  foreach ($line in $devices) {
    if ($line -match '^(\S+)\s+device$') {
      return $Matches[1]
    }
  }
  return $null
}

function Test-TcpPortAvailable {
  param([int]$CandidatePort)
  $existing = Get-NetTCPConnection -State Listen -LocalPort $CandidatePort -ErrorAction SilentlyContinue
  if ($existing) {
    return $false
  }
  $listener = $null
  try {
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Any, $CandidatePort)
    $listener.Start()
    return $true
  } catch {
    return $false
  } finally {
    if ($listener) {
      $listener.Stop()
    }
  }
}

function Resolve-LocalPort {
  param([int]$PreferredPort)
  for ($candidate = $PreferredPort; $candidate -lt ($PreferredPort + 50); $candidate++) {
    if (Test-TcpPortAvailable $candidate) {
      return $candidate
    }
  }
  throw "No free local relay port found from $PreferredPort to $($PreferredPort + 49)."
}

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$workspacePath = (Resolve-Path -Path $Workspace -ErrorAction Stop).ProviderPath
$binDir = Join-Path $repo 'bin'
$relayExe = Join-Path $binDir 'codexnomad-relay.exe'
$daemonExe = Join-Path $binDir 'codexnomad.exe'
$requestedPort = $Port
$Port = Resolve-LocalPort $Port

$localIP = Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Sort-Object InterfaceMetric |
  Select-Object -First 1 -ExpandProperty IPAddress

if ([string]::IsNullOrWhiteSpace($localIP)) {
  throw 'Could not detect a LAN IPv4 address. Connect Wi-Fi/Ethernet and retry.'
}

$adb = Resolve-Adb
$adbDevice = Get-ConnectedAdbDevice $adb
$usingAdbReverse = $false
$relayHost = $localIP

if ($UseAdbReverse -and -not $NoAdbReverse) {
  if ([string]::IsNullOrWhiteSpace($adb)) {
    throw 'ADB is not installed or not on PATH. Install platform-tools or run without -UseAdbReverse.'
  }
  if ([string]::IsNullOrWhiteSpace($adbDevice)) {
    throw 'No connected ADB device found. Connect with USB/wireless debugging or run without -UseAdbReverse.'
  }
  if (-not $DryRun) {
    & $adb reverse "tcp:$Port" "tcp:$Port" | Out-Null
  }
  $usingAdbReverse = $true
  $relayHost = '127.0.0.1'
}

$relayURL = "ws://$relayHost`:$Port/v1/relay"
$backendURL = "http://$relayHost`:$Port"
$leakMarker = 'E2EE_TEST_SECRET_12345'
$mcpSafeMode = ($Agent -eq 'codex' -and -not $AllowAppsMcp)

$agentBin = Resolve-AgentBinary $Agent
if ([string]::IsNullOrWhiteSpace($agentBin)) {
  if ($Agent -eq 'codex') {
    throw "Could not find a runnable Codex CLI. The Windows Codex app sandbox binary is not enough. Install with: npm.cmd install -g @openai/codex ; then run: codex.cmd login. You can also run -Agent claude or -Agent demo."
  }
  throw "Could not find '$Agent' on PATH. Install the official CLI, set CODEXNOMAD_$($Agent.ToUpper())_BIN, or run with -Agent demo to test QR/E2EE without a real agent."
}

if ($DryRun) {
  Write-Host "Repo: $repo"
  Write-Host "Workspace: $workspacePath"
  if ($Port -ne $requestedPort) {
    Write-Host "Requested port $requestedPort is busy; using $Port."
  }
  Write-Host "Relay URL: $relayURL"
  Write-Host "Backend URL: $backendURL"
  Write-Host "Agent: $Agent"
  Write-Host "Agent binary: $agentBin"
  Write-Host "Run app: $RunApp"
  Write-Host "Reliable mode (disable apps MCP): $mcpSafeMode"
  Write-Host "ADB reverse: $usingAdbReverse"
  Write-Host "ADB device: $adbDevice"
  Write-Host "Dry run only. No windows started."
  exit 0
}

if (-not $SkipBuild) {
  & (Join-Path $PSScriptRoot 'build-daemon-windows.ps1')
  & (Join-Path $PSScriptRoot 'build-relay-windows.ps1')
}

if (-not (Test-Path $relayExe)) {
  throw "Relay binary missing: $relayExe"
}
if (-not (Test-Path $daemonExe)) {
  throw "Daemon binary missing: $daemonExe"
}
Write-Host "Using $Agent binary: $agentBin"
if ($Port -ne $requestedPort) {
  Write-Host "Requested port $requestedPort is busy; using $Port."
}

$relayLines = @(
  "`$Host.UI.RawUI.WindowTitle = 'Codex Nomad Relay'",
  "`$env:PORT = '$Port'",
  "`$env:PUBLIC_BASE_URL = '$backendURL'",
  "`$env:APP_SHARED_TOKEN = 'dev-app-token'",
  "`$env:CODEXNOMAD_RELAY_DEBUG_FRAMES = '1'",
  "`$env:CODEXNOMAD_RELAY_LEAK_MARKERS = '$leakMarker'",
  "Write-Host 'Codex Nomad relay running at $relayURL'",
  "Write-Host 'E2EE audit marker: $leakMarker'",
  "& '$relayExe'"
)
$relayCommand = New-QuotedCommand $relayLines

$daemonAgent = if ($Agent -eq 'claude') { 'claude' } else { 'codex' }
$daemonArgTokens = New-Object System.Collections.Generic.List[string]
if ($Agent -eq 'demo') {
  $daemonArgTokens.Add('-NoLogo')
  $daemonArgTokens.Add('-NoProfile')
  $daemonArgTokens.Add('-NoExit')
  $daemonArgTokens.Add('-Command')
  $daemonArgTokens.Add("Write-Host 'Codex Nomad demo agent ready'; Write-Host 'Type in the mobile app and watch it arrive here.'")
} elseif ($mcpSafeMode) {
  $daemonArgTokens.Add('--disable')
  $daemonArgTokens.Add('apps')
}
$daemonArgs = ($daemonArgTokens | ForEach-Object { ConvertTo-PSStringLiteral $_ }) -join ' '
$daemonLaunch = if ([string]::IsNullOrWhiteSpace($daemonArgs)) {
  "& '$daemonExe' $daemonAgent"
} else {
  "& '$daemonExe' $daemonAgent $daemonArgs"
}

$daemonLines = @(
  "`$Host.UI.RawUI.WindowTitle = 'Codex Nomad $Agent Session'",
  "`$env:CODEXNOMAD_RELAY_URL = '$relayURL'",
  "`$env:CODEXNOMAD_REQUIRE_RELAY = '1'",
  "`$env:CODEXNOMAD_OPEN_QR = '1'",
  "`$env:CODEXNOMAD_CODEX_BIN = $(ConvertTo-PSStringLiteral $agentBin)",
  "`$env:CODEXNOMAD_CLAUDE_BIN = $(ConvertTo-PSStringLiteral $agentBin)",
  "`$env:CODEXNOMAD_ALLOW_APPS_MCP = '$([int]$AllowAppsMcp.IsPresent)'",
  "Write-Host 'Starting Codex Nomad $Agent session through $relayURL'",
  "Write-Host 'Workspace: $workspacePath'",
  "Write-Host 'Reliable mode (disable apps MCP): $mcpSafeMode'",
  "Write-Host 'Scan the QR from the Android app.'",
  $daemonLaunch
)
$daemonCommand = New-QuotedCommand $daemonLines

Start-Process powershell -WorkingDirectory $workspacePath -ArgumentList @(
  '-NoExit',
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-Command',
  $relayCommand
)

$healthURL = "http://127.0.0.1`:$Port/healthz"
$ready = $false
for ($i = 0; $i -lt 30; $i++) {
  try {
    Invoke-WebRequest -UseBasicParsing -Uri $healthURL -TimeoutSec 1 | Out-Null
    $ready = $true
    break
  } catch {
    Start-Sleep -Milliseconds 500
  }
}
if (-not $ready) {
  Write-Warning "Relay did not answer $healthURL yet. Check the relay window for errors."
}

Start-Process powershell -WorkingDirectory $workspacePath -ArgumentList @(
  '-NoExit',
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-Command',
  $daemonCommand
)

if ($RunApp) {
  $flutter = Join-Path $env:USERPROFILE 'dev\flutter\bin\flutter.bat'
  if (-not (Test-Path $flutter)) {
    $flutter = (Get-Command flutter -ErrorAction Stop).Source
  }
  $appDir = Join-Path $repo 'apps\android\flutter-app'
  $appLines = @(
    "`$Host.UI.RawUI.WindowTitle = 'Codex Nomad Flutter App'",
    "Write-Host 'Running Android app. If no phone is connected, Flutter will stop and tell you.'",
    "& '$flutter' run --dart-define=CODEXNOMAD_BACKEND_URL=$backendURL --dart-define=CODEXNOMAD_APP_TOKEN=dev-app-token"
  )
  Start-Process powershell -WorkingDirectory $appDir -ArgumentList @(
    '-NoExit',
    '-NoProfile',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    (New-QuotedCommand $appLines)
  )
}

Write-Host ''
Write-Host 'Started local Codex Nomad test.'
Write-Host "1. Relay window: logs WebSocket frame metadata and E2EE leak warnings."
Write-Host "2. $Agent window: shows the QR code. Scan it from Android."
Write-Host '3. In the app chat, send:'
Write-Host "   $leakMarker"
Write-Host '4. If relay prints POSSIBLE PLAINTEXT LEAK, encryption is broken. If it only prints ciphertext=true frame metadata, relay cannot read the message.'
Write-Host ''
Write-Host "Relay URL:   $relayURL"
Write-Host "Backend URL: $backendURL"
Write-Host "Reliable mode (disable apps MCP): $mcpSafeMode"
if ($usingAdbReverse) {
  Write-Host "ADB reverse: enabled for device $adbDevice"
} else {
  Write-Host "ADB reverse: disabled; phone must reach $localIP over Wi-Fi/LAN"
}
