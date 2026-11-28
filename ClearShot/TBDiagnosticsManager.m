#import "TBDiagnosticsManager.h"
#import <UIKit/UIKit.h>
#import <sys/sysctl.h>
#import <sys/utsname.h>
#import <sys/stat.h>
#import <unistd.h>
#import <stdio.h>

// Section classes that currently export diagnostics. A class that doesn't
// conform to TBDiagnosticProvider is simply skipped — this list can grow
// faster than every section catches up.
#import "CSInstaller.h"              // ClearShot — already has diagnosticReport
// Other sections implement the protocol as a category in their own .m.

@implementation TBDiagnosticsManager

+ (NSArray<Class> *)diagnosticProviders {
    return @[
        NSClassFromString(@"ABMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"RSMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"BCMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"CSInstaller")                ?: (Class)NSNull.class,
        NSClassFromString(@"RMMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"ARMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"WFMainViewController")       ?: (Class)NSNull.class,
        NSClassFromString(@"TBSupervisionManager")       ?: (Class)NSNull.class,
    ];
}

// ============================================================================
// Header: who are we, what are we running on
// ============================================================================

+ (NSString *)processIdentityBlock {
    NSMutableString *s = [NSMutableString string];
    [s appendFormat:@"pid=%d  uid=%d  euid=%d  gid=%d  egid=%d\n",
     getpid(), getuid(), geteuid(), getgid(), getegid()];

    UIDevice *d = [UIDevice currentDevice];
    struct utsname sys; uname(&sys);
    [s appendFormat:@"device: %@ · iOS %@ · machine %s\n",
     d.model, d.systemVersion, sys.machine];

    NSString *exec = [[NSBundle mainBundle] executablePath];
    [s appendFormat:@"exec: %@\n", exec];

    NSString *bundle = [[NSBundle mainBundle] bundleIdentifier];
    NSString *version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    NSString *build   = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
    [s appendFormat:@"bundle: %@ · version %@ (build %@)\n",
     bundle ?: @"(nil)", version ?: @"?", build ?: @"?"];

    if (geteuid() == 0) {
        [s appendString:@"\n✅ Running at euid=0 — all root-owned paths writable.\n"];
    } else {
        [s appendFormat:@"\n⚠️ Not running as root (euid=%d). setuid(0) likely failed at main().\n",
         geteuid()];
    }
    return s;
}

// ============================================================================
// Writability checks for every root-owned path TrollBox writes to
// ============================================================================

+ (NSString *)writabilityBlock {
    NSArray *paths = @[
        @"/Library/ControlCenter/Bundles",                    // ClearShot
        @"/Library/LaunchDaemons",                             // ResSetter boot daemon
        @"/var/mobile/Library/Preferences",                    // ResSetter gfx plist
        @"/var/Managed Preferences/mobile",                    // Don't-Lock-After-Respring
        @"/var/mobile/Library/Caches/MappedImageCache/Persistent", // Badge Color
        @"/var/containers/Shared/SystemGroup",                 // Supervise
        @"/var/mobile/Library/Logs/CrashReporter/Analytics",   // Reclaim Space
        @"/var/mobile/Library/Logs/CrashReporter",             // Reclaim Space
        @"/var/mobile/Library/Logs/AppleSupport",              // Reclaim Space
        @"/var/log",                                           // Reclaim Space system logs
        @"/var/mobile/Containers/Data/Application",            // Reclaim Space orphans
        @"/var/mobile/Library/Caches",                         // Reclaim Space system caches
    ];
    NSMutableString *s = [NSMutableString string];
    for (NSString *p in paths) {
        const char *cp = [p fileSystemRepresentation];
        BOOL exists = (access(cp, F_OK) == 0);
        BOOL writable = (access(cp, W_OK) == 0);
        NSString *marker = !exists ? @"— "
                         : writable ? @"✅"
                                    : @"❌";
        [s appendFormat:@"  %@ %@\n", marker, p];
    }
    return s;
}

// ============================================================================
// Per-section diagnostics via TBDiagnosticProvider conformance
// ============================================================================

+ (NSString *)sectionBlock {
    NSMutableString *s = [NSMutableString string];
    for (Class c in [self diagnosticProviders]) {
        if (c == (Class)NSNull.class || !c) continue;
        if (![c respondsToSelector:@selector(diagnosticInfo)]) continue;
        NSString *info = nil;
        @try {
            info = [c performSelector:@selector(diagnosticInfo)];
        } @catch (NSException *e) {
            info = [NSString stringWithFormat:@"⚠️ %@ threw while gathering diagnostics: %@",
                    NSStringFromClass(c), e];
        }
        if (info.length) {
            [s appendFormat:@"\n── %@ ──\n%@\n", NSStringFromClass(c), info];
        }
    }
    return s;
}

// ============================================================================
// Full report assembly
// ============================================================================

+ (NSString *)fullReport {
    NSMutableString *r = [NSMutableString string];

    [r appendString:@"═══════════ TrollBox diagnostic report ═══════════\n\n"];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    [r appendFormat:@"Generated: %@\n\n", [fmt stringFromDate:[NSDate date]]];

    [r appendString:@"─── Process identity ───\n"];
    [r appendString:[self processIdentityBlock]];

    [r appendString:@"\n─── Writability checks ───\n"];
    [r appendString:[self writabilityBlock]];

    [r appendString:@"\n─── Section diagnostics ───\n"];
    [r appendString:[self sectionBlock]];

    [r appendString:@"\n═══════════ end of report ═══════════\n"];
    return r;
}

@end
