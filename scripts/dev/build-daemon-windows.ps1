$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$binDir = Join-Path $repo 'bin'
New-Item -ItemType Directory -Force -Path $binDir | Out-Null

Push-Location (Join-Path $repo 'daemon')
try {
  go build -o (Join-Path $binDir 'codexnomad.exe') .\cmd\daemon
} finally {
  Pop-Location
}

Write-Host "Built $binDir\codexnomad.exe"
