param(
  [ValidateSet('amd64', 'arm64')]
  [string]$Arch = 'amd64',
  [string]$OutputDir = 'dist'
)

$ErrorActionPreference = 'Stop'

function Resolve-RepoRoot {
  return (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
}

function Remove-SafeDirectory {
  param(
    [string]$Path,
    [string]$AllowedRoot
  )
  $resolvedRoot = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $AllowedRoot).Path)
  $resolvedTarget = [System.IO.Path]::GetFullPath($Path)
  if (-not $resolvedTarget.StartsWith($resolvedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove outside output root: $resolvedTarget"
  }
  if (Test-Path -LiteralPath $resolvedTarget) {
    Remove-Item -LiteralPath $resolvedTarget -Recurse -Force
  }
}

$repo = Resolve-RepoRoot
$outDir = if ([System.IO.Path]::IsPathRooted($OutputDir)) {
  $OutputDir
} else {
  Join-Path $repo $OutputDir
}
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outDir = (Resolve-Path -LiteralPath $outDir).Path

$stage = Join-Path $outDir "codexnomad_windows_$Arch"
Remove-SafeDirectory -Path $stage -AllowedRoot $outDir
New-Item -ItemType Directory -Force -Path $stage | Out-Null

$previousGoos = $env:GOOS
$previousGoarch = $env:GOARCH
$previousCgo = $env:CGO_ENABLED
try {
  $env:GOOS = 'windows'
  $env:GOARCH = $Arch
  $env:CGO_ENABLED = '0'
  Push-Location (Join-Path $repo 'daemon')
  try {
    go build -trimpath -ldflags '-s -w' -o (Join-Path $stage 'codexnomad.exe') .\cmd\daemon
  } finally {
    Pop-Location
  }
} finally {
  $env:GOOS = $previousGoos
  $env:GOARCH = $previousGoarch
  $env:CGO_ENABLED = $previousCgo
}

$commit = git -C $repo rev-parse --short HEAD
@"
Codex Nomad Windows $Arch
Commit: $commit

Install:
  powershell -NoProfile -ExecutionPolicy Bypass -File .\install.ps1

After install:
  codexnomad doctor
  codexnomad pair
  codexnomad pair claude
"@ | Set-Content -Encoding ASCII -Path (Join-Path $stage 'README-install.txt')

$versionPath = Join-Path $stage 'VERSION'
"commit=$commit" | Set-Content -Encoding ASCII -Path $versionPath

$zip = Join-Path $outDir "codexnomad_windows_$Arch.zip"
if (Test-Path -LiteralPath $zip) {
  Remove-Item -LiteralPath $zip -Force
}
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -Force

Write-Host "Packaged $zip"
