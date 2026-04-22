#!/usr/bin/env sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)"
out_dir="${1:-$root/dist}"
case "$out_dir" in
  /*) ;;
  *) out_dir="$root/$out_dir" ;;
esac
mkdir -p "$out_dir"
out_dir="$(CDPATH= cd -- "$out_dir" && pwd)"

commit="$(git -C "$root" rev-parse --short HEAD)"

safe_remove_dir() {
  target="$1"
  case "$target" in
    "$out_dir"/*) rm -rf "$target" ;;
    *) printf 'refusing to remove outside output dir: %s\n' "$target" >&2; exit 1 ;;
  esac
}

build_one() {
  os="$1"
  arch="$2"
  name="codexnomad_${os}_${arch}"
  stage="$out_dir/$name"
  archive="$out_dir/$name.tar.gz"

  safe_remove_dir "$stage"
  mkdir -p "$stage"

  (
    cd "$root/daemon"
    GOOS="$os" GOARCH="$arch" CGO_ENABLED=0 \
      go build -trimpath -ldflags '-s -w' -o "$stage/codexnomad" ./cmd/daemon
  )

  cat > "$stage/README-install.txt" <<EOF
Codex Nomad $os $arch
Commit: $commit

Install:
  curl -fsSL https://codexnomad.pro/install | sh

After install:
  codexnomad doctor
  codexnomad pair
  codexnomad pair claude
EOF

  printf 'commit=%s\n' "$commit" > "$stage/VERSION"
  chmod 0755 "$stage/codexnomad"
  tar -czf "$archive" -C "$stage" codexnomad README-install.txt VERSION
  printf 'Packaged %s\n' "$archive"
}

build_one linux amd64
build_one linux arm64
build_one darwin amd64
build_one darwin arm64
