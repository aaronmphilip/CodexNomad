$ErrorActionPreference = 'Stop'

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$flutter = Join-Path $env:USERPROFILE 'dev\flutter\bin\flutter.bat'
if (-not (Test-Path $flutter)) {
  $flutterCmd = Get-Command flutter -ErrorAction Stop
  $flutter = $flutterCmd.Source
}

$pathParts = @()
foreach ($candidate in @('C:\Git\bin', 'C:\Git\usr\bin')) {
  if (Test-Path $candidate) {
    $pathParts += $candidate
  }
}

$ndkRoot = Join-Path $env:LOCALAPPDATA 'Android\Sdk\ndk'
if (Test-Path $ndkRoot) {
  $make = Get-ChildItem $ndkRoot -Recurse -Filter make.exe -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like '*prebuilt*windows*x86_64*bin*' } |
    Sort-Object FullName -Descending |
    Select-Object -First 1
  if ($make) {
    $pathParts += $make.Directory.FullName
  }
}

$pathParts += (Join-Path $env:USERPROFILE 'dev\flutter\bin')
$pathParts += 'C:\Program Files\Go\bin'
$env:Path = ($pathParts -join ';') + ';' + $env:Path

$dartDefines = @()
foreach ($name in @('SUPABASE_URL', 'SUPABASE_ANON_KEY', 'CODEXNOMAD_BACKEND_URL', 'CODEXNOMAD_APP_TOKEN')) {
  $value = [Environment]::GetEnvironmentVariable($name)
  if (-not [string]::IsNullOrWhiteSpace($value)) {
    $dartDefines += "--dart-define=$name=$value"
  }
}

Push-Location (Join-Path $repo 'apps\android\flutter-app')
try {
  & $flutter pub get
  & $flutter analyze
  & $flutter build apk --debug --target-platform android-arm64 @dartDefines
} finally {
  Pop-Location
}
