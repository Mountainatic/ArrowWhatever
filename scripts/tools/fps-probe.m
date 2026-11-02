// fps-probe: a window whose layer colour changes on every display-link tick, so WindowServer has to composite and
// present a new frame each vblank.  Prints the display link's nominal and actual rate and how many frames the app
// committed, after N seconds.  Read the accel counters around it to see how many of those frames reached the panel.
// Build: clang -fobjc-arc -framework Cocoa -framework QuartzCore -framework CoreVideo fps-probe.m -o fps-probe
// Usage: fps-probe [seconds=10] [width=1200] [height=800]
#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreVideo/CoreVideo.h>
#include <mach/mach_time.h>

static NSView *gView;
static volatile int64_t gTicks, gCommits;
static double gNominal;

static CVReturn tick(CVDisplayLinkRef link, const CVTimeStamp *now, const CVTimeStamp *out, CVOptionFlags f,
                     CVOptionFlags *fo, void *ctx)
{
    (void)link; (void)now; (void)f; (void)fo; (void)ctx;
    if (gNominal == 0 && out->videoRefreshPeriod)
        gNominal = (double)out->videoTimeScale / (double)out->videoRefreshPeriod;
    __sync_fetch_and_add(&gTicks, 1);
    dispatch_async(dispatch_get_main_queue(), ^{
        static int k;
        k++;
        [CATransaction begin];
        [CATransaction setDisableActions:YES];
        gView.layer.backgroundColor = CGColorCreateGenericRGB((k & 1) ? 1 : 0, (k >> 1) & 1, (k >> 2) & 1, 1);
        [CATransaction commit];
        __sync_fetch_and_add(&gCommits, 1);
    });
    return kCVReturnSuccess;
}

int main(int argc, char **argv)
{
    @autoreleasepool {
        double secs = argc > 1 ? atof(argv[1]) : 10;
        double w = argc > 2 ? atof(argv[2]) : 1200, h = argc > 3 ? atof(argv[3]) : 800;
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        NSWindow *win = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 100, w, h)
                                                    styleMask:NSWindowStyleMaskTitled
                                                      backing:NSBackingStoreBuffered defer:NO];
        win.title = @"fps-probe";
        gView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, w, h)];
        gView.wantsLayer = YES;
        win.contentView = gView;
        [win makeKeyAndOrderFront:nil];
        [NSApp activateIgnoringOtherApps:YES];

        CVDisplayLinkRef link;
        CVDisplayLinkCreateWithActiveCGDisplays(&link);
        CVDisplayLinkSetOutputCallback(link, tick, NULL);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            gTicks = gCommits = 0;
            uint64_t t0 = mach_absolute_time();
            CVDisplayLinkStart(link);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(secs * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                CVDisplayLinkStop(link);
                mach_timebase_info_data_t tb;
                mach_timebase_info(&tb);
                double el = (double)(mach_absolute_time() - t0) * tb.numer / tb.denom / 1e9;
                printf("elapsed %.2f s  display-link nominal %.1f Hz  ticks %.1f/s  commits %.1f/s\n", el, gNominal,
                       gTicks / el, gCommits / el);
                fflush(stdout);
                exit(0);
            });
        });
        [NSApp run];
    }
    return 0;
}
