#!/usr/bin/env bash
set -euo pipefail

# NVIDIA GPU stats via nvidia-smi.
# Output format is JSON because Waybar "return-type": "json".

if ! command -v nvidia-smi >/dev/null 2>&1; then
  echo '{"text":"GPU n/a","tooltip":"nvidia-smi not found","class":"warn","icon":"gpu"}'
  exit 0
fi

# ---- thresholds ----
TEMP_WARN=75
TEMP_CRIT=85

VRAM_WARN=85
VRAM_CRIT=95
# --------------------

# Query: utilization %, temperature C, power draw W, total memory MiB, used memory MiB
read -r util temp pwr mem_total mem_used < <(
  nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,power.draw,memory.total,memory.used \
    --format=csv,noheader,nounits | head -n1 | tr ',' ' ' | awk '{print $1, $2, $3, $4, $5}'
)

# Guard against empty/NA output
util="${util:-0}"
temp="${temp:-0}"
pwr="${pwr:-0}"
mem_total="${mem_total:-0}"
mem_used="${mem_used:-0}"

# VRAM percent (integer). Avoid division by zero.
vram_pct=0
if [[ "$mem_total" -gt 0 ]]; then
  vram_pct=$(( (mem_used * 100) / mem_total ))
fi

# Determine class based on the "worst" of temp + vram
# priority: critical > warning > normal
class="gpu"

# temp-based escalation
if [[ "$temp" -ge "$TEMP_CRIT" ]]; then
  class="critical"
elif [[ "$temp" -ge "$TEMP_WARN" ]]; then
  class="warning"
fi

# vram-based escalation (may override)
if [[ "$vram_pct" -ge "$VRAM_CRIT" ]]; then
  class="critical"
elif [[ "$vram_pct" -ge "$VRAM_WARN" ]]; then
  # only raise to warning if we aren't already critical
  if [[ "$class" != "critical" ]]; then
    class="warning"
  fi
fi

text="GPU ${util}% ${temp}C VRAM ${vram_pct}%"
tooltip="GPU Util: ${util}%\nTemp: ${temp} C\nPower: ${pwr} W\nVRAM: ${mem_used} / ${mem_total} MiB (${vram_pct}%)\nClass: ${class}"

echo "{\"text\":\"${text}\",\"tooltip\":\"${tooltip}\",\"class\":\"${class}\",\"icon\":\"gpu\"}"
