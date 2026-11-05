# tl-summ: percentiles of the accel's per-frame flip timeline (sysctl debug.nvaccel_iop_xe_tl, §37.9)
import sys
rows = []
for l in open(sys.argv[1]):
    p = l.split()
    if len(p) >= 10 and p[0].lstrip('-').isdigit(): rows.append([int(x) for x in p[:7]])
names = ['gap', 'queued->pop', 'pop->mark', 'mark->arm', 'arm->latch', 'latch->sig', 'sig->next']
print(len(rows), 'frames')
for i, n in enumerate(names):
    v = sorted(r[i] for r in rows if r[i] >= 0)
    if v: print('%-12s p10 %6d p50 %6d p90 %6d us' % (n, v[len(v) // 10], v[len(v) // 2], v[len(v) * 9 // 10]))
