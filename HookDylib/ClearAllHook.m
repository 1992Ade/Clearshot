// ============================================================================
// libClearAllHook.dylib — injected into SpringBoard via TFInjector.
//
// Hooks the main app-switcher view controller's viewDidLoad so we can add
// a "Clear All" button in the top-right corner. Tapping it enumerates every
// running process via sysctl KERN_PROC_ALL (same walker CSProcessUtils uses)
// and sends SIGTERM to every pid whose executable name isn't on the
// exclusion list.
//
// Exclusion list (process names that MUST stay alive to avoid a respring
// or a broken audio/network session):
//   • SpringBoard           — killing it is a respring
//   • backboardd / BackBoard — SpringBoard's parent
//   • frontboardd            — application lifecycle manager
//   • mediaserverd          — audio session manager; killing it kills audio
//   • cfprefsd              — NSUserDefaults daemon
//   • lockdownd              — USB + tethering daemon
//   • launchd                — init
//   • trustd                 — certificate validator
//   • trolltoreserved        — TrollStore install daemon
//   • ClearShot              — us. We'd kill ourselves otherwise.
//
// Everything else is fair game.
// ============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <sys/sysctl.h>
#import <sys/types.h>
#import <signal.h>
#import <errno.h>
#import <dlfcn.h>

// ----------------------------------------------------------------------------
// Private BKS declarations. BKSTerminate* accepts a bundleId and a reason
// code; same mechanism iOS uses when the user force-quits from the native
// switcher. Resolved at runtime so a missing symbol doesn't break dyld
// loading.
// ----------------------------------------------------------------------------
typedef void (*bks_terminate_fn)(NSString *bundleId, int reason,
                                  int subReason, NSString *description);

static bks_terminate_fn cah_bks_terminate(void) {
    static bks_terminate_fn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/"
                          "BackBoardServices.framework/BackBoardServices",
                          RTLD_LAZY);
        if (h) fn = (bks_terminate_fn)dlsym(h,
            "BKSTerminateApplicationForReasonAndReportWithDescription");
    });
    return fn;
}

// ----------------------------------------------------------------------------
// Exclusion list.
// ----------------------------------------------------------------------------
static NSSet<NSString *> *cah_exclusion_set(void) {
    static NSSet *s = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        s = [NSSet setWithObjects:
             @"SpringBoard",
             @"backboardd",
             @"BackBoard",
             @"frontboardd",
             @"mediaserverd",
             @"cfprefsd",
             @"lockdownd",
             @"launchd",
             @"trustd",
             @"trolltoreserved",
             @"trollstored",
             @"trollstorehelper",
             @"ClearShot",     // TrollBox's binary
             nil];
    });
    return s;
}

// ----------------------------------------------------------------------------
// sysctl walker — same pattern as TrollBox's CSProcessUtils.m. Returns an
// array of @{@"pid": NSNumber, @"name": NSString} for every running proc.
// ----------------------------------------------------------------------------
static NSArray<NSDictionary *> *cah_list_processes(void) {
    int mib[3] = { CTL_KERN, KERN_PROC, KERN_PROC_ALL };
    size_t length = 0;
    if (sysctl(mib, 3, NULL, &length, NULL, 0) < 0) return @[];
    struct kinfo_proc *info = malloc(length);
    if (!info) return @[];
    if (sysctl(mib, 3, info, &length, NULL, 0) < 0) {
        free(info);
        return @[];
    }

    int count = (int)(length / sizeof(struct kinfo_proc));
    static int argMax = 0;
    if (argMax == 0) {
        size_t s = sizeof(argMax);
        if (sysctl((int[]){ CTL_KERN, KERN_ARGMAX }, 2, &argMax, &s, NULL, 0) == -1) {
            argMax = 4096;
        }
    }

    NSMutableArray *out = [NSMutableArray array];
    for (int i = 0; i < count; i++) {
        pid_t pid = info[i].kp_proc.p_pid;
        if (pid <= 1) continue;   // skip launchd + kernel
        size_t s = argMax;
        char *buf = malloc(s);
        if (!buf) continue;
        NSString *name = nil;
        if (sysctl((int[]){ CTL_KERN, KERN_PROCARGS2, pid }, 3,
                   buf, &s, NULL, 0) == 0) {
            NSString *execPath = [NSString stringWithCString:(buf + sizeof(int))
                                                     encoding:NSUTF8StringEncoding];
            name = [execPath lastPathComponent];
        }
        free(buf);
        if (!name.length) continue;
        [out addObject:@{ @"pid": @(pid), @"name": name }];
    }
    free(info);
    return out;
}

// ----------------------------------------------------------------------------
// Clear-all action.
// ----------------------------------------------------------------------------
static void cah_perform_clear_all(void) {
    @try {
        NSSet *skip = cah_exclusion_set();
        NSArray *procs = cah_list_processes();
        NSUInteger killed = 0;
        for (NSDictionary *d in procs) {
            NSString *name = d[@"name"];
            pid_t pid = [d[@"pid"] intValue];
            if ([skip containsObject:name]) continue;
            // Prefer BKS terminate (= clean app lifecycle) when we can
            // resolve a bundleId. For now go straight to SIGTERM — it's
            // simpler and works for every process whose euid matches ours.
            if (kill(pid, SIGTERM) == 0) {
                killed++;
                NSLog(@"[ClearAllHook] killed %@ (pid=%d)", name, pid);
            } else {
                NSLog(@"[ClearAllHook] SIGTERM %@ (pid=%d) failed: %s",
                      name, pid, strerror(errno));
            }
        }
        NSLog(@"[ClearAllHook] cleared %lu processes", (unsigned long)killed);
    } @catch (NSException *e) {
        NSLog(@"[ClearAllHook] clear_all threw: %@", e);
    }
}

// ----------------------------------------------------------------------------
// Insert a UIButton into the app switcher view controller we just loaded.
// ----------------------------------------------------------------------------
static void cah_inject_button(UIViewController *switcherVC) {
    @try {
        UIView *v = switcherVC.view;
        if (!v) return;
        // Idempotency — don't add a second button on a reload.
        if ([v viewWithTag:0xC1EA4A11]) return;

        UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
        b.tag = 0xC1EA4A11;
        [b setTitle:@"Clear All" forState:UIControlStateNormal];
        [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        b.backgroundColor = [[UIColor systemRedColor] colorWithAlphaComponent:0.9];
        b.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
        b.layer.cornerRadius = 10;
        b.translatesAutoresizingMaskIntoConstraints = NO;
        [b addTarget:nil action:@selector(csh_clearAllPressed:)
             forControlEvents:UIControlEventTouchUpInside];
        [v addSubview:b];

        UILayoutGuide *g = v.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [b.topAnchor      constraintEqualToAnchor:g.topAnchor constant:10],
            [b.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
            [b.heightAnchor   constraintEqualToConstant:36],
            [b.widthAnchor    constraintEqualToConstant:94],
        ]];
    } @catch (NSException *e) {
        NSLog(@"[ClearAllHook] inject_button threw: %@", e);
    }
}

// Install this as an instance method on every candidate switcher class so
// a tap routes back here.
@interface NSObject (CAHClearAll)
- (void)csh_clearAllPressed:(id)sender;
@end
@implementation NSObject (CAHClearAll)
- (void)csh_clearAllPressed:(id)sender {
    cah_perform_clear_all();
}
@end

// ----------------------------------------------------------------------------
// Swizzle viewDidLoad on the switcher view controller(s). The class name
// has drifted across iOS 14/15/16: SBMainSwitcherViewController,
// SBAppSwitcherViewController, SBFluidSwitcherViewController. We try each
// and hook the first one that resolves.
// ----------------------------------------------------------------------------
static NSArray<NSString *> *cah_switcher_classes(void) {
    return @[
        @"SBFluidSwitcherViewController",
        @"SBMainSwitcherViewController",
        @"SBAppSwitcherController",
        @"SBAppSwitcherViewController",
    ];
}

typedef void (*viewDidLoad_t)(id self, SEL _cmd);
static viewDidLoad_t cah_orig_viewDidLoad = NULL;

static void cah_hooked_viewDidLoad(id self, SEL _cmd) {
    if (cah_orig_viewDidLoad) cah_orig_viewDidLoad(self, _cmd);
    cah_inject_button(self);
}

__attribute__((constructor))
static void cah_init(void) {
    @try {
        for (NSString *name in cah_switcher_classes()) {
            Class c = NSClassFromString(name);
            if (!c) continue;
            Method m = class_getInstanceMethod(c, @selector(viewDidLoad));
            if (!m) continue;
            cah_orig_viewDidLoad = (viewDidLoad_t)method_getImplementation(m);
            method_setImplementation(m, (IMP)cah_hooked_viewDidLoad);
            NSLog(@"[ClearAllHook] hooked -[%@ viewDidLoad]", name);
            return;
        }
        NSLog(@"[ClearAllHook] no switcher candidate matched");
    } @catch (NSException *e) {
        NSLog(@"[ClearAllHook] init threw: %@ — SpringBoard untouched", e);
    }
}
