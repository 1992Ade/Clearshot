#import "TFInjector.h"
#import "TFMachO.h"
#import "TFCodesign.h"
#import "CSProcessUtils.h"

// ============================================================================
// LSApplicationWorkspace private surface we need to resolve app dirs.
// ============================================================================
@interface LSApplicationProxy : NSObject
@property (readonly) NSString *bundleIdentifier;
@property (readonly) NSURL *bundleURL;
@property (readonly) NSString *bundleExecutable;
+ (instancetype)applicationProxyForIdentifier:(NSString *)bid;
@end
@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (BOOL)registerApplicationDictionary:(NSDictionary *)dict;
- (BOOL)registerBundleWithInfo:(NSDictionary *)info options:(NSDictionary *)opts
                           type:(NSString *)type
                       progress:(id)progress;
@end

// NSUserDefaults registry of our injections.
static NSString * const kInjectedRegistryKey = @"TBTweaksInjectedDylibs";

// ============================================================================
// Helpers
// ============================================================================

static NSError *TIErr(NSString *msg) {
    return [NSError errorWithDomain:@"TFInjector" code:1
                            userInfo:@{NSLocalizedDescriptionKey: msg ?: @"error"}];
}

// Our own registry (what we injected) merged with the live Mach-O LC_LOAD_DYLIB
// entries under Frameworks/. We treat a load command pointing at
// `@executable_path/Frameworks/<leaf>` as "injected" regardless of whether
// WE wrote it or an external tool did.
static NSMutableDictionary *tfReadRegistry(void) {
    NSDictionary *d = [[NSUserDefaults standardUserDefaults]
                        dictionaryForKey:kInjectedRegistryKey];
    return d ? [d mutableCopy] : [NSMutableDictionary dictionary];
}
static void tfWriteRegistry(NSDictionary *d) {
    [[NSUserDefaults standardUserDefaults] setObject:d forKey:kInjectedRegistryKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

@implementation TFInjector

#pragma mark - Public

+ (NSString *)appDirForBundleId:(NSString *)bundleId {
    Class proxyC = NSClassFromString(@"LSApplicationProxy");
    if (!proxyC) return nil;
    LSApplicationProxy *p = [proxyC applicationProxyForIdentifier:bundleId];
    return p.bundleURL.path;
}

+ (NSArray<NSString *> *)injectedDylibLeafsForAppID:(NSString *)bundleId {
    NSString *appDir = [self appDirForBundleId:bundleId];
    if (!appDir) return @[];

    NSString *execName = [self executableNameInApp:appDir];
    NSString *execPath = [appDir stringByAppendingPathComponent:execName];
    NSArray *refs = [TFMachO dylibReferencesInMachOAtPath:execPath error:nil];

    NSMutableSet *leafs = [NSMutableSet set];
    for (NSString *ref in refs) {
        // Only user-injected dylibs land under Frameworks/. System dylibs
        // start with /System, /usr, @rpath, etc.
        if ([ref containsString:@"@executable_path/Frameworks/"]) {
            [leafs addObject:[ref lastPathComponent]];
        } else if ([ref containsString:@"@rpath/"]) {
            // might be ours too if we wrote an @rpath form; include leaf
            // only when it also exists under Frameworks/ (= we put it there)
            NSString *leaf = [ref lastPathComponent];
            NSString *fwPath = [appDir stringByAppendingPathComponent:
                                [@"Frameworks/" stringByAppendingString:leaf]];
            if ([[NSFileManager defaultManager] fileExistsAtPath:fwPath]) {
                [leafs addObject:leaf];
            }
        }
    }
    return [leafs allObjects];
}

+ (NSString *)injectDylibAtPath:(NSString *)src
                      intoAppID:(NSString *)bundleId
                          error:(NSError **)err {
    NSString *appDir = [self appDirForBundleId:bundleId];
    if (!appDir) {
        if (err) *err = TIErr(@"Target app's bundle URL couldn't be resolved.");
        return nil;
    }
    NSString *execName = [self executableNameInApp:appDir];
    if (!execName) {
        if (err) *err = TIErr(@"Target app has no CFBundleExecutable in Info.plist.");
        return nil;
    }
    NSString *execPath = [appDir stringByAppendingPathComponent:execName];
    NSString *frameworksDir = [appDir stringByAppendingPathComponent:@"Frameworks"];

    NSFileManager *fm = [NSFileManager defaultManager];
    [fm createDirectoryAtPath:frameworksDir withIntermediateDirectories:YES
                    attributes:nil error:nil];

    NSString *leafname = [src lastPathComponent];
    NSString *dst = [frameworksDir stringByAppendingPathComponent:leafname];
    NSError *cpErr = nil;
    // Remove any existing copy so the destination isn't a stale one.
    [fm removeItemAtPath:dst error:nil];
    if (![fm copyItemAtPath:src toPath:dst error:&cpErr]) {
        if (err) *err = cpErr ?: TIErr(@"Couldn't copy dylib into app bundle.");
        return nil;
    }

    // Patch the Mach-O to add the LC_LOAD_DYLIB.
    NSString *loadName = [@"@executable_path/Frameworks/"
                           stringByAppendingString:leafname];
    NSError *patchErr = nil;
    if (![TFMachO addDylibReference:loadName
                      toMachOAtPath:execPath
                              error:&patchErr]) {
        [fm removeItemAtPath:dst error:nil];
        if (err) *err = patchErr;
        return nil;
    }

    // Re-sign the executable so iOS will still launch it.
    NSError *signErr = nil;
    if (![TFCodesign signMachOAtPath:execPath entitlementsPath:nil error:&signErr]) {
        // Try to undo the patch so we don't leave a broken app on disk.
        [TFMachO removeDylibReference:loadName
                     fromMachOAtPath:execPath
                               error:nil];
        [fm removeItemAtPath:dst error:nil];
        if (err) *err = signErr;
        return nil;
    }

    // Record in our registry.
    NSMutableDictionary *reg = tfReadRegistry();
    NSMutableArray *list = [(reg[bundleId] ?: @[]) mutableCopy];
    if (![list containsObject:leafname]) [list addObject:leafname];
    reg[bundleId] = list;
    tfWriteRegistry(reg);

    [self kickLaunchServicesForApp:bundleId];
    return leafname;
}

+ (BOOL)ejectDylibLeaf:(NSString *)leafname
             fromAppID:(NSString *)bundleId
                 error:(NSError **)err {
    NSString *appDir = [self appDirForBundleId:bundleId];
    if (!appDir) {
        if (err) *err = TIErr(@"Target app's bundle URL couldn't be resolved.");
        return NO;
    }
    NSString *execName = [self executableNameInApp:appDir];
    NSString *execPath = [appDir stringByAppendingPathComponent:execName];
    NSString *frameworksDir = [appDir stringByAppendingPathComponent:@"Frameworks"];
    NSString *dylibPath = [frameworksDir stringByAppendingPathComponent:leafname];

    NSString *loadName = [@"@executable_path/Frameworks/"
                           stringByAppendingString:leafname];

    NSError *rmErr = nil;
    NSUInteger n = [TFMachO removeDylibReference:loadName
                                fromMachOAtPath:execPath
                                           error:&rmErr];
    if (rmErr) {
        if (err) *err = rmErr;
        return NO;
    }
    if (n == 0) {
        // Maybe it's stored as @rpath/<leaf> instead.
        NSString *rpathForm = [@"@rpath/" stringByAppendingString:leafname];
        n = [TFMachO removeDylibReference:rpathForm
                         fromMachOAtPath:execPath
                                   error:&rmErr];
    }

    // Always try to delete the file and re-sign — even if we removed 0 load
    // commands, cleanup is still a good idea in case the user injected via
    // another tool and we just need to remove the file.
    [[NSFileManager defaultManager] removeItemAtPath:dylibPath error:nil];
    NSError *signErr = nil;
    if (![TFCodesign signMachOAtPath:execPath entitlementsPath:nil error:&signErr]) {
        if (err) *err = signErr;
        return NO;
    }

    NSMutableDictionary *reg = tfReadRegistry();
    NSMutableArray *list = [(reg[bundleId] ?: @[]) mutableCopy];
    [list removeObject:leafname];
    if (list.count) reg[bundleId] = list; else [reg removeObjectForKey:bundleId];
    tfWriteRegistry(reg);

    [self kickLaunchServicesForApp:bundleId];
    return YES;
}

#pragma mark - Helpers

+ (NSString *)executableNameInApp:(NSString *)appDir {
    NSString *plist = [appDir stringByAppendingPathComponent:@"Info.plist"];
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:plist];
    return info[@"CFBundleExecutable"];
}

// Nudge Launch Services so SpringBoard re-reads the modified app bundle.
// Different iOS versions ship different reregister entry points; we try the
// documented one first and fall back to killall SpringBoard-adjacents via
// rootSpawn uicache if that exists, with every failure swallowed.
+ (void)kickLaunchServicesForApp:(NSString *)bundleId {
    @try {
        Class wsC = NSClassFromString(@"LSApplicationWorkspace");
        if (wsC) {
            id ws = [wsC performSelector:@selector(defaultWorkspace)];
            if ([ws respondsToSelector:@selector(registerApplicationDictionary:)]) {
                [ws registerApplicationDictionary:@{ @"ApplicationType": @"User",
                                                     @"CFBundleIdentifier": bundleId }];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[TFInjector] LS reregister threw: %@", e);
    }
    // Best-effort uicache (Procursus / TrollStore tooling); not fatal.
    [CSProcessUtils rootSpawn:@"/usr/bin/uicache" args:@[@"-p", [self appDirForBundleId:bundleId] ?: @""]
                       stdOut:NULL stdErr:NULL];
}

@end
