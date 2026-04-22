param(
  [string]$ReleaseBase = $env:CODEXNOMAD_RELEASE_BASE,
  [string]$ArchivePath = $env:CODEXNOMAD_ARCHIVE,
  [string]$InstallDir = $env:CODEXNOMAD_INSTALL_DIR,
  [switch]$NoService,
  [switch]$NoPath,
  [switch]$SkipDoctor,
  [switch]$Help
)

$ErrorActionPreference = 'Stop'

function Show-Help {
  Write-Host @'
Codex Nomad Windows installer

Usage:
  irm https://codexnomad.pro/install.ps1 | iex

Options:
  -ReleaseBase URL   Base URL containing codexnomad_windows_<arch>.zip.
                     Default: https://codexnomad.pro/releases/latest
  -ArchivePath PATH  Install from a local release zip instead of downloading.
  -InstallDir PATH   Install directory. Default: %LOCALAPPDATA%\CodexNomad\bin
  -NoService         Do not create/start the CodexNomad logon task.
  -NoPath            Do not add the install directory to the user PATH.
  -SkipDoctor        Do not run codexnomad doctor after install.

The script is idempotent. Running it again updates codexnomad.exe in place.

Environment equivalents:
  CODEXNOMAD_RELEASE_BASE, CODEXNOMAD_ARCHIVE, CODEXNOMAD_INSTALL_DIR,
  CODEXNOMAD_NO_SERVICE=1, CODEXNOMAD_NO_PATH=1, CODEXNOMAD_SKIP_DOCTOR=1
'@
}

function Write-Step {
  param([string]$Message)
  Write-Host ""
  Write-Host "==> $Message"
}

function Get-InstallArch {
  $arch = $env:PROCESSOR_ARCHITECTURE
  if ($arch -eq 'AMD64' -or $arch -eq 'x86_64') {
    return 'amd64'
  }
  if ($arch -eq 'ARM64' -or $arch -eq 'AARCH64') {
    return 'arm64'
  }
  throw "Unsupported Windows architecture: $arch"
}

function New-SafeTempDir {
  $base = [System.IO.Path]::GetTempPath()
  $path = Join-Path $base ("codexnomad-install-" + [guid]::NewGuid().ToString('n'))
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return (Resolve-Path $path).Path
}

function Remove-SafeTempDir {
  param([string]$Path)
  if (-not $Path) {
    return
  }
  $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue)
  if (-not $resolved) {
    return
  }
  $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
  $target = [System.IO.Path]::GetFullPath($resolved.Path)
  if (-not $target.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing to remove non-temp directory: $target"
  }
  Remove-Item -LiteralPath $target -Recurse -Force
}

function Resolve-InstallDir {
  param([string]$Path)
  if ($Path) {
    New-Item -ItemType Directory -Force -Path $Path | Out-Null
    return (Resolve-Path -LiteralPath $Path).Path
  }
  $base = $env:LOCALAPPDATA
  if (-not $base) {
    $base = Join-Path $HOME 'AppData\Local'
  }
  $dir = Join-Path $base 'CodexNomad\bin'
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  return (Resolve-Path -LiteralPath $dir).Path
}

function Get-Archive {
  param(
    [string]$Base,
    [string]$LocalArchive,
    [string]$TempDir,
    [string]$Arch
  )

  if ($LocalArchive) {
    $resolved = Resolve-Path -LiteralPath $LocalArchive
    return $resolved.Path
  }

  if (-not $Base) {
    $Base = 'https://codexnomad.pro/releases/latest'
  }
  $baseClean = $Base.TrimEnd('/')
  $url = "$baseClean/codexnomad_windows_$Arch.zip"
  $zip = Join-Path $TempDir "codexnomad_windows_$Arch.zip"

  Write-Step "Downloading $url"
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $zip
  return $zip
}

function Stop-ExistingDaemon {
  param([string]$Exe)
  if (Test-Path -LiteralPath $Exe) {
    try {
      & $Exe stop 2>$null | Out-Null
    } catch {
      Write-Host "Existing daemon was not running."
    }
  }
  try {
    schtasks.exe /End /TN CodexNomad 2>$null | Out-Null
  } catch {
  }
  $global:LASTEXITCODE = 0
}

function Install-Binary {
  param(
    [string]$Archive,
    [string]$InstallDir,
    [string]$TempDir
  )

  $extractDir = Join-Path $TempDir 'extract'
  New-Item -ItemType Directory -Force -Path $extractDir | Out-Null
  Expand-Archive -Force -Path $Archive -DestinationPath $extractDir

  $source = Get-ChildItem -Path $extractDir -Recurse -File -Filter 'codexnomad.exe' |
    Select-Object -First 1
  if (-not $source) {
    throw "Archive does not contain codexnomad.exe: $Archive"
  }

  $target = Join-Path $InstallDir 'codexnomad.exe'
  Stop-ExistingDaemon $target
  Copy-Item -LiteralPath $source.FullName -Destination $target -Force
  return $target
}

function Add-UserPath {
  param([string]$Dir)
  $current = [Environment]::GetEnvironmentVariable('Path', 'User')
  $parts = @()
  if ($current) {
    $parts = $current.Split(';', [System.StringSplitOptions]::RemoveEmptyEntries)
  }
  foreach ($part in $parts) {
    if ([string]::Equals($part.TrimEnd('\'), $Dir.TrimEnd('\'), [System.StringComparison]::OrdinalIgnoreCase)) {
      $env:Path = "$Dir;$env:Path"
      Write-Host "PATH already contains $Dir"
      return
    }
  }
  $next = if ($current) { "$current;$Dir" } else { $Dir }
  [Environment]::SetEnvironmentVariable('Path', $next, 'User')
  $env:Path = "$Dir;$env:Path"
  Write-Host "Added to user PATH: $Dir"
}

function Run-NonFatal {
  param(
    [string]$Title,
    [scriptblock]$Action
  )
  try {
    Write-Step $Title
    & $Action
  } catch {
    Write-Warning $_.Exception.Message
  } finally {
    $global:LASTEXITCODE = 0
  }
}

function Test-EnvFlag {
  param([string]$Name)
  $item = Get-Item -Path "Env:$Name" -ErrorAction SilentlyContinue
  if ($null -eq $item) {
    return $false
  }
  $value = [string]$item.Value
  return $value -match '^(1|true|yes|on)$'
}

if ($Help) {
  Show-Help
  exit 0
}

if (Test-EnvFlag 'CODEXNOMAD_NO_SERVICE') {
  $NoService = $true
}
if (Test-EnvFlag 'CODEXNOMAD_NO_PATH') {
  $NoPath = $true
}
if (Test-EnvFlag 'CODEXNOMAD_SKIP_DOCTOR') {
  $SkipDoctor = $true
}

$tempDir = $null
try {
  $arch = Get-InstallArch
  $installRoot = Resolve-InstallDir $InstallDir
  $tempDir = New-SafeTempDir

  Write-Step "Preparing Codex Nomad for Windows $arch"
  $archive = Get-Archive -Base $ReleaseBase -LocalArchive $ArchivePath -TempDir $tempDir -Arch $arch

  Write-Step "Installing codexnomad.exe"
  $exe = Install-Binary -Archive $archive -InstallDir $installRoot -TempDir $tempDir
  Write-Host "Installed: $exe"

  if (-not $NoPath) {
    Write-Step "Updating user PATH"
    Add-UserPath $installRoot
  }

  if (-not $NoService) {
    Run-NonFatal 'Installing logon task' {
      & $exe install
    }
  }

  if (-not $SkipDoctor) {
    Run-NonFatal 'Checking local readiness' {
      & $exe doctor all
    }
  }

  Write-Host ""
  Write-Host "Codex Nomad is installed."
  Write-Host "Open a new PowerShell window, then run:"
  Write-Host "  codexnomad pair"
  Write-Host "or:"
  Write-Host "  codexnomad pair claude"
  $global:LASTEXITCODE = 0
} finally {
  Remove-SafeTempDir $tempDir
}
