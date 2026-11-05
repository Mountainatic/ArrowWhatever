// genie-fps: panel frame rate, steady and during the Genie minimize/restore animation.
// Counts real flips through the accel's counter (debug.xegfxaccel_iop_xe_flips), sampled every 0.5 ms on a thread, so
// it measures what reached the panel, not what the app drew.
//   1. steady: a window repaints on every display-link tick for S seconds -> flips/s, frame-time p50/p90/p99, max gap
//   2. genie:  the tool minimizes and restores its own window N times -> per animation: duration, flips, fps, max gap
// Prints a summary line (tab separated) for fps-history; see genie-fps.sh.
// Build: clang -O2 -fobjc-arc -framework Cocoa -framework QuartzCore -framework CoreVideo genie-fps.m -o genie-fps
// Usage: genie-fps [steady_seconds=5] [genie_cycles=4] [width=1400] [height=900]
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#include <sys/sysctl.h>
#include <mach/mach_time.h>
#include <pthread.h>

static double now_s(void)
{
    static mach_timebase_info_data_t tb;
    if (!tb.denom) mach_timebase_info(&tb);
    return (double)mach_absolute_time() * tb.numer / tb.denom / 1e9;
}

static long flips(void)
{
    int64_t v = 0; size_t n = sizeof v;
    if (sysctlbyname("debug.xegfxaccel_iop_xe_flips", &v, &n, NULL, 0) != 0) return -1;
    return n == 4 ? (long)*(int32_t *)&v : (long)v;
}

#define MAXEV 200000
static double gEvT[MAXEV];
static volatile int gEvN;
static volatile int gStop;
static volatile long gFreqSum, gFreqN, gFreqBusy, gFreqMax, gFreqAt550;
static volatile int gFreqOn;

static int gt_act(void)
{
    int v = 0; size_t n = sizeof v;
    return sysctlbyname("debug.xegfx_gt_act", &v, &n, NULL, 0) == 0 ? v : -1;
}

static void *sampler(void *arg)
{
    (void)arg;
    long last = flips();
    int k = 0;
    while (!gStop) {
        if (gFreqOn && (++k % 20) == 0) {
            int f = gt_act();
            if (f > 0) { gFreqSum += f; gFreqBusy++; if (f > gFreqMax) gFreqMax = f; if (f <= 550) gFreqAt550++; }
            if (f >= 0) gFreqN++;
        }
        long f = flips();
        if (f > last) {
            double t = now_s();
            for (long k = last; k < f && gEvN < MAXEV; k++) gEvT[gEvN++] = t;
            last = f;
        }
        usleep(500);
    }
    return NULL;
}

static int cmpd(const void *a, const void *b)
{
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

typedef struct { int n; double fps, p50, p90, p99, maxgap; } stats;

static stats window_stats(double t0, double t1)
{
    stats s = { 0 };
    static double gaps[MAXEV];
    int ng = 0; double prev = t0, last = t0;
    for (int i = 0; i < gEvN; i++) {
        double t = gEvT[i];
        if (t < t0 || t > t1) continue;
        s.n++;
        if (t > prev) gaps[ng++] = (t - prev) * 1e3;
        prev = t; last = t;
    }
    if (t1 > last) gaps[ng++] = (t1 - last) * 1e3;
    s.fps = s.n / (t1 - t0);
    if (ng) {
        qsort(gaps, ng, sizeof gaps[0], cmpd);
        s.p50 = gaps[ng / 2]; s.p90 = gaps[(int)(ng * 0.9)]; s.p99 = gaps[(int)(ng * 0.99) < ng ? (int)(ng * 0.99) : ng - 1];
        s.maxgap = gaps[ng - 1];
    }
    return s;
}

static NSWindow *gWin;
static NSView *gView;
static CVDisplayLinkRef gLink;
static volatile int gAnimate;
static double gNominal;

static CVReturn tick(CVDisplayLinkRef l, const CVTimeStamp *n, const CVTimeStamp *o, CVOptionFlags f, CVOptionFlags *fo, void *c)
{
    (void)l; (void)n; (void)f; (void)fo; (void)c;
    if (gNominal == 0 && o->videoRefreshPeriod) gNominal = (double)o->videoTimeScale / (double)o->videoRefreshPeriod;
    if (!gAnimate) return kCVReturnSuccess;
    dispatch_async(dispatch_get_main_queue(), ^{
        static int k; k++;
        [CATransaction begin]; [CATransaction setDisableActions:YES];
        CGColorRef c = CGColorCreateGenericRGB(0.2 + 0.6 * ((k >> 0) & 1), 0.2 + 0.6 * ((k >> 1) & 1), 0.2 + 0.6 * ((k >> 2) & 1), 1);
        gView.layer.backgroundColor = c; CGColorRelease(c);
        [CATransaction commit];
    });
    return kCVReturnSuccess;
}

static void spin(double secs)
{
    double end = now_s() + secs;
    while (now_s() < end)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.005]];
}

static int wait_until(BOOL (^cond)(void), double timeout)
{
    double end = now_s() + timeout;
    while (!cond()) {
        if (now_s() > end) return 0;
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    }
    return 1;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        setvbuf(stdout, NULL, _IONBF, 0);
        double steady = argc > 1 ? atof(argv[1]) : 5;
        int cycles = argc > 2 ? atoi(argv[2]) : 4;
        double w = argc > 3 ? atof(argv[3]) : 1400, h = argc > 4 ? atof(argv[4]) : 900;
        if (flips() < 0) { fprintf(stderr, "cannot read debug.xegfxaccel_iop_xe_flips (XeGfx accel not loaded?)\n"); return 1; }

        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSRect vis = NSScreen.mainScreen.visibleFrame;
        NSRect r = NSMakeRect(NSMidX(vis) - w / 2, NSMidY(vis) - h / 2, w, h);
        gWin = [[NSWindow alloc] initWithContentRect:r
                                           styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskClosable
                                             backing:NSBackingStoreBuffered defer:NO];
        gWin.title = @"genie-fps";
        gWin.releasedWhenClosed = NO;
        gView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
        gView.wantsLayer = YES;
        gView.layer.backgroundColor = CGColorGetConstantColor(kCGColorWhite);
        NSTextField *label = [NSTextField labelWithString:@"genie-fps: measuring, please don't touch this window"];
        label.font = [NSFont systemFontOfSize:28 weight:NSFontWeightSemibold];
        label.frame = NSMakeRect(40, h / 2 - 20, w - 80, 40);
        [gView addSubview:label];
        gWin.contentView = gView;
        [gWin makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];

        pthread_t th; pthread_create(&th, NULL, sampler, NULL);
        CVDisplayLinkCreateWithActiveCGDisplays(&gLink);
        CVDisplayLinkSetOutputCallback(gLink, tick, NULL);
        CVDisplayLinkStart(gLink);
        spin(1.0);

        double s0 = now_s();
        gAnimate = 1; gFreqOn = 1;
        spin(steady);
        gAnimate = 0; gFreqOn = 0;
        double s1 = now_s();
        stats st = window_stats(s0 + 0.2, s1);
        printf("display link nominal %.1f Hz\n", gNominal);
        printf("steady   %5.1f fps  frame p50 %5.2f p90 %5.2f p99 %5.2f max %6.1f ms  (%d flips in %.1f s)\n",
               st.fps, st.p50, st.p90, st.p99, st.maxgap, st.n, s1 - s0 - 0.2);
        if (gFreqBusy)
            printf("gpu clock while busy: avg %ld MHz, max %ld MHz, %.0f%% of busy samples at 550 MHz (busy %ld of %ld samples)\n",
                   gFreqSum / gFreqBusy, gFreqMax, 100.0 * gFreqAt550 / gFreqBusy, gFreqBusy, gFreqN);
        spin(0.5);

        double gfps[64], gmax[64], gdur[64]; int ng = 0;
        for (int c = 0; c < cycles && ng < 62; c++) {
            for (int dir = 0; dir < 2; dir++) {
                double t0 = now_s();
                if (dir == 0) [gWin miniaturize:nil]; else [gWin deminiaturize:nil];
                int ok = wait_until(^BOOL { return dir == 0 ? gWin.isMiniaturized : (!gWin.isMiniaturized && gWin.isVisible); }, 5);
                double t1 = now_s();
                spin(0.05);
                double t2 = now_s();
                stats g = window_stats(t0, t1);
                gfps[ng] = g.fps; gmax[ng] = g.maxgap; gdur[ng] = (t1 - t0) * 1e3; ng++;
                printf("genie %-8s %5.1f fps  %3d flips in %5.0f ms  frame p50 %5.2f p90 %5.2f max %6.1f ms%s\n",
                       dir == 0 ? "minimize" : "restore", g.fps, g.n, (t1 - t0) * 1e3, g.p50, g.p90, g.maxgap, ok ? "" : "  (timed out)");
                (void)t2;
                spin(0.6);
            }
        }
        double sf = 0, sm = 0, sd = 0, worst = 0;
        for (int i = 0; i < ng; i++) { sf += gfps[i]; sm += gmax[i]; sd += gdur[i]; if (gmax[i] > worst) worst = gmax[i]; }
        if (ng) printf("genie    %5.1f fps average over %d animations, average longest gap %.1f ms, worst %.1f ms, avg duration %.0f ms\n",
                       sf / ng, ng, sm / ng, worst, sd / ng);

        gStop = 1; pthread_join(th, NULL);
        CVDisplayLinkStop(gLink);
        printf("SUMMARY\t%.1f\t%.2f\t%.2f\t%.1f\t%.1f\t%.1f\t%.1f\t%ld\t%.0f\n", st.fps, st.p50, st.p99, st.maxgap,
               ng ? sf / ng : 0, ng ? sm / ng : 0, worst, gFreqBusy ? gFreqSum / gFreqBusy : 0,
               gFreqBusy ? 100.0 * gFreqAt550 / gFreqBusy : 0);
        [gWin close];
    }
    return 0;
}
