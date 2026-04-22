#!/usr/bin/env sh
set -eu

DOMAIN="${CODEXNOMAD_DOMAIN:-https://codexnomad.pro}"
RELEASE_BASE="${CODEXNOMAD_RELEASE_BASE:-$DOMAIN/releases/latest}"

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
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

cleanup() {
  if [ "${tmp:-}" ] && [ -d "$tmp" ]; then
    case "$tmp" in
      "${TMPDIR:-/tmp}"/codexnomad-install.*) rm -rf "$tmp" ;;
    esac
  fi
}

add_path_hint() {
  install_dir="$1"
  case ":$PATH:" in
    *":$install_dir:"*) ;;
    *) log "Add this to PATH if needed: export PATH=\"$install_dir:\$PATH\"" ;;
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
  trap cleanup EXIT INT TERM

  if [ "${CODEXNOMAD_ARCHIVE:-}" ]; then
    archive="$CODEXNOMAD_ARCHIVE"
    [ -f "$archive" ] || fail "CODEXNOMAD_ARCHIVE does not exist: $archive"
    log "Installing from local archive: $archive"
  else
    archive="$tmp/codexnomad.tar.gz"
    url="${RELEASE_BASE%/}/codexnomad_${os}_${arch}.tar.gz"
    log "Downloading $url"
    curl -fsSL "$url" -o "$archive"
  fi

  tar -xzf "$archive" -C "$tmp"
  [ -f "$tmp/codexnomad" ] || fail "archive does not contain codexnomad"
  chmod 0755 "$tmp/codexnomad"

  if [ -x "$install_dir/codexnomad" ]; then
    "$install_dir/codexnomad" stop >/dev/null 2>&1 || true
  fi
  mv "$tmp/codexnomad" "$install_dir/codexnomad"

  add_path_hint "$install_dir"

  if [ "${CODEXNOMAD_NO_SERVICE:-0}" != "1" ]; then
    "$install_dir/codexnomad" install || {
      warn "autostart setup failed; run manually with: $install_dir/codexnomad start"
    }
  fi

  if [ "${CODEXNOMAD_SKIP_DOCTOR:-0}" != "1" ]; then
    "$install_dir/codexnomad" doctor all || {
      warn "doctor found setup issues; install still completed"
    }
  fi

  log ""
  log "Codex Nomad installed."
  log "Start a session with: codexnomad pair"
  log "Or Claude Code with: codexnomad pair claude"
}

install_windows_from_sh() {
  command -v powershell.exe >/dev/null 2>&1 || fail "Windows install requires powershell.exe"
  ps1_path=""
  for candidate in "$(pwd)/install.ps1" "$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)/install.ps1"; do
    if [ -f "$candidate" ]; then
      ps1_path="$candidate"
      break
    fi
  done
  if [ "$ps1_path" ]; then
    if command -v cygpath >/dev/null 2>&1; then
      ps1_path="$(cygpath -w "$ps1_path")"
    fi
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$ps1_path"
    return
  fi
  script_url="${CODEXNOMAD_INSTALL_PS1_URL:-$DOMAIN/install.ps1}"
  powershell.exe -NoProfile -ExecutionPolicy Bypass -Command \
    "iwr -UseBasicParsing '$script_url' | iex"
}

os="$(detect_os)"
arch="$(detect_arch)"

if [ "$os" = "windows" ]; then
  install_windows_from_sh
else
  install_posix "$os" "$arch"
fi
