#!/usr/bin/env bash
set -euo pipefail

# Pick interface from default route
IFACE="$(ip route show default 2>/dev/null | awk 'NR==1{for(i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')"
IFACE="${IFACE:-}"

# If still empty, pick first non-lo interface that is UP
if [[ -z "$IFACE" ]]; then
  IFACE="$(ip -o link show up | awk -F': ' '$2!="lo"{print $2; exit}')"
fi

# If we truly can't find one, output something obvious
if [[ -z "$IFACE" || ! -d "/sys/class/net/$IFACE" ]]; then
  printf '{"text":"NET ?","tooltip":"No active interface found","class":"net-red"}\n'
  exit 0
fi


IP="$(ip -4 addr show "$IFACE" | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
IP="${IP:-no-ip}"

echo "{\"text\":\"${IFACE} ${IP}\"}"
