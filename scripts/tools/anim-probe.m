// anim-probe: a timeline of the panel during a Dock animation.  Opens a window, minimizes it (Genie, or whatever the
// Dock's minimize effect is), restores it, and every 20 ms records how many frames reached the panel and the flip
// worker's GPU-idle wait (XeGfxAccel sysctls) and the GPU clock (debug.xegfx_gt_act, -1 on an older core).  Prints one line per sample with the phase, so a hitch shows up as a
// run of samples with no flips.  Read-only.
// Build: clang -fobjc-arc -framework Cocoa anim-probe.m -o anim-probe
// Usage: anim-probe [rounds=2] [width=900] [height=600]   (points)
#import <Cocoa/Cocoa.h>
#include <sys/sysctl.h>
#include <mach/mach_time.h>

static long long sc(const char *n)
{
    long long v = 0;
    size_t len = sizeof v;
    if (sysctlbyname(n, &v, &len, NULL, 0) != 0) return -1;
    if (len == 4) v = (long long)*(int *)&v;
    return v;
}

typedef struct { double t; const char *phase; long long flips, idleWaits, forced, idleLastUs, armLastUs, gtMhz; } Sample;
static Sample gS[4096];
static int gN;
static const char *volatile gPhase = "idle";
static double gT0;

static double now(void)
{
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e9;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        const int rounds = argc > 1 ? atoi(argv[1]) : 2;
        const double w = argc > 2 ? atof(argv[2]) : 900, h = argc > 3 ? atof(argv[3]) : 600;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(60, 60, w, h)
                                                    styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable
                                                      backing:NSBackingStoreBuffered defer:NO];
        win.title = @"anim-probe";
        NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
        v.wantsLayer = YES;
        v.layer.backgroundColor = CGColorCreateGenericRGB(0.2, 0.5, 0.9, 1);
        win.contentView = v;
        [win makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];
        gT0 = now();

        dispatch_queue_t q = dispatch_queue_create("sampler", DISPATCH_QUEUE_SERIAL);
        dispatch_async(q, ^{
            while (gN < 4096) {
                Sample *s = &gS[gN];
                s->t = now() - gT0;
                s->phase = gPhase;
                s->flips = sc("debug.xegfxaccel_iop_xe_flips");
                s->idleWaits = sc("debug.xegfxaccel_iop_xe_idle_waits");
                s->forced = sc("debug.xegfxaccel_iop_xe_idle_forced");
                s->idleLastUs = sc("debug.xegfxaccel_iop_xe_idle_last_us");
                s->armLastUs = sc("debug.xegfxaccel_iop_xe_arm_last_us");
                s->gtMhz = sc("debug.xegfx_gt_act");
                gN++;
                usleep(20000);
            }
        });

        __block int r = 0;
        __block void (^step)(void);
        step = ^{
            if (r >= rounds) {
                gPhase = "done";
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    int n = gN;
                    printf("t_s\tphase\tflips\tordered\tforced\tidle_last_us\tarm_last_us\tgt_mhz\n");
                    for (int i = 1; i < n; i++)
                        printf("%.3f\t%s\t%lld\t%lld\t%lld\t%lld\t%lld\t%lld\n", gS[i].t, gS[i].phase,
                               gS[i].flips - gS[i - 1].flips, gS[i].idleWaits - gS[i - 1].idleWaits,
                               gS[i].forced - gS[i - 1].forced, gS[i].idleLastUs, gS[i].armLastUs, gS[i].gtMhz);
                    fflush(stdout);
                    exit(0);
                });
                return;
            }
            r++;
            gPhase = "minimize";
            [win miniaturize:nil];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                gPhase = "restore";
                [win deminiaturize:nil];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    gPhase = "rest";
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), step);
                });
            });
        };
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), step);
        [NSApp run];
    }
    return 0;
}
