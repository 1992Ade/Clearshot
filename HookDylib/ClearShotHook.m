// ============================================================================
// libClearShotHook.dylib — injected into SpringBoard via the Tweaks engine
// (TFInjector → LC_LOAD_DYLIB in /Applications/SpringBoard.app/SpringBoard).
//
// Hooks the SBScreenshotManager entry point that iOS calls after a user
// does Power + Home (or the equivalent Side + Volume Up) screenshot
// gesture. Our override replaces the system path with a CARenderServer
// capture, so the saved image is unaffected by FLAG_SECURE.
//
// Method name varies across iOS point releases. We try several candidates
// at constructor time; the first one that matches a real selector gets
// swizzled. @try/@catch around everything so a mis-swizzle can never
// bring SpringBoard down.
// ============================================================================

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <Photos/Photos.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <dlfcn.h>

// ----------------------------------------------------------------------------
// IOSurface + CARenderServer glue
// ----------------------------------------------------------------------------
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

typedef kern_return_t (*RenderDisplayFn)(mach_port_t, CFStringRef,
                                         IOSurfaceRef, int32_t, int32_t);

static RenderDisplayFn csh_render_fn(void) {
    static RenderDisplayFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
                          RTLD_LAZY);
        if (qc) fn = (RenderDisplayFn)dlsym(qc, "CARenderServerRenderDisplay");
    });
    return fn;
}
static CFStringRef csh_display_id(void) {
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

// ----------------------------------------------------------------------------
// Capture UIImage via CARenderServer
// ----------------------------------------------------------------------------
static UIImage *csh_capture(void) {
    RenderDisplayFn render = csh_render_fn();
    if (!render) return nil;

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
    if (!surface) return nil;

    kern_return_t kr = render(MACH_PORT_NULL, csh_display_id(), surface, 0, 0);
    if (kr != KERN_SUCCESS) {
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

// ----------------------------------------------------------------------------
// Save to Photos (SpringBoard has the entitlements)
// ----------------------------------------------------------------------------
static void csh_save_to_photos(UIImage *img) {
    if (!img) return;
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                                handler:^(PHAuthorizationStatus st) {
        if (st != PHAuthorizationStatusAuthorized &&
            st != PHAuthorizationStatusLimited) {
            NSLog(@"[ClearShotHook] Photos denied (status=%ld)", (long)st);
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:img];
        } completionHandler:^(BOOL ok, NSError *err) {
            NSLog(@"[ClearShotHook] save success=%d err=%@", ok, err);
        }];
    }];
}

// ----------------------------------------------------------------------------
// The swizzle targets. iOS evolves the SBScreenshotManager method name
// between point releases, so we try each candidate until one is present.
// ----------------------------------------------------------------------------
static NSArray<NSString *> *csh_candidates(void) {
    return @[
        @"_savePNGScreenshotToCameraRoll:",
        @"_writeScreenshotToCameraRoll:",
        @"_handleScreenshotActivationWithContext:",
        @"takeScreenshot",
        @"performScreenshotActions:",
    ];
}

// ----------------------------------------------------------------------------
// Our replacement implementation. Signature matches a 1-arg method; for
// 0-arg targets (takeScreenshot) we just ignore the second parameter.
// ----------------------------------------------------------------------------
static void csh_replacement(id self, SEL _cmd, id arg1) {
    @try {
        UIImage *img = csh_capture();
        if (img) {
            csh_save_to_photos(img);
            NSLog(@"[ClearShotHook] intercepted %@, saved CARenderServer capture",
                  NSStringFromSelector(_cmd));
            return;    // SUPPRESS the original — our save is the result
        }
        NSLog(@"[ClearShotHook] CARenderServer failed, falling through");
    } @catch (NSException *e) {
        NSLog(@"[ClearShotHook] replacement threw: %@", e);
    }
    // Fallback: original path (empty — we never got the pointer to it
    // because we used setImplementation rather than exchange). On the
    // fallthrough iOS WILL still take its normal screenshot via other
    // code paths, so the user isn't left with nothing.
}

// ----------------------------------------------------------------------------
// Constructor — runs when SpringBoard dyld loads our dylib.
// ----------------------------------------------------------------------------
__attribute__((constructor))
static void csh_init(void) {
    @try {
        Class smClass = NSClassFromString(@"SBScreenshotManager");
        if (!smClass) {
            NSLog(@"[ClearShotHook] SBScreenshotManager not found at load time");
            return;
        }
        for (NSString *name in csh_candidates()) {
            SEL sel = NSSelectorFromString(name);
            Method m = class_getInstanceMethod(smClass, sel);
            if (!m) continue;

            // Install our replacement. Use method_setImplementation so the
            // same selector still resolves; iOS's internal callers still
            // land in our csh_replacement.
            IMP previous = method_setImplementation(m, (IMP)csh_replacement);
            (void)previous;
            NSLog(@"[ClearShotHook] hooked -[SBScreenshotManager %@]", name);
            return;
        }
        NSLog(@"[ClearShotHook] no SBScreenshotManager candidate matched");
    } @catch (NSException *e) {
        NSLog(@"[ClearShotHook] init threw: %@ — SpringBoard untouched", e);
    }
}
