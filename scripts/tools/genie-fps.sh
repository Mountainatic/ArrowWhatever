#!/bin/sh
# genie-fps.sh: run genie-fps (steady and Genie frame rate) and append one line to data/fps-history.tsv with system
# and WindowServer uptime, so a slowdown over time shows up across runs.  Usage: tools/genie-fps.sh [steady_s] [cycles]
set -e
HERE=$(cd "$(dirname "$0")" && pwd); ROOT=$(dirname "$HERE")
BIN="$HERE/genie-fps"
if [ ! -x "$BIN" ] || [ "$HERE/genie-fps.m" -nt "$BIN" ]; then
  clang -O2 -fobjc-arc -framework Cocoa -framework QuartzCore -framework CoreVideo "$HERE/genie-fps.m" -o "$BIN"
fi
OUT=$("$BIN" "${1:-5}" "${2:-4}" 2>/dev/null)
echo "$OUT" | grep -v '^SUMMARY'
boot=$(sysctl -n kern.boottime | sed 's/^{ sec = \([0-9]*\).*/\1/'); nowt=$(date +%s)
ws=$(pgrep -x WindowServer | head -1); wsup=$(ps -o etime= -p "$ws" | tr -d ' ')
H="$ROOT/data/fps-history.tsv"
[ -f "$H" ] || printf 'time\tuptime_min\tws_uptime\tsteady_fps\tp50_ms\tp99_ms\tmaxgap_ms\tgenie_fps\tgenie_avg_maxgap_ms\tgenie_worst_ms\tgpu_busy_avg_mhz\tgpu_pct_at_550\n' > "$H"
echo "$OUT" | grep '^SUMMARY' | cut -f2- | while read -r l; do
  printf '%s\t%d\t%s\t%s\n' "$(date '+%m-%dT%H:%M:%S')" $(( (nowt - boot) / 60 )) "$wsup" "$l" | tr ' ' '\t' >> "$H"
done
tail -1 "$H"
