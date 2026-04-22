param(
  [string]$InstallDir,
  [switch]$NoService,
  [switch]$NoPath,
  [switch]$SkipDoctor,
  [switch]$WithService,
  [switch]$RunDoctor
)

$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$releaseDir = Join-Path $repo '.tools\local-release'
$archive = Join-Path $releaseDir 'codexnomad_windows_amd64.zip'

Write-Host ''
Write-Host '==> Building local Codex Nomad Windows installer archive'
& (Join-Path $repo 'scripts\release\package-daemon-windows.ps1') -OutputDir $releaseDir

if (-not (Test-Path -LiteralPath $archive)) {
  throw "Expected archive was not created: $archive"
}

Write-Host ''
Write-Host '==> Installing local Codex Nomad daemon build'
$installParams = @{
  ArchivePath = $archive
}
if ($InstallDir) {
  $installParams.InstallDir = $InstallDir
}
if ($NoService -or -not $WithService) {
  $installParams.NoService = $true
}
if ($NoPath) {
  $installParams.NoPath = $true
}
if ($SkipDoctor -or -not $RunDoctor) {
  $installParams.SkipDoctor = $true
}

& (Join-Path $repo 'install.ps1') @installParams

Write-Host ''
Write-Host 'For local phone testing before the hosted relay is deployed, run:'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1 -Agent claude'
Write-Host 'or:'
Write-Host '  powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\dev\start-local-test-windows.ps1 -Agent codex'
