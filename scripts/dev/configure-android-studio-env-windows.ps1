$ErrorActionPreference = 'Stop'

function Add-UniquePath {
  param(
    [string[]]$Existing,
    [string]$Candidate
  )
  if ([string]::IsNullOrWhiteSpace($Candidate) -or -not (Test-Path $Candidate)) {
    return $Existing
  }
  foreach ($entry in $Existing) {
    if ($entry.TrimEnd('\') -ieq $Candidate.TrimEnd('\')) {
      return $Existing
    }
  }
  return @($Existing + $Candidate)
}

$pathsToAdd = @()

foreach ($candidate in @('C:\Git\bin', 'C:\Git\usr\bin')) {
  if (Test-Path $candidate) {
    $pathsToAdd += $candidate
  }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($git) {
  $gitRoot = Split-Path (Split-Path $git.Source -Parent) -Parent
  foreach ($candidate in @((Join-Path $gitRoot 'bin'), (Join-Path $gitRoot 'usr\bin'))) {
    if (Test-Path $candidate) {
      $pathsToAdd += $candidate
    }
  }
}

$ndkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk\ndk'
if (Test-Path $ndkRoot) {
  $make = Get-ChildItem $ndkRoot -Recurse -Filter make.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*prebuilt*windows*x86_64*bin*' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if ($make) {
    $pathsToAdd += $make.Directory.FullName
  }
}

if ($pathsToAdd.Count -eq 0) {
  throw 'Could not find Git Bash or Android NDK make.exe. Install Git for Windows and open Android Studio once so it installs the NDK.'
}

$userPathRaw = [Environment]::GetEnvironmentVariable('Path', 'User')
$entries = @()
if (-not [string]::IsNullOrWhiteSpace($userPathRaw)) {
  $entries = @($userPathRaw -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

foreach ($path in ($pathsToAdd | Select-Object -Unique)) {
  $entries = Add-UniquePath -Existing $entries -Candidate $path
}

$newPath = ($entries | Select-Object -Unique) -join ';'
[Environment]::SetEnvironmentVariable('Path', $newPath, 'User')

Write-Host 'Updated your user PATH for Android Studio native Flutter builds.'
Write-Host 'Added/confirmed:'
foreach ($path in ($pathsToAdd | Select-Object -Unique)) {
  Write-Host "  $path"
}
Write-Host ''
Write-Host 'Close Android Studio completely and reopen it so it reads the new PATH.'
