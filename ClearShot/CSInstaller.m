#import "CSInstaller.h"
#import "CSProcessUtils.h"

#import <Photos/Photos.h>
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <sys/stat.h>
#import <sys/sysctl.h>
#import <unistd.h>

// ============================================================================
// IOSurface + CARenderServer forward decls (headers not shipped by the
// theos/sdks copy of iPhoneOS16.5.sdk). The symbols themselves exist in
// IOSurface.framework and QuartzCore.framework on every iOS we support.
// ============================================================================
typedef struct __IOSurface *IOSurfaceRef;
extern const CFStringRef kIOSurfaceWidth;
extern const CFStringRef kIOSurfaceHeight;
extern const CFStringRef kIOSurfaceBytesPerElement;
extern const CFStringRef kIOSurfaceBytesPerRow;
extern const CFStringRef kIOSurfaceAllocSize;
extern const CFStringRef kIOSurfacePixelFormat;
extern IOSurfaceRef IOSurfaceCreate(CFDictionaryRef properties);
extern kern_return_t IOSurfaceLock(IOSurfaceRef, uint32_t, uint32_t *);
extern kern_return_t IOSurfaceUnlock(IOSurfaceRef, uint32_t, uint32_t *);
extern void *IOSurfaceGetBaseAddress(IOSurfaceRef);
#define kIOSurfaceLockReadOnly 0x1

typedef kern_return_t (*RenderDisplayFn)(mach_port_t, CFStringRef, IOSurfaceRef,
                                         int32_t, int32_t);

static RenderDisplayFn cs_resolve_render(void) {
    static RenderDisplayFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
                          RTLD_LAZY);
        if (qc) fn = (RenderDisplayFn)dlsym(qc, "CARenderServerRenderDisplay");
    });
    return fn;
}

static CFStringRef cs_resolve_display_id(void) {
    static CFStringRef did = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
                          RTLD_LAZY);
        if (qc) {
            CFStringRef *p = dlsym(qc, "kCARenderServerDisplayIDMain");
            if (p) did = *p;
        }
        if (!did) did = CFSTR("LCD");
    });
    return did;
}

@interface UIScreen (CSPrivate)
- (id)_snapshotWithRect:(CGRect)rect afterScreenUpdates:(BOOL)after;
@end

@implementation CSInstaller

#pragma mark - Paths

+ (NSString *)systemInstallPath {
    return @"/Library/ControlCenter/Bundles/ClearShotModule.bundle";
}

+ (NSString *)embeddedBundlePath {
    return [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:@"ClearShotModule.bundle"];
}

+ (BOOL)isModuleInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self systemInstallPath]];
}

+ (NSString *)recordSystemInstallPath {
    return @"/Library/ControlCenter/Bundles/ClearShotRecordModule.bundle";
}

+ (NSString *)recordEmbeddedBundlePath {
    return [[[NSBundle mainBundle] bundlePath]
            stringByAppendingPathComponent:@"ClearShotRecordModule.bundle"];
}

+ (BOOL)isRecordModuleInstalled {
    return [[NSFileManager defaultManager] fileExistsAtPath:[self recordSystemInstallPath]];
}

#pragma mark - Install

+ (BOOL)installModuleReturningError:(NSError **)error {
    // 1) Install the Capture module first.
    if (![self installBundleFromPath:[self embeddedBundlePath]
                              toPath:[self systemInstallPath]
                           binaryLeaf:@"ClearShotModule"
                                error:error]) {
        return NO;
    }
    // 2) Then the Record twin. If the embedded Record bundle is missing
    //    (older build without the Record module compiled), we just note it
    //    in NSLog and don't fail the install — Capture alone is still
    //    useful.
    NSString *recSrc = [self recordEmbeddedBundlePath];
    if (![[NSFileManager defaultManager] fileExistsAtPath:recSrc]) {
        NSLog(@"[ClearShot/Installer] Record bundle not in app — skipping (%@)", recSrc);
        return YES;
    }
    NSError *recErr = nil;
    if (![self installBundleFromPath:recSrc
                              toPath:[self recordSystemInstallPath]
                           binaryLeaf:@"ClearShotRecordModule"
                                error:&recErr]) {
        NSLog(@"[ClearShot/Installer] Record install failed: %@ — Capture install stays", recErr);
        // Not fatal. Report via the next diagnostics pull.
    }
    return YES;
}

// Shared body for both bundles so we don't duplicate 90 lines of rootSpawn
// dance. All of the original install error reporting is preserved.
+ (BOOL)installBundleFromPath:(NSString *)src
                         toPath:(NSString *)dst
                     binaryLeaf:(NSString *)binaryLeaf
                          error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];

    // Build a verbose error if the embedded bundle is missing — the user
    // sees exactly what we looked at and what was actually there, instead
    // of a bare "Embedded module not found".
    if (![fm fileExistsAtPath:src]) {
        NSMutableString *detail = [NSMutableString string];
        [detail appendFormat:@"Embedded module not found.\n\nLooked for:\n%@\n\n", src];
        NSString *appRoot = [[NSBundle mainBundle] bundlePath];
        [detail appendFormat:@"Contents of %@:\n", appRoot];
        NSError *lsErr = nil;
        NSArray *entries = [fm contentsOfDirectoryAtPath:appRoot error:&lsErr];
        if (entries) {
            for (NSString *name in entries) {
                [detail appendFormat:@"  • %@\n", name];
            }
        } else {
            [detail appendFormat:@"  (could not list: %@)\n",
             lsErr.localizedDescription];
        }
        if (error) {
            *error = [NSError errorWithDomain:@"ClearShot" code:1
                                     userInfo:@{NSLocalizedDescriptionKey: detail}];
        }
        return NO;
    }

    // Make sure /Library/ControlCenter/Bundles/ exists. If it doesn't, create
    // it via rootSpawn since the parent is root:wheel on a stock iOS 15/16.
    NSString *parent = [dst stringByDeletingLastPathComponent];
    if (![fm fileExistsAtPath:parent]) {
        [CSProcessUtils rootSpawn:@"/bin/mkdir"
                             args:@[@"-p", parent]
                           stdOut:NULL stdErr:NULL];
    }

    // If a previous bundle is there, remove it via rootSpawn too — in-process
    // NSFileManager removeItemAtPath on a root-owned path would fail at
    // euid=501.
    if ([fm fileExistsAtPath:dst]) {
        NSString *rmOut = nil, *rmErr = nil;
        int rrc = [CSProcessUtils rootSpawn:@"/bin/rm"
                                       args:@[@"-rf", dst]
                                     stdOut:&rmOut stdErr:&rmErr];
        if (rrc != 0) {
            if (error) {
                *error = [NSError errorWithDomain:@"ClearShot" code:4 userInfo:@{
                    NSLocalizedDescriptionKey:
                        [NSString stringWithFormat:
                         @"rootSpawn /bin/rm -rf %@ exit=%d\n%@", dst, rrc,
                         rmErr ?: @""]
                }];
            }
            return NO;
        }
    }

    // Shell out to /bin/cp via rootSpawn so the copy ALWAYS lands at uid=0
    // regardless of whether ldid stripped a private entitlement from the
    // parent. In-process NSFileManager would fail on /Library/... if the
    // parent process happens to be at euid=501; rootSpawn forces the child
    // persona to root via posix_spawnattr_set_persona_uid_np.
    NSString *spawnOut = nil, *spawnErr = nil;
    int rc = [CSProcessUtils rootSpawn:@"/bin/cp"
                                  args:@[@"-R", src, dst]
                                stdOut:&spawnOut
                                stdErr:&spawnErr];
    if (rc != 0) {
        NSString *extra = [CSProcessUtils currentProcessIdentitySummary];
        NSString *combined = [NSString stringWithFormat:
                              @"rootSpawn /bin/cp exit=%d\n\nstderr:\n%@\nstdout:\n%@\n\n%@",
                              rc, spawnErr ?: @"", spawnOut ?: @"", extra];
        if (error) {
            *error = [NSError errorWithDomain:@"ClearShot" code:3
                                     userInfo:@{NSLocalizedDescriptionKey: combined}];
        }
        return NO;
    }

    // Fix permissions via rootSpawn too so chmod works even if we are at
    // euid=501.
    [CSProcessUtils rootSpawn:@"/bin/chmod" args:@[@"755", dst]
                       stdOut:NULL stdErr:NULL];
    NSArray *contents = [fm contentsOfDirectoryAtPath:dst error:nil];
    for (NSString *name in contents) {
        NSString *child = [dst stringByAppendingPathComponent:name];
        [CSProcessUtils rootSpawn:@"/bin/chmod" args:@[@"644", child]
                           stdOut:NULL stdErr:NULL];
    }
    NSString *binaryPath = [dst stringByAppendingPathComponent:binaryLeaf];
    if ([fm fileExistsAtPath:binaryPath]) {
        [CSProcessUtils rootSpawn:@"/bin/chmod" args:@[@"755", binaryPath]
                           stdOut:NULL stdErr:NULL];
    }

    return YES;
}

#pragma mark - Respring

+ (void)respring {
    [CSProcessUtils forceRespring];
}

#pragma mark - Capture — CARenderServer

+ (UIImage *)captureViaCARenderServer:(kern_return_t *)outKR {
    RenderDisplayFn render = cs_resolve_render();
    if (!render) {
        NSLog(@"[ClearShot] CARenderServerRenderDisplay symbol not resolved");
        if (outKR) *outKR = KERN_INVALID_ADDRESS;
        return nil;
    }

    CGSize boundsPt = [UIScreen mainScreen].bounds.size;
    CGFloat scale   = [UIScreen mainScreen].scale;
    size_t width    = (size_t)(boundsPt.width  * scale);
    size_t height   = (size_t)(boundsPt.height * scale);
    size_t bpr      = width * 4;
    size_t allocSize = height * bpr;

    NSDictionary *props = @{
        (__bridge id)kIOSurfaceWidth:           @(width),
        (__bridge id)kIOSurfaceHeight:          @(height),
        (__bridge id)kIOSurfaceBytesPerElement: @(4),
        (__bridge id)kIOSurfaceBytesPerRow:     @(bpr),
        (__bridge id)kIOSurfaceAllocSize:       @(allocSize),
        (__bridge id)kIOSurfacePixelFormat:     @((unsigned)'BGRA'),
    };
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (!surface) {
        NSLog(@"[ClearShot] IOSurfaceCreate failed");
        if (outKR) *outKR = KERN_NO_SPACE;
        return nil;
    }

    kern_return_t kr = render(MACH_PORT_NULL, cs_resolve_display_id(), surface, 0, 0);
    if (outKR) *outKR = kr;
    if (kr != KERN_SUCCESS) {
        NSLog(@"[ClearShot] CARenderServerRenderDisplay kr=0x%x (%d)", kr, kr);
        CFRelease((CFTypeRef)surface);
        return nil;
    }

    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    void *data = IOSurfaceGetBaseAddress(surface);

    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(data, width, height, 8, bpr, cs,
                       kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CGImageRef cgImage = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    if (ctx) CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    CFRelease((CFTypeRef)surface);

    if (!cgImage) return nil;
    UIImage *img = [UIImage imageWithCGImage:cgImage scale:scale
                                 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return img;
}

#pragma mark - Capture — private UIScreen fallback

+ (UIImage *)captureViaPrivateUIScreen {
    UIScreen *screen = [UIScreen mainScreen];
    SEL sel = NSSelectorFromString(@"_snapshotWithRect:afterScreenUpdates:");
    if (![screen respondsToSelector:sel]) return nil;

    NSMethodSignature *sig = [screen methodSignatureForSelector:sel];
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    [inv setTarget:screen];
    [inv setSelector:sel];
    CGRect rect = screen.bounds;
    BOOL after = NO;
    [inv setArgument:&rect atIndex:2];
    [inv setArgument:&after atIndex:3];
    [inv invoke];

    void *raw = NULL;
    [inv getReturnValue:&raw];
    id result = (__bridge id)raw;

    if ([result isKindOfClass:[UIImage class]]) {
        return (UIImage *)result;
    }
    if ([result isKindOfClass:[UIView class]]) {
        UIView *v = (UIView *)result;
        UIGraphicsBeginImageContextWithOptions(v.bounds.size, NO, screen.scale);
        [v drawViewHierarchyInRect:v.bounds afterScreenUpdates:NO];
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return img;
    }
    return nil;
}

#pragma mark - Capture — public fallback (does NOT bypass FLAG_SECURE)

+ (UIImage *)captureViaPublicRendering {
    UIWindow *key = nil;
    for (UIScene *s in UIApplication.sharedApplication.connectedScenes) {
        if (![s isKindOfClass:[UIWindowScene class]]) continue;
        for (UIWindow *w in ((UIWindowScene *)s).windows) {
            if (w.isKeyWindow) { key = w; break; }
        }
        if (key) break;
    }
    if (!key) return nil;
    UIGraphicsBeginImageContextWithOptions(key.bounds.size, NO,
                                           [UIScreen mainScreen].scale);
    [key drawViewHierarchyInRect:key.bounds afterScreenUpdates:NO];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

#pragma mark - Capture — public chain

+ (UIImage *)captureCurrentScreenBypassingSecureFlag {
    return [self captureCurrentScreenReportingPath:NULL];
}

+ (UIImage *)captureCurrentScreenReportingPath:(NSString * _Nullable * _Nullable)outPath {
    kern_return_t kr = KERN_SUCCESS;
    UIImage *img = [self captureViaCARenderServer:&kr];
    if (img) {
        if (outPath) *outPath = @"CARenderServer (bypass)";
        return img;
    }

    img = [self captureViaPrivateUIScreen];
    if (img) {
        if (outPath) {
            *outPath = [NSString stringWithFormat:
                        @"UIScreen._snapshot fallback (CARenderServer kr=0x%x — "
                        @"this path does NOT bypass FLAG_SECURE)", kr];
        }
        return img;
    }

    img = [self captureViaPublicRendering];
    if (img) {
        if (outPath) {
            *outPath = [NSString stringWithFormat:
                        @"drawViewHierarchy public fallback (CARenderServer kr=0x%x — "
                        @"this path does NOT bypass FLAG_SECURE)", kr];
        }
        return img;
    }

    if (outPath) {
        *outPath = [NSString stringWithFormat:@"all paths failed (kr=0x%x)", kr];
    }
    return nil;
}

#pragma mark - Photos

+ (void)saveImageToPhotos:(UIImage *)image
               completion:(void (^)(BOOL, NSError *))completion {
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                               handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized &&
            status != PHAuthorizationStatusLimited) {
            if (completion) completion(NO,
                [NSError errorWithDomain:@"ClearShot" code:2
                    userInfo:@{NSLocalizedDescriptionKey: @"Photos permission denied"}]);
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:^(BOOL success, NSError *err) {
            if (completion) completion(success, err);
        }];
    }];
}

#pragma mark - Diagnostic report

+ (NSString *)diagnosticReport {
    NSMutableString *r = [NSMutableString string];
    NSFileManager *fm = [NSFileManager defaultManager];

    [r appendString:@"=== ClearShot Diagnostic ===\n\n"];
    [r appendString:[CSProcessUtils currentProcessIdentitySummary]];
    [r appendString:@"\n"];

    NSString *appRoot = [[NSBundle mainBundle] bundlePath];
    [r appendFormat:@"App bundle:\n%@\n\n", appRoot];

    NSError *lsErr = nil;
    NSArray *entries = [fm contentsOfDirectoryAtPath:appRoot error:&lsErr];
    [r appendString:@"App root contents:\n"];
    if (entries) {
        for (NSString *name in entries) {
            NSString *full = [appRoot stringByAppendingPathComponent:name];
            BOOL isDir = NO;
            [fm fileExistsAtPath:full isDirectory:&isDir];
            [r appendFormat:@"  %@ %@\n", isDir ? @"[d]" : @"   ", name];
        }
    } else {
        [r appendFormat:@"  (ls failed: %@)\n", lsErr.localizedDescription];
    }
    [r appendString:@"\n"];

    NSString *embedded = [self embeddedBundlePath];
    BOOL embExists = [fm fileExistsAtPath:embedded];
    [r appendFormat:@"Embedded bundle: %@\n  %@\n\n",
     embExists ? @"✅ present" : @"❌ MISSING", embedded];

    if (embExists) {
        NSArray *bundleContents = [fm contentsOfDirectoryAtPath:embedded error:nil];
        [r appendString:@"Embedded bundle contents:\n"];
        for (NSString *name in bundleContents) {
            [r appendFormat:@"  • %@\n", name];
        }
        [r appendString:@"\n"];
    }

    BOOL sysInstalled = [self isModuleInstalled];
    [r appendFormat:@"System install: %@\n  %@\n\n",
     sysInstalled ? @"✅ present" : @"❌ not installed",
     [self systemInstallPath]];

    // Can we even open the parent of the system install path?
    BOOL ccParent = [fm fileExistsAtPath:@"/Library/ControlCenter/"];
    BOOL ccBundles = [fm fileExistsAtPath:@"/Library/ControlCenter/Bundles/"];
    [r appendFormat:@"/Library/ControlCenter present: %@\n", ccParent ? @"yes" : @"no"];
    [r appendFormat:@"/Library/ControlCenter/Bundles present: %@\n\n",
     ccBundles ? @"yes" : @"no"];

    // Explicit writability checks on the paths we touch. access(W_OK) is
    // the truth: if the in-process euid can write here, so can NSFileManager;
    // if not, we need rootSpawn.
    [r appendString:@"Writability (access W_OK) :\n"];
    const char * const probes[] = {
        "/Library/ControlCenter/Bundles/",
        "/Library/LaunchDaemons/",
        "/var/mobile/Library/Preferences/",
        "/var/containers/Shared/SystemGroup/",
        NULL
    };
    for (int i = 0; probes[i]; i++) {
        int ok = access(probes[i], W_OK);
        [r appendFormat:@"  %s → %@\n", probes[i],
         ok == 0 ? @"✅ writable" : @"❌ not writable (rootSpawn used)"];
    }
    [r appendString:@"\n"];

    // CARenderServer symbol resolution.
    RenderDisplayFn fn = cs_resolve_render();
    [r appendFormat:@"CARenderServerRenderDisplay symbol: %@\n",
     fn ? @"✅ resolved" : @"❌ NOT found (QuartzCore dlsym failed)"];

    // A one-shot Test capture result.
    NSString *path = nil;
    UIImage *img = [self captureCurrentScreenReportingPath:&path];
    [r appendFormat:@"Capture attempt: %@\n  path: %@\n",
     img ? @"✅ got an image" : @"❌ no image",
     path ?: @"(none)"];

    return r;
}

// Bridge to TBDiagnosticProvider — the global diagnostics aggregator looks
// for +diagnosticInfo on each section class. We return a slim status
// summary; the big one-shot Test capture of diagnosticReport belongs on an
// explicit tap, not every time someone opens About Device → Diagnostics.
+ (NSString *)diagnosticInfo {
    NSMutableString *r = [NSMutableString string];
    [r appendFormat:@"Module installed in /Library/ControlCenter/Bundles/: %@\n",
     [self isModuleInstalled] ? @"✅ yes" : @"❌ no"];
    RenderDisplayFn fn = cs_resolve_render();
    [r appendFormat:@"CARenderServerRenderDisplay symbol: %@\n",
     fn ? @"✅ resolved" : @"❌ not found"];
    return r;
}

@end
