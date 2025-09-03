#!/usr/bin/env bash
set -euo pipefail

# Load MACHINE_NAME_LIST (array) and MACHINE_NAME_PREFIX from ../config.env
source "$(dirname "$0")/../config.env"

INTERVAL="${1:-60}"
CONCURRENCY="${CONCURRENCY:-8}"
GPU_MODEL_WIDTH="${GPU_MODEL_WIDTH:-8}"   # width for short model name (e.g., A4000, A100-80GB)

SSH_OPTS=(
  -o BatchMode=yes
  -o ConnectTimeout=2
  -o StrictHostKeyChecking=accept-new
  -o LogLevel=ERROR
)

while true; do
  # Build host list (supports array or space-separated string)
  hosts=()
  for NAME in ${MACHINE_NAME_LIST[@]:-$MACHINE_NAME_LIST}; do
    hosts+=("${MACHINE_NAME_PREFIX}-${NAME}")
  done

  tmpdir="$(mktemp -d)"
  trap "rm -rf '$tmpdir'" EXIT

  # Parallel fetch (no -n to avoid xargs warning with -I)
  printf "%s\n" "${hosts[@]}" | xargs -P "$CONCURRENCY" -I{} bash -c '
    set -euo pipefail
    host="$1"
    SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=2 -o StrictHostKeyChecking=accept-new -o LogLevel=ERROR)
    out="$(ssh "${SSH_OPTS[@]}" "$host" \
      "command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits" \
      2>/dev/null || true)"
    if [[ -n "$out" ]]; then
      f="'"$tmpdir"'"/"$(echo "$host" | tr "/:" "__")".csv
      printf "%s\n" "$out" > "$f"
    fi
  ' _ {}

  # Collect responders
  responded=()
  for h in "${hosts[@]}"; do
    f="$tmpdir/$(echo "$h" | tr '/:' '__').csv"
    [[ -s "$f" ]] && responded+=("$h")
  done

  clear || tput clear || true

  if [[ ${#responded[@]} -eq 0 ]]; then
    echo "No hosts responded. (Only showing hosts that are reachable and have nvidia-smi)"
    echo
    rm -rf "$tmpdir"; trap - EXIT
    sleep "$INTERVAL"
    continue
  fi

  # Layout: compute host column width
  HOST_W=4
  for h in "${responded[@]}"; do
    (( ${#h} > HOST_W )) && HOST_W=${#h}
  done
  ((HOST_W+=1))  # small padding

  # Rows (one line per GPU; only the first line shows the host)
  for h in "${responded[@]}"; do
    f="$tmpdir/$(echo "$h" | tr '/:' '__').csv"
    awk -v FS=',' -v host="$h" -v hostw="$HOST_W" -v modelw="$GPU_MODEL_WIDTH" '
      function trim(s){ gsub(/^ +| +$/,"",s); return s }
      function shortname(name,  s,m,a,n,i){
        s=trim(name)
        if (match(s, /(A[0-9]{3,4})([- ]([0-9]+GB))?/, m)) return (m[3]!="") ? m[1] "-" m[3] : m[1]
        if (match(s, /(RTX[ ]?[0-9]{3,4}(?:[ ]?Ti|[ ]?SUPER)?)/, m)) { gsub(/[ ]+/,"",m[1]); return m[1] }
        n=split(s,a,/[[:space:]]+/)
        for(i=n;i>=2;i--) if(a[i] ~ /^[0-9]+GB$/ && a[i-1] ~ /(A[0-9]{3,4}|[3-9][0-9]{2,4}(Ti)?)$/) return a[i-1] "-" a[i]
        for(i=n;i>=1;i--) if(a[i] ~ /([A-Za-z].*[0-9]|[0-9].*[A-Za-z]|-)/) return a[i]
        return a[n]
      }
      {
        for(i=1;i<=NF;i++) $i=trim($i)
        idx      = $1 + 0
        model    = shortname($2)
        usedGB   = ($3 + 0)/1024
        totalGBf = ($4 + 0)/1024
        util     = $5 + 0

        # Format: g0 <MODEL> <UTIL%> <USED/TOTAL>  (e.g., "g0 A4000   0%  0.0/16")
        # total printed as integer if whole, else 1 decimal
        totalStr = (int(totalGBf)==totalGBf) ? sprintf("%.0f", totalGBf) : sprintf("%.1f", totalGBf)
        line = sprintf("g%-2d %-*.*s %3.0f%% %4.1f/%s", idx, modelw, modelw, model, util, usedGB, totalStr)

        lines[idx] = line
        if (idx > maxidx) maxidx = idx
      }
      END {
        first = 1
        for (i=0; i<=maxidx; i++) if (i in lines) {
          if (first) { printf "%-*s  %s\n", hostw, host, lines[i]; first=0 }
          else       { printf "%-*s  %s\n", hostw, "",   lines[i] }
        }
      }
    ' "$f"
  done

  rm -rf "$tmpdir"; trap - EXIT
  sleep "$INTERVAL"
done

