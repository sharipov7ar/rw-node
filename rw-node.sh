#!/usr/bin/env bash
# rw-node — management tool for the permanent RUS XHTTP bridge.
set -Eeuo pipefail

APP_DIR=/opt/remnawave/rw-node
CONF=/etc/rw-node/rw-node.env
EXITS_DIR="$APP_DIR/exits"
MARK_BEGIN='# RW-NODE-EXITS-BEGIN'
MARK_END='# RW-NODE-EXITS-END'

die(){ echo "Ошибка: $*" >&2; exit 1; }
note(){ echo "==> $*"; }
need_root(){ [[ $EUID -eq 0 ]] || die 'Запустите через sudo.'; }
load_config(){ [[ -r "$CONF" ]] || die "Нет $CONF. Создайте его по config/rw-node.env.example."; source "$CONF"; }
valid_code(){ [[ "$1" =~ ^[a-z0-9]{2,12}$ ]] || die 'Код локации: 2–12 строчных латинских букв/цифр.'; }
confirm(){ read -r -p "$1 [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]]; }

bootstrap(){
  need_root
  install -d -m 700 /etc/rw-node "$APP_DIR" "$EXITS_DIR"
  if [[ ! -f "$CONF" ]]; then
    install -m 600 "$(dirname "$0")/config/rw-node.env.example" "$CONF"
    note "Создан $CONF — заполните его и повторите команду."
  fi
}

ensure_markers(){
  [[ -f "$NGINX_CONFIG" ]] || die "Не найден Nginx-конфиг: $NGINX_CONFIG"
  if ! grep -Fqx "$MARK_BEGIN" "$NGINX_CONFIG"; then
    printf '\n%s\n%s\n' "$MARK_BEGIN" "$MARK_END" >> "$NGINX_CONFIG"
  fi
}

render_nginx_block(){
  local code=$1 host=$2 socket=$3 cert_name=${CERTBOT_CERT_NAME:-$BASE_DOMAIN}
  cat <<EOF
# exit: $code
server {
    listen unix:/dev/shm/nginx.sock ssl proxy_protocol;
    http2 on;
    server_name $host;

    ssl_certificate     "/etc/nginx/ssl/$cert_name/fullchain.pem";
    ssl_certificate_key "/etc/nginx/ssl/$cert_name/privkey.pem";
    ssl_trusted_certificate "/etc/nginx/ssl/$cert_name/fullchain.pem";
    root /var/www/html;
    index index.html;
    add_header X-Robots-Tag "noindex, nofollow, noarchive, nosnippet, noimageindex" always;

    location ^~ /xhttp/ {
        client_max_body_size 0;
        client_body_timeout 5m;
        grpc_read_timeout 315s;
        grpc_send_timeout 5m;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_pass unix:$socket;
    }

    location / { try_files \$uri \$uri/ =404; }
}
EOF
}

rewrite_nginx_exits(){
  local tmp; tmp=$(mktemp)
  awk -v begin="$MARK_BEGIN" -v end="$MARK_END" -v dir="$EXITS_DIR" '
    $0 == begin { print; while (("find " dir " -maxdepth 1 -type f -name \"*.nginx\" -print | sort") | getline x) { while ((getline l < x)>0) print l; close(x) } ; skip=1; next }
    $0 == end { skip=0; print; next }
    !skip { print }
  ' "$NGINX_CONFIG" > "$tmp"
  install -m 644 "$tmp" "$NGINX_CONFIG"; rm -f "$tmp"
}

patch_profile(){
  local code=$1 host=$2 exit_ip=$3 pass=$4 socket="/dev/shm/xrxh-$code.socket"
  [[ -f "$PROFILE_JSON" ]] || die "Не найден базовый профиль: $PROFILE_JSON"
  local out="$APP_DIR/profile.next.json" tmp; tmp=$(mktemp)
  jq --arg c "$code" --arg h "$host" --arg ip "$exit_ip" --arg p "$pass" --arg sock "$socket" --arg steal "$ENTRY_STEAL_TAG" '
    def inboundTag: "RUS2-" + ($c|ascii_upcase) + "-XHTTP";
    def legacyInboundTag: "RUS-" + ($c|ascii_upcase) + "-XHTTP";
    def outboundTag: "EXIT-" + ($c|ascii_upcase);
    .inbounds |= map(select(.tag != inboundTag)) + [{
      tag: inboundTag, listen: ($sock + ",0666"), protocol:"vless",
      settings:{clients:[],fallbacks:[],decryption:"none"},
      sniffing:{enabled:true,destOverride:["http","tls","quic"]},
      streamSettings:{network:"xhttp",xhttpSettings:{mode:"auto",path:"/xhttp/",extra:{noSSEHeader:true,xPaddingBytes:"100-1000",scMaxBufferedPosts:30,scMaxEachPostBytes:1000000,scStreamUpServerSecs:"20-80"}}}
    }] |
    .outbounds |= map(select(.tag != outboundTag)) + [{tag:outboundTag,protocol:"shadowsocks",settings:{servers:[{address:$ip,port:9999,method:"chacha20-ietf-poly1305",password:$p,level:0}]}}] |
    .routing.rules |= map(select((((.inboundTag // []) | index(inboundTag)) or ((.inboundTag // []) | index(legacyInboundTag))) | not)) + [{type:"field",inboundTag:[inboundTag],outboundTag:outboundTag}] |
    (.inbounds[] | select(.tag == $steal) | .streamSettings.realitySettings.serverNames) |= (if index($h) then . else . + [$h] end)
  ' "$PROFILE_JSON" > "$tmp"
  jq empty "$tmp" || die 'Не удалось сформировать профиль.'
  install -m 600 "$tmp" "$out"; rm -f "$tmp"
}

apply_panel(){
  [[ -n ${PANEL_URL:-} && -n ${PANEL_TOKEN:-} && -n ${PROFILE_UUID:-} ]] || die 'Заполните PANEL_URL, PANEL_TOKEN и PROFILE_UUID.'
  [[ -f "$APP_DIR/profile.next.json" ]] || die 'Сначала добавьте exit.'
  local payload; payload=$(jq -c '{config:.}' "$APP_DIR/profile.next.json")
  note "PATCH $PANEL_URL/api/config-profiles/$PROFILE_UUID"
  curl --fail-with-body -sS -X PATCH "$PANEL_URL/api/config-profiles/$PROFILE_UUID" \
    -H "Authorization: Bearer $PANEL_TOKEN" -H 'Content-Type: application/json' --data "$payload" >/dev/null
  install -m 600 "$APP_DIR/profile.next.json" "$PROFILE_JSON"
  note 'Профиль обновлён в панели и сохранён как новая база.'
}

add_exit(){
  need_root; load_config; ensure_markers
  local code ip pass host socket
  read -r -p 'Код локации (например nl): ' code; code=${code,,}; valid_code "$code"
  read -r -p 'IPv4 EXIT-сервера: ' ip
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || die 'Нужен IPv4.'
  read -r -s -p 'Пароль Shadowsocks bridge: ' pass; echo
  [[ ${#pass} -ge 16 ]] || die 'Пароль bridge должен быть не короче 16 символов.'
  host="rus-$code.$BASE_DOMAIN"; socket="/dev/shm/xrxh-$code.socket"
  render_nginx_block "$code" "$host" "$socket" > "$EXITS_DIR/$code.nginx"
  chmod 600 "$EXITS_DIR/$code.nginx"
  jq -n --arg code "$code" --arg host "$host" --arg socket "$socket" --arg ip "$ip" '{code:$code,host:$host,socket:$socket,exit_ip:$ip}' > "$EXITS_DIR/$code.json"
  chmod 600 "$EXITS_DIR/$code.json"
  rewrite_nginx_exits
  patch_profile "$code" "$host" "$ip" "$pass"
  note "Готово: $host → RUS2-${code^^}-XHTTP → EXIT-${code^^}."
  note "Создан $APP_DIR/profile.next.json. Проверить Nginx и применить в панели — отдельными пунктами меню."
}

renew_certs(){
  need_root; load_config
  certbot renew
  ( cd "$COMPOSE_DIR" && docker compose restart remnawave-nginx remnanode )
}

restart_services(){ need_root; load_config; ( cd "$COMPOSE_DIR" && docker compose restart remnawave-nginx remnanode ); }
check_nginx(){ need_root; load_config; ( cd "$COMPOSE_DIR" && docker compose exec -T remnawave-nginx nginx -t ); }
status(){ load_config; echo '--- containers'; (cd "$COMPOSE_DIR" && docker compose ps); echo '--- sockets'; ls -la /dev/shm/nginx.sock /dev/shm/xrxh*.socket 2>/dev/null || true; }

menu(){
  while :; do
    cat <<'EOF'

rw-node — RUS XHTTP bridge
1) Добавить/обновить EXIT и сформировать профиль
2) Проверить Nginx
3) Применить сформированный профиль в Remnawave API
4) Обновить сертификаты и перезапустить сервисы
5) Перезапустить Nginx и Remnanode
6) Статус
0) Выход
EOF
    read -r -p 'Выбор: ' x
    case "$x" in 1) add_exit;;2) check_nginx;;3) confirm 'Применить profile.next.json в панель?' && apply_panel;;4) renew_certs;;5) restart_services;;6) status;;0) break;;*) echo 'Неверный выбор.';;esac
  done
}

case ${1:-menu} in bootstrap) bootstrap;; add-exit) add_exit;; apply-panel) apply_panel;; renew-certs) renew_certs;; restart) restart_services;; status) status;; menu) menu;; *) echo "Usage: $0 {bootstrap|add-exit|apply-panel|renew-certs|restart|status|menu}"; exit 2;; esac
