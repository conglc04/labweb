#!/usr/bin/env bash
# oVPC lab: persist the tested host route to the DB in Netplan.
# This script DOES NOT apply the network configuration or reboot.
set -Eeuo pipefail

DB_IP="10.4.20.114"
NEXT_HOP="10.4.10.210"
ORIGIN="90-ovpc-db-route"
ROUTE_FILE="/etc/netplan/${ORIGIN}.yaml"

if [[ $EUID -ne 0 ]]; then
  echo "ERROR: Run as root (sudo bash configure-db-route.sh)." >&2
  exit 1
fi
if ! command -v netplan >/dev/null 2>&1; then
  echo "ERROR: netplan not installed." >&2
  exit 1
fi
if [[ ! -f /etc/netplan/50-cloud-init.yaml ]]; then
  echo "ERROR: Expected /etc/netplan/50-cloud-init.yaml is missing. Stop for review." >&2
  exit 1
fi
if ! netplan get network.ethernets.all | grep -q 'dhcp4: true'; then
  echo "ERROR: Expected DHCP-enabled Netplan definition 'all' not found. Stop for review." >&2
  exit 1
fi

# Do not overwrite an existing route file that might contain other rules.
if [[ -e "$ROUTE_FILE" ]]; then
  echo "ERROR: $ROUTE_FILE already exists. Inspect it before modifying." >&2
  exit 1
fi

echo "Configuring route ${DB_IP}/32 via ${NEXT_HOP} for interface Netplan ID 'all'..."
netplan set --origin-hint="$ORIGIN" "network.ethernets.all.routes=[{to: ${DB_IP}/32, via: ${NEXT_HOP}}]"
chmod 600 "$ROUTE_FILE"

if ! netplan generate; then
  echo "ERROR: Netplan validation failed. Moving the new file aside." >&2
  mv "$ROUTE_FILE" "/root/${ORIGIN}.yaml.failed"
  exit 1
fi

echo "PASS: Netplan syntax is valid. Configuration saved to $ROUTE_FILE"
echo '--- Effective Netplan device config ---'
netplan get network.ethernets.all
printf '\n%s\n' 'NOT APPLIED YET. Next, on the VM Console:'
echo '  netplan try --timeout 120'
echo 'Press ENTER to accept ONLY if the VM remains reachable.'
echo 'Then check:'
echo "  ip -4 route get ${DB_IP}"
echo "  curl -s -o /dev/null -w '%{http_code}\\n' http://127.0.0.1/index.php"
