#!/usr/bin/env bash
# Deploy oVPC lab LEMP web app to existing Ubuntu 24.04 LEMP VM.
# Usage (as root): bash deploy-web.sh
# Does not publish secrets to GitHub or enable SSH.
set -Eeuo pipefail
umask 077

WEB_ROOT=/var/www/html
DB_IP=10.4.20.114
DB_ROUTE_NEXT_HOP=10.4.10.210
WEB_SOURCE=https://raw.githubusercontent.com/conglc04/labweb/main/index.php
NGINX_SITE=/etc/nginx/sites-available/default
NGINX_BACKUP="${NGINX_SITE}.before-ovpc-$(date +%Y%m%d%H%M%S)"

if [[ $EUID -ne 0 ]]; then
  echo 'ERROR: Run as root: sudo bash deploy-web.sh' >&2
  exit 1
fi

for cmd in php nginx curl ip systemctl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $cmd" >&2
    exit 1
  fi
done

if ! [[ -S /run/php/php8.3-fpm.sock ]]; then
  echo 'ERROR: PHP 8.3-FPM socket not present (/run/php/php8.3-fpm.sock).' >&2
  exit 1
fi
if ! php -m | grep -qx 'pdo_mysql'; then
  echo 'ERROR: PDO MySQL module is missing.' >&2
  exit 1
fi

# The two existing Web VMs have already used a temporary host route in this lab.
# This guest route DOES NOT persist across reboot; migrate to managed routing later.
interface=$(ip -o -4 route get "$DB_IP" | sed -n 's/.* dev \([^ ]*\).*/\1/p' | head -n 1)
if [[ -z "$interface" ]]; then
  echo 'ERROR: Unable to detect interface for DB route.' >&2
  exit 1
fi
ip route replace "${DB_IP}/32" via "$DB_ROUTE_NEXT_HOP" dev "$interface"
echo "INFO: Temporary DB route: $DB_IP via $DB_ROUTE_NEXT_HOP on $interface"

mkdir -p "$WEB_ROOT" /etc/ovpc
app_tmp=$(mktemp)
trap 'rm -f "$app_tmp"; unset DB_PASSWORD || true' EXIT
curl --fail --location --show-error --silent --connect-timeout 8 --max-time 30 \
  "$WEB_SOURCE" --output "$app_tmp"
php -l "$app_tmp" >/dev/null
install -o root -g root -m 0644 "$app_tmp" "$WEB_ROOT/index.php"

printf 'Enter MySQL password for webapp (hidden): ' >&2
IFS= read -r -s DB_PASSWORD
printf '\n' >&2
if [[ -z "$DB_PASSWORD" ]]; then
  echo 'ERROR: Password cannot be empty.' >&2
  exit 1
fi

# var_export safely escapes arbitrary password characters into a PHP literal.
config_tmp=$(mktemp)
trap 'rm -f "$app_tmp" "$config_tmp"; unset DB_PASSWORD || true' EXIT
printf '%s' "$DB_PASSWORD" | php -r '
  $password = stream_get_contents(STDIN);
  $conf = ["host" => "10.4.20.114", "dbname" => "labdb", "user" => "webapp", "pass" => $password];
  echo "<?php\nreturn ", var_export($conf, true), ";\n";
' > "$config_tmp"
install -o root -g www-data -m 0640 "$config_tmp" /etc/ovpc/db.php
unset DB_PASSWORD
php -l /etc/ovpc/db.php >/dev/null

if [[ -f "$NGINX_SITE" ]]; then
  cp -a "$NGINX_SITE" "$NGINX_BACKUP"
  echo "INFO: Nginx config backup: $NGINX_BACKUP"
fi
cat > "$NGINX_SITE" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    root /var/www/html;
    index index.php index.html;

    location = /health {
        access_log off;
        default_type text/plain;
        return 200 'ok';
    }
    location / { try_files $uri $uri/ =404; }
    location ~ \.php$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/run/php/php8.3-fpm.sock;
    }
    location ~ /\. { deny all; }
}
NGINX

if ! nginx -t; then
  echo "ERROR: Nginx config is invalid. Backup: $NGINX_BACKUP" >&2
  exit 1
fi
systemctl reload nginx

echo '--- Checks ---'
php -l "$WEB_ROOT/index.php"
curl -sS --max-time 10 -o /dev/null -w 'HTTP /index.php: %{http_code}\n' http://127.0.0.1/index.php
curl -sS --max-time 10 -o /dev/null -w 'HTTP /health: %{http_code}\n' http://127.0.0.1/health
printf 'DB route: '
ip route get "$DB_IP"
echo 'NOTE: DB route is temporary and will be lost after VM reboot.'
