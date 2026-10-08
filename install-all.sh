#!/usr/bin/env bash
# Full interactive deployment: Remnanode first, bridge manager second.
set -Eeuo pipefail

REPO_RAW="https://raw.githubusercontent.com/sharipov7ar/rw-node/main"
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo.' >&2; exit 1; }

# When launched as: bash <(curl -fsSL .../install-all.sh)
# /dev/fd has no sibling scripts, so fetch the complete repository once.
if [[ ! -f "$ROOT/install-remnanode.sh" || ! -f "$ROOT/install-rw-node.sh" ]]; then
  WORKDIR=$(mktemp -d)
  trap 'rm -rf "$WORKDIR"' EXIT
  for file in install-all.sh install-remnanode.sh install-rw-node.sh rw-node.sh; do
    curl -fsSL "$REPO_RAW/$file" -o "$WORKDIR/$file"
  done
  mkdir -p "$WORKDIR/config"
  curl -fsSL "$REPO_RAW/config/rw-node.env.example" -o "$WORKDIR/config/rw-node.env.example"
  chmod 700 "$WORKDIR"/*.sh
  exec bash "$WORKDIR/install-all.sh"
fi

"$ROOT/install-remnanode.sh"
"$ROOT/install-rw-node.sh"

echo
echo 'Нода и менеджер установлены.'
echo 'Заполните /etc/rw-node/rw-node.env, сохраните Config Profile в'
echo '/opt/remnawave/rw-node/profile.json и запустите: sudo rw-node menu'
