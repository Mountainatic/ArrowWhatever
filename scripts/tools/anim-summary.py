#!/usr/bin/python3
# 100 ms buckets of an anim-probe run (stdin): flips, ordered flips, forced arms, longest GPU-idle wait, GPU clock range.
import sys
from collections import OrderedDict
b = OrderedDict()
for l in sys.stdin.read().splitlines()[1:]:
    f = l.split('\t')
    k = (round(float(f[0]) // 0.1 * 0.1, 1), f[1])
    e = b.setdefault(k, [0, 0, 0, 0, [], []])
    e[0] += int(f[2]); e[1] += int(f[3]); e[2] += int(f[4]); e[3] = max(e[3], int(f[5]))
    if len(f) > 7 and int(f[7]) > 0: e[4].append(int(f[7]))
for (t, ph), (fl, o, fo, il, mhz, _) in b.items():
    if ph in ('minimize', 'restore'):
        g = '%4d-%4d MHz' % (min(mhz), max(mhz)) if mhz else '   (no clock)'
        print('%4.1f %-8s flips %2d ordered %2d forced %d idle_max %6d us  %s' % (t, ph, fl, o, fo, il, g))
