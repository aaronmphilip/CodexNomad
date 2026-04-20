#!/usr/bin/env sh
set -eu

APP="codexnomad"
DOMAIN="https://codexnomad.pro"
RELEASE_BASE="${CODEXNOMAD_RELEASE_BASE:-$DOMAIN/releases/latest}"

log() {
  printf '%s\n' "$*"
}

fail() {
  printf 'codexnomad install failed: %s\n' "$*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

detect_os() {
  os="$(uname -s | tr '[:upper:]' '[:lower:]')"
  case "$os" in
    linux*) printf 'linux' ;;
    darwin*) printf 'darwin' ;;
    mingw*|msys*|cygwin*) printf 'windows' ;;
    *) fail "unsupported OS: $os" ;;
  esac
}

detect_arch() {
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) printf 'amd64' ;;
    arm64|aarch64) printf 'arm64' ;;
    *) fail "unsupported CPU architecture: $arch" ;;
  esac
}

install_posix() {
  os="$1"
  arch="$2"
  need curl
  need tar

  install_dir="${CODEXNOMAD_INSTALL_DIR:-$HOME/.local/bin}"
  mkdir -p "$install_dir"

  tmp="${TMPDIR:-/tmp}/codexnomad-install.$$"
  mkdir -p "$tmp"
  trap 'rm -rf "$tmp"' EXIT INT TERM

  url="$RELEASE_BASE/codexnomad_${os}_${arch}.tar.gz"
  log "Downloading $url"
  curl -fsSL "$url" -o "$tmp/codexnomad.tar.gz"
  tar -xzf "$tmp/codexnomad.tar.gz" -C "$tmp"
  chmod 0755 "$tmp/codexnomad"
  mv "$tmp/codexnomad" "$install_dir/codexnomad"

  case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) log "Add this to PATH if needed: export PATH=\"$install_dir:\$PATH\"" ;;
  esac

  "$install_dir/codexnomad" install || {
    log "Autostart setup failed. You can still run: $install_dir/codexnomad start"
    exit 0
  }

  log "Codex Nomad installed."
  log "Start a session with: codexnomad codex"
}

install_windows_from_sh() {
  arch="$1"
  command -v powershell.exe >/dev/null 2>&1 || fail "Windows install requires powershell.exe"
  ps='
  $ErrorActionPreference = "Stop"
  $base = $env:CODEXNOMAD_RELEASE_BASE
  if (-not $base) { $base = "https://codexnomad.pro/releases/latest" }
  $dir = Join-Path $env:LOCALAPPDATA "CodexNomad\bin"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $zip = Join-Path $env:TEMP "codexnomad_windows.zip"
  $url = "$base/codexnomad_windows_'"$arch"'.zip"
  Invoke-WebRequest -Uri $url -OutFile $zip
  Expand-Archive -Force -Path $zip -DestinationPath $dir
  $exe = Join-Path $dir "codexnomad.exe"
  & $exe install
  Write-Host "Codex Nomad installed at $exe"
  '
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ps"
}

os="$(detect_os)"
arch="$(detect_arch)"

if [ "$os" = "windows" ]; then
  install_windows_from_sh "$arch"
else
  install_posix "$os" "$arch"
fi
