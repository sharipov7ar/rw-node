#!/usr/bin/env bash
# Full interactive deployment: Remnanode first, bridge manager second.
set -Eeuo pipefail
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ $EUID -eq 0 ]] || { echo 'Запустите через sudo.' >&2; exit 1; }

"$ROOT/install-remnanode.sh"
"$ROOT/install-rw-node.sh"

echo
echo 'Нода и менеджер установлены.'
echo 'Заполните /etc/rw-node/rw-node.env, сохраните Config Profile в'
echo '/opt/remnawave/rw-node/profile.json и запустите: sudo rw-node menu'
