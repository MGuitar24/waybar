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

RX_NOW=$(cat "/sys/class/net/$IFACE/statistics/rx_bytes")
TX_NOW=$(cat "/sys/class/net/$IFACE/statistics/tx_bytes")
TS_NOW=$(date +%s%N) # nanoseconds

STATE="/tmp/waybar-net-${IFACE}.state"

# Defaults if no prior state
RX_OLD=$RX_NOW
TX_OLD=$TX_NOW
TS_OLD=$TS_NOW

if [[ -f "$STATE" ]]; then
  read -r RX_OLD TX_OLD TS_OLD < "$STATE" || true
fi

# Save state for next run ASAP
printf "%s %s %s\n" "$RX_NOW" "$TX_NOW" "$TS_NOW" > "$STATE"

# Compute elapsed seconds (as float)
DT_NS=$((TS_NOW - TS_OLD))
if (( DT_NS <= 0 )); then DT_NS=1000000000; fi
DT_S=$(awk -v ns="$DT_NS" 'BEGIN{printf "%.6f", ns/1000000000}')

DOWN_BPS=$(awk -v a="$RX_NOW" -v b="$RX_OLD" -v dt="$DT_S" 'BEGIN{v=(a-b)/dt; if(v<0)v=0; printf "%.0f", v}')
UP_BPS=$(awk -v a="$TX_NOW" -v b="$TX_OLD" -v dt="$DT_S" 'BEGIN{v=(a-b)/dt; if(v<0)v=0; printf "%.0f", v}')

fmt_rate() {
  local bps="$1"
  if (( bps < 1024*1024 )); then
    awk -v b="$bps" 'BEGIN{printf "%.0fkB/s", b/1024}'
  else
    awk -v b="$bps" 'BEGIN{printf "%.1fMB/s", b/1024/1024}'
  fi
}

rate_level() {
  local bps="$1"
  if (( bps < 1024*1024 )); then
    echo "green"
  elif (( bps <= 15*1024*1024 )); then
    echo "yellow"
  else
    echo "red"
  fi
}

level_color() {
  case "$1" in
    green)  echo "#2ecc71" ;;  # green
    yellow) echo "#f1c40f" ;;  # yellow
    red)    echo "#ff6b6b" ;;  # red
    *)      echo "#6c6c6c" ;;  # fallback gray
  esac
}

UP_TXT="$(fmt_rate "$UP_BPS")"
DOWN_TXT="$(fmt_rate "$DOWN_BPS")"

UP_LVL="$(rate_level "$UP_BPS")"
DOWN_LVL="$(rate_level "$DOWN_BPS")"

UP_COLOR="$(level_color "$UP_LVL")"
DOWN_COLOR="$(level_color "$DOWN_LVL")"

# Keep a single module class if you still want it (based on DOWN), but the underline is split.
CLASS="net-${DOWN_LVL}"

# Pango markup: separate underlines/colors for ↑ and ↓ segments
TEXT="↑<span underline='single' underline_color='${UP_COLOR}'>${UP_TXT}</span> ↓<span underline='single' underline_color='${DOWN_COLOR}'>${DOWN_TXT}</span>"
TOOLTIP="Interface: ${IFACE}\nDown: ${DOWN_TXT}\nUp: ${UP_TXT}\n(Computed over ${DT_S}s)"

# JSON escape quotes
TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/"/\\"/g')
TIP_ESC=$(printf '%s' "$TOOLTIP" | sed 's/"/\\"/g')

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$TEXT_ESC" "$TIP_ESC" "$CLASS"

