$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$exe = Join-Path $repo 'bin\codexnomad.exe'
if (-not (Test-Path $exe)) {
  & (Join-Path $PSScriptRoot 'build-daemon-windows.ps1')
}

$localIP = Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Sort-Object InterfaceMetric |
  Select-Object -First 1 -ExpandProperty IPAddress

if ([string]::IsNullOrWhiteSpace($localIP)) {
  throw 'Could not detect a LAN IPv4 address. Connect Wi-Fi/Ethernet and retry.'
}

$port = if ($env:PORT) { $env:PORT } else { '8080' }
$env:CODEXNOMAD_RELAY_URL = "ws://$localIP`:$port/v1/relay"
$env:CODEXNOMAD_RELAY_TOKEN = if ($env:CODEXNOMAD_RELAY_TOKEN) { $env:CODEXNOMAD_RELAY_TOKEN } else { '' }
$claudeCmd = Join-Path $env:APPDATA 'npm\claude.cmd'
if (Test-Path $claudeCmd) {
  $env:CODEXNOMAD_CLAUDE_BIN = $claudeCmd
}

Write-Host "Starting Claude session through $env:CODEXNOMAD_RELAY_URL"
& $exe claude
