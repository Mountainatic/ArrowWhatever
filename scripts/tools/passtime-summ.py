# passtime-summ: summarise a WindowServer nvmtl-passtime log (§32.17): per-cb GPU time and time per target size.
# Usage: passtime-summ.py passtime.log[.gz]
import sys, re, gzip, statistics as st
from collections import defaultdict
cb, size = defaultdict(float), defaultdict(lambda: [0, 0.0])
for l in (gzip.open(sys.argv[1], 'rt') if sys.argv[1].endswith('.gz') else open(sys.argv[1])):
    m = re.match(r'cb (\d+) pass \d+ (\d+x\d+) fmt \d+ gpu_us ([\d.]+)', l)
    if not m: continue
    cb[int(m[1])] += float(m[3]); size[m[2]][0] += 1; size[m[2]][1] += float(m[3])
v = sorted(cb.values()); tot = sum(v)
q = lambda p: v[min(len(v) - 1, int(p * len(v)))]
print('%d cbs, %d passes, GPU %.1f ms total; per cb p50 %.2f p90 %.2f max %.2f ms' % (len(v), sum(n for n, _ in size.values()), tot / 1e3, q(.5) / 1e3, q(.9) / 1e3, v[-1] / 1e3))
for s, (n, us) in sorted(size.items(), key=lambda x: -x[1][1])[:6]:
    print('  %-10s %5d passes  avg %6.2f ms  %4.1f%% of GPU' % (s, n, us / n / 1e3, 100 * us / tot))
