# rw-node

Управляющий скрипт для постоянной входной RU-ноды Remnawave: XHTTP через Unix sockets → отдельные зарубежные EXIT по Shadowsocks.

## Модель

`rus-<code>.metall3.ru:443` → `RUS2-<CODE>-XHTTP` → `EXIT-<CODE>` → bridge `:9999` на зарубежном сервере.

Каждый EXIT изолирован: отдельные hostname, socket, inbound, outbound и routing rule. На зарубежном сервере bridge должен принимать только IP RU-ноды в UFW.

## Установка на RU-ноду

1. На чистой RU-нoded запустите единый интерактивный установщик:

```bash
sudo ./install-all.sh
```

Он устанавливает Remnanode, Nginx self-steal с путём `/xhttp/` и затем сам менеджер.

2. Если нода уже установлена, ставьте только менеджер:

```bash
sudo ./install-rw-node.sh
sudoedit /etc/rw-node/rw-node.env
sudo rw-node menu
```

`CERTBOT_CERT_NAME` должен быть именем wildcard/SAN-сертификата для `*.metall3.ru`. В `docker-compose.yml` Nginx должен монтировать его в `/etc/nginx/ssl/<CERTBOT_CERT_NAME>/`. Для нового hostname отдельное изменение compose не требуется.

Перед первым добавлением exit сохраните актуальную конфигурацию профиля из панели в `/opt/remnawave/rw-node/profile.json`; файл должен содержать текущий JSON Config Profile для `rus2`.

## Применение в панели

Пункт 1 создаёт полный `profile.next.json`, но не меняет работающую панель. Проверьте его, затем:

- либо вставьте JSON в Config Profile вручную;
- либо задайте `PANEL_URL`, `PANEL_TOKEN` со scope `config-profiles:update` и `PROFILE_UUID` в `/etc/rw-node/rw-node.env`, затем выберите пункт 3.

Config Profile в Remnawave — полная конфигурация Xray ноды; после обновления панель отправляет её на Remnanode. genui{"citation":{"ref":"turn4search6"}}

## Добавление новой локации

Сначала на EXIT создайте отдельный `BRIDGE-XX-IN` Shadowsocks на `9999`, случайный пароль и firewall allow только от RU IP. Затем в меню выберите пункт 1. Скрипт:

- добавит Nginx server block с тем же `/xhttp/`, но своим Unix socket;
- добавит XHTTP inbound, Shadowsocks outbound и route в новый полный профиль;
- добавит новый hostname в `RUS2-Steal.serverNames`;
- не хранит пароль bridge в Git.

Сначала выполните `Проверить Nginx`, затем примените профиль. После этого добавьте Host и включите новый inbound в нужном Internal Squad в Remnawave, иначе пользователи не получат его в подписке.

## Ограничения безопасности

- Не коммитьте `/etc/rw-node/rw-node.env`, `profile.json`, `profile.next.json` и файлы из `state/`.
- API token должен быть отдельным и иметь минимум `config-profiles:read`/`config-profiles:update`.
- Перед применением API скрипт требует подтверждение; он не выполняет сетевые изменения по умолчанию.
