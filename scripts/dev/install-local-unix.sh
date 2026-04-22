#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
release_dir="$root/.tools/local-release"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$os" in
  linux*) os="linux" ;;
  darwin*) os="darwin" ;;
  *) printf 'unsupported OS: %s\n' "$os" >&2; exit 1 ;;
esac

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64) arch="amd64" ;;
  arm64|aarch64) arch="arm64" ;;
  *) printf 'unsupported CPU architecture: %s\n' "$arch" >&2; exit 1 ;;
esac

printf '\n==> Building local Codex Nomad %s/%s installer archive\n' "$os" "$arch"
sh "$root/scripts/release/package-daemon-unix.sh" "$release_dir"

archive="$release_dir/codexnomad_${os}_${arch}.tar.gz"
if [ ! -f "$archive" ]; then
  printf 'expected archive was not created: %s\n' "$archive" >&2
  exit 1
fi

printf '\n==> Installing local Codex Nomad daemon build\n'
CODEXNOMAD_ARCHIVE="$archive" sh "$root/install.sh"
