#!/usr/bin/env bash
set -Eeuo pipefail
REPO_RAW="https://raw.githubusercontent.com/sharipov7ar/rw-node/main"
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo.' >&2; exit 1; }
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

# Supports direct launch through process substitution.
if [[ ! -f "$ROOT/rw-node.sh" ]]; then
  WORKDIR=$(mktemp -d)
  trap 'rm -rf "$WORKDIR"' EXIT
  mkdir -p "$WORKDIR/config"
  curl -fsSL "$REPO_RAW/rw-node.sh" -o "$WORKDIR/rw-node.sh"
  curl -fsSL "$REPO_RAW/config/rw-node.env.example" -o "$WORKDIR/config/rw-node.env.example"
  chmod 700 "$WORKDIR/rw-node.sh"
  ROOT="$WORKDIR"
fi

install -d -m 755 /usr/local/lib/rw-node /usr/local/sbin
install -m 755 "$ROOT/rw-node.sh" /usr/local/lib/rw-node/rw-node.sh
install -d -m 755 /usr/local/lib/rw-node/config
install -m 644 "$ROOT/config/rw-node.env.example" /usr/local/lib/rw-node/config/rw-node.env.example
ln -sfn /usr/local/lib/rw-node/rw-node.sh /usr/local/sbin/rw-node
/usr/local/sbin/rw-node bootstrap
echo 'Команда установлена: sudo rw-node menu'
