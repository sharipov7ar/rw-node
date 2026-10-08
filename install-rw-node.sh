#!/usr/bin/env bash
set -Eeuo pipefail
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo.' >&2; exit 1; }
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
install -d -m 755 /usr/local/lib/rw-node /usr/local/sbin
install -m 755 "$ROOT/rw-node.sh" /usr/local/lib/rw-node/rw-node.sh
install -d -m 755 /usr/local/lib/rw-node/config
install -m 644 "$ROOT/config/rw-node.env.example" /usr/local/lib/rw-node/config/rw-node.env.example
ln -sfn /usr/local/lib/rw-node/rw-node.sh /usr/local/sbin/rw-node
/usr/local/sbin/rw-node bootstrap
echo 'Команда установлена: sudo rw-node menu'
