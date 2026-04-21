$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$localIP = Get-NetIPAddress -AddressFamily IPv4 |
  Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
  Sort-Object InterfaceMetric |
  Select-Object -First 1 -ExpandProperty IPAddress

if ([string]::IsNullOrWhiteSpace($localIP)) {
  throw 'Could not detect a LAN IPv4 address. Connect Wi-Fi/Ethernet and retry.'
}

$env:PORT = if ($env:PORT) { $env:PORT } else { '8080' }
$env:PUBLIC_BASE_URL = if ($env:PUBLIC_BASE_URL) { $env:PUBLIC_BASE_URL } else { "http://$localIP`:$env:PORT" }
$env:APP_SHARED_TOKEN = if ($env:APP_SHARED_TOKEN) { $env:APP_SHARED_TOKEN } else { 'dev-app-token' }
$env:RELAY_SHARED_TOKEN = if ($env:RELAY_SHARED_TOKEN) { $env:RELAY_SHARED_TOKEN } else { '' }
$env:RELAY_TICKET_SECRET = if ($env:RELAY_TICKET_SECRET) { $env:RELAY_TICKET_SECRET } else { '' }

Write-Host "Relay URL for QR/app: ws://$localIP`:$env:PORT/v1/relay"
Write-Host "Backend URL for Flutter dart-define: http://$localIP`:$env:PORT"

Push-Location (Join-Path $repo 'services\relay')
try {
  go run .\cmd\relay
} finally {
  Pop-Location
}
