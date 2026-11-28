#import "TFCodesign.h"
#import "CSProcessUtils.h"

// Known ldid locations across the TrollStore / jailbreak / Procursus
// ecosystem. First match wins; the list is ordered newest → oldest.
static NSArray<NSString *> *tfKnownLdidPaths(void) {
    return @[
        @"/var/jb/usr/bin/ldid",                         // Dopamine rootless jb
        @"/var/jb/opt/procursus/usr/bin/ldid",           // older Procursus
        @"/usr/local/bin/ldid",                          // TrollFools custom install
        @"/usr/bin/ldid",                                // classic Procursus
        @"/Applications/TrollStore.app/ldid",            // TrollStore bundled
        @"/var/containers/Bundle/Application/TrollStore.app/ldid",
    ];
}

@implementation TFCodesign

+ (NSString *)availableLdidPath {
    static dispatch_once_t once;
    static NSString *found = nil;
    dispatch_once(&once, ^{
        NSFileManager *fm = [NSFileManager defaultManager];
        for (NSString *p in tfKnownLdidPaths()) {
            if ([fm isExecutableFileAtPath:p]) { found = p; break; }
        }
        if (!found) NSLog(@"[TFCodesign] no ldid found at known paths");
    });
    return found;
}

+ (BOOL)signMachOAtPath:(NSString *)path
       entitlementsPath:(NSString *)entitlementsPath
                  error:(NSError **)err {
    NSString *ldid = [self availableLdidPath];
    if (!ldid) {
        if (err) *err = [NSError errorWithDomain:@"TFCodesign" code:1
                                         userInfo:@{NSLocalizedDescriptionKey:
            @"ldid not found. Install it via sbreload / Procursus, or copy "
            @"the one bundled with TrollFools to /usr/local/bin/ldid."}];
        return NO;
    }

    NSMutableArray *args = [NSMutableArray array];
    if (entitlementsPath.length) {
        [args addObject:[@"-S" stringByAppendingString:entitlementsPath]];
    } else {
        [args addObject:@"-S"];
    }
    [args addObject:path];

    NSString *out = nil, *errStr = nil;
    int rc = [CSProcessUtils rootSpawn:ldid args:args stdOut:&out stdErr:&errStr];
    if (rc != 0) {
        if (err) *err = [NSError errorWithDomain:@"TFCodesign" code:2
                                         userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"ldid rc=%d%@%@",
             rc,
             errStr.length ? [@"\nstderr: " stringByAppendingString:errStr] : @"",
             out.length    ? [@"\nstdout: " stringByAppendingString:out]    : @""]}];
        return NO;
    }
    return YES;
}

@end
