# passtime-sizes: per (target size, shader pair) pass time and per-draw time, and the cb distribution, for one or two
# passtime logs with draw counts (§36.12 genie captures).  Usage: passtime-sizes.py a.log[.gz] [b.log[.gz]]
import re, sys, collections, gzip, os
def load(f):
    d = collections.defaultdict(list); cb = collections.defaultdict(float)
    for l in (gzip.open(f, 'rt') if f.endswith('.gz') else open(f)):
        m = re.match(r'cb (\d+) pass \d+ (\d+x\d+) fmt \d+ gpu_us ([\d.]+) gap_us [\d.]+ fs (\w+) (\w+) \w+ \w+ draws (\d+)', l)
        if m: d[(m[2], m[4] + ' ' + m[5])].append((float(m[3]) / 1e3, int(m[6]))); cb[m[1]] += float(m[3]) / 1e3
    return d, sorted(cb.values())
logs = [load(f) for f in sys.argv[1:]]
for f, (d, v) in zip(sys.argv[1:], logs):
    print('%s: %d cbs  p50 %.2f p90 %.2f p99 %.1f max %.1f ms; >8 ms %d, >12 ms %d' % (os.path.basename(f), len(v), v[len(v)//2], v[int(.9*len(v))], v[int(.99*len(v))], v[-1], sum(1 for x in v if x > 8), sum(1 for x in v if x > 12)))
keys = [('3840x2340', '394291c7 44d03494'), ('3979x2479', '394291c7 44d03494'), ('4067x2567', '394291c7 44d03494'), ('3979x2479', 'c8ba9c29 c8f53aed'), ('3840x2400', 'f1c2052c 00000000'), ('3840x2400', '394291c7 44d03494')]
for k in keys:
    out = []
    for d, _ in logs:
        r = sorted(d.get(k, []))
        out.append('n=%4d med %6.2f ms max %6.2f, %6.0f us/draw' % (len(r), r[len(r)//2][0], r[-1][0], sorted(x[0] * 1e3 / max(x[1], 1) for x in r)[len(r)//2]) if r else 'n=   0')
    print('%-10s %-18s | %s' % (k[0], k[1], ' | '.join(out)))
