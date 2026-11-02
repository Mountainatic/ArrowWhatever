#!/bin/sh
# §32.15: prints a timestamped line whenever a surface-mark wait times out (100 ms) or the flip worker's longest mark
# wait grows, with the snapshot and idle counters next to it.  Read-only.  Usage: mark-timeout-watch.sh [seconds=1800]
end=$(( $(date +%s) + ${1:-1800} )); last=""
while [ "$(date +%s)" -lt "$end" ]; do
    cur=$(sysctl -n debug.xegfxaccel_surface_gpu_timeouts debug.xegfxaccel_iop_xe_mark_max_us debug.xegfxaccel_iop_xe_snap_timeouts debug.xegfxaccel_iop_xe_idle_forced | tr '\n' ' ')
    [ "$cur" != "$last" ] && echo "$(date +%H:%M:%S) timeouts/mark_max_us/snap_timeouts/idle_forced $cur"
    last=$cur; sleep 0.5
done
