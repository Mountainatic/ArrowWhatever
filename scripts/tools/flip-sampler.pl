#!/usr/bin/perl
# flip-sampler: every 10 ms for N seconds, the accel's Xe flip count (debug.xegfxaccel_iop_xe_flips) with a timestamp in
# ms, so a stutter shows as a gap between flips.  Usage: flip-sampler.pl seconds > out.txt
use strict; use Time::HiRes qw(time sleep);
my $n = shift || 60; my $t0 = time; my $last = -1;
while (time - $t0 < $n) {
    my $f = `/usr/sbin/sysctl -n debug.xegfxaccel_iop_xe_flips`; chomp $f;
    if ($f != $last) { printf "%.1f %s\n", (time - $t0) * 1000, $f; $last = $f; }
    sleep 0.01;
}
