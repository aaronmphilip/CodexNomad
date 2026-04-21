$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$binDir = Join-Path $repo 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Push-Location (Join-Path $repo 'services\relay')
try {
  go build -o (Join-Path $binDir 'codexnomad-relay.exe') .\cmd\relay
} finally {
  Pop-Location
}

Write-Host "Built $binDir\codexnomad-relay.exe"
