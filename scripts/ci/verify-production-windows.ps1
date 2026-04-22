param(
  [switch]$RequireCleanWorktree,
  [switch]$SkipAndroidBuild,
  [switch]$SkipReleaseBundle
)

$ErrorActionPreference = 'Stop'

function Step {
  param(
    [string]$Name,
    [scriptblock]$Action
  )
  Write-Host ""
  Write-Host "==> $Name"
  & $Action
}

function Invoke-In {
  param(
    [string]$Path,
    [scriptblock]$Action
  )
  Push-Location $Path
  try {
    & $Action
  } finally {
    Pop-Location
  }
}

function Assert-CleanWorktree {
  $status = git status --porcelain
  if ($status) {
    $status | Write-Host
    throw 'Working tree is not clean.'
  }
}

function Assert-GoFormat {
  param([string]$Path)
  Invoke-In $Path {
    $unformatted = gofmt -l .
    if ($unformatted) {
      $unformatted | Write-Host
      throw "Go files need gofmt in $Path."
    }
  }
}

function Ensure-AndroidSigningKey {
  param([string]$AppDir)

  $androidDir = Join-Path $AppDir 'android'
  $keyProperties = Join-Path $androidDir 'key.properties'
  if (Test-Path $keyProperties) {
    Write-Host "Using existing ignored Android signing config: $keyProperties"
    return
  }

  $keytool = Get-Command keytool -ErrorAction Stop
  $keystoreDir = Join-Path $androidDir 'keystores'
  $keystore = Join-Path $keystoreDir 'codexnomad-ci-upload.jks'
  New-Item -ItemType Directory -Force -Path $keystoreDir | Out-Null

  if (-not (Test-Path $keystore)) {
    & $keytool.Source -genkeypair `
      -v `
      -keystore $keystore `
      -storepass codexnomad-ci `
      -keypass codexnomad-ci `
      -alias codexnomad-ci `
      -keyalg RSA `
      -keysize 2048 `
      -validity 10000 `
      -dname 'CN=Codex Nomad CI,O=Codex Nomad,C=US'
  }

  @'
storePassword=codexnomad-ci
keyPassword=codexnomad-ci
keyAlias=codexnomad-ci
storeFile=../keystores/codexnomad-ci-upload.jks
'@ | Set-Content -Encoding ASCII -Path $keyProperties

  Write-Host "Created ignored CI-only Android signing config: $keyProperties"
}

$repo = Resolve-Path (Join-Path $PSScriptRoot '..\..')
$daemonDir = Join-Path $repo 'daemon'
$relayDir = Join-Path $repo 'services\relay'
$appDir = Join-Path $repo 'apps\android\flutter-app'

Step 'Repository status' {
  Invoke-In $repo {
    git status -sb
    if ($RequireCleanWorktree) {
      Assert-CleanWorktree
    }
  }
}

Step 'Go formatting' {
  Assert-GoFormat $daemonDir
  Assert-GoFormat $relayDir
}

Step 'Daemon tests and build' {
  Invoke-In $daemonDir {
    go test ./...
    go build ./...
  }
}

Step 'Relay tests and build' {
  Invoke-In $relayDir {
    go test ./...
    go build ./...
  }
}

Step 'Flutter dependencies' {
  Invoke-In $appDir {
    flutter pub get
  }
}

Step 'Flutter format check' {
  Invoke-In $appDir {
    dart format --output=none --set-exit-if-changed lib test
  }
}

Step 'Flutter analyze and tests' {
  Invoke-In $appDir {
    flutter analyze --no-pub
    flutter test --no-pub
  }
}

if (-not $SkipAndroidBuild) {
  Step 'Android debug APK' {
    Invoke-In $appDir {
      flutter build apk --debug --no-pub
    }
  }
}

if (-not $SkipAndroidBuild -and -not $SkipReleaseBundle) {
  Step 'Android release app bundle' {
    Ensure-AndroidSigningKey $appDir
    Invoke-In $appDir {
      flutter build appbundle --release --no-pub
    }
  }
}

Step 'Production gate complete' {
  Write-Host 'All requested production verification checks passed.'
}
