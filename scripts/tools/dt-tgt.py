# dt-tgt: rank the draws of a drawtime log (tgtid plugin, §37.25) by GPU time per cb, with source and target surface
import re, sys, collections
L = [l.rstrip() for l in open(sys.argv[1]) if l.startswith('cb ') and (' tgt ' in l or ' id ' in l)]
cbs = collections.OrderedDict()
for l in L:
    m = re.match(r'cb (\d+) pass (\d+) ', l); cbs.setdefault(int(m[1]), []).append(l)
def cls(i): return 'fb%d' % (int(i, 16) & 0xffff) if i.startswith('8') else ('img' if i != '00000000' else '-')
agg = collections.defaultdict(lambda: [0, 0.0])
for cb, ls in cbs.items():
    tg = {}
    for l in ls:
        m = re.match(r'cb \d+ pass (\d+) (\d+x\d+) .* tgt (\w+)', l)
        if m: tg[m[1]] = m[3]
    for l in ls:
        m = re.match(r'cb \d+ pass (\d+) draw (\d+) gpu_us ([\d.]+) fs (\w+) n (\d+) sc (\d+x\d+) t0 (\S+) (\S+) id (\w+)', l)
        if not m: continue
        key = (m[4], m[5], m[6], m[7] + ' ' + m[8], 'fb' if m[9].startswith('8') else cls(m[9]), 'fb' if tg.get(m[1], '0').startswith('8') else cls(tg.get(m[1], '00000000')))
        agg[key][0] += 1; agg[key][1] += float(m[3])
n = len(cbs); tot = sum(v[1] for v in agg.values())
print('%d cbs, GPU %.2f ms per cb (draws serialised)' % (n, tot / n / 1e3))
for k, (c, us) in sorted(agg.items(), key=lambda kv: -kv[1][1])[:int(sys.argv[2]) if len(sys.argv) > 2 else 10]:
    print('  %6.0f us/cb  x%.2f  fs %s n %-3s sc %-9s src %-16s %-3s -> %s' % (us / n, c / n, *k))
