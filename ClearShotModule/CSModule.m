#import "CSModule.h"
#import <QuartzCore/QuartzCore.h>
#import <Photos/Photos.h>
#import <mach/mach.h>
#import <dlfcn.h>

// ============================================================================
// The Control Center module. Runs inside SpringBoard on iOS 11+ so it
// inherits SpringBoard's (ample) entitlements — CARenderServerRenderDisplay
// is reachable from here by design.
//
// SpringBoard loads modules from /Library/ControlCenter/Bundles/. The
// wrapper app copies ClearShotModule.bundle there on first launch, then
// restarts SpringBoard so it picks us up.
//
// The capture chain here mirrors CSInstaller's three-step fallback. In
// practice step 1 is what we want (bypasses FLAG_SECURE); steps 2 and 3
// exist so that if CARenderServer errors out on a given build or iOS point
// release we still save SOMETHING to Photos instead of silently failing
// and flashing red.
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

typedef kern_return_t (*RenderDisplayFn)(mach_port_t, CFStringRef,
                                         IOSurfaceRef, int32_t, int32_t);

static RenderDisplayFn cs_render(void) {
    static RenderDisplayFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore",
                          RTLD_LAZY);
        if (qc) fn = (RenderDisplayFn)dlsym(qc, "CARenderServerRenderDisplay");
    });
    return fn;
}

static CFStringRef cs_display_id(void) {
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

@interface CCUIToggleModule (Private)
- (void)setLatching:(BOOL)latching;
@end

@interface UIScreen (CSPrivate)
- (id)_snapshotWithRect:(CGRect)rect afterScreenUpdates:(BOOL)after;
@end

@implementation CSModule

- (instancetype)init {
    if ((self = [super init])) {
        if ([self respondsToSelector:@selector(setLatching:)]) {
            [self setLatching:NO];
        }
    }
    return self;
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    if (selected) {
        [self takeShot];
        dispatch_async(dispatch_get_main_queue(), ^{
            [super setSelected:NO];
        });
    }
}

#pragma mark - Capture chain

- (void)takeShot {
    NSLog(@"[ClearShot] module tap → attempting capture");
    UIImage *img = [self captureViaCARenderServer];
    if (img) {
        NSLog(@"[ClearShot] CARenderServer OK");
        [self saveToPhotos:img];
        return;
    }
    img = [self captureViaPrivateUIScreen];
    if (img) {
        NSLog(@"[ClearShot] fallback: UIScreen._snapshot (no FLAG_SECURE bypass)");
        [self saveToPhotos:img];
        return;
    }
    img = [self captureViaPublicRendering];
    if (img) {
        NSLog(@"[ClearShot] fallback: drawViewHierarchy (no FLAG_SECURE bypass)");
        [self saveToPhotos:img];
        return;
    }
    NSLog(@"[ClearShot] all capture paths failed");
    [self flashIcon:[UIColor systemRedColor]];
}

- (UIImage *)captureViaCARenderServer {
    RenderDisplayFn render = cs_render();
    if (!render) {
        NSLog(@"[ClearShot] CARenderServerRenderDisplay symbol not resolved");
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
        return nil;
    }

    kern_return_t kr = render(MACH_PORT_NULL, cs_display_id(), surface, 0, 0);
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
    UIImage *img = [UIImage imageWithCGImage:cgImage
                                       scale:scale
                                 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return img;
}

- (UIImage *)captureViaPrivateUIScreen {
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

- (UIImage *)captureViaPublicRendering {
    // From inside SpringBoard, the "key window" is whatever SpringBoard
    // last drew — which if we were tapped from Control Center is Control
    // Center itself, not the app behind it. This path is only useful as a
    // last resort and specifically does NOT bypass FLAG_SECURE.
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

#pragma mark - Photos

- (void)saveToPhotos:(UIImage *)image {
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly
                                               handler:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized &&
            status != PHAuthorizationStatusLimited) {
            NSLog(@"[ClearShot] Photos permission denied by SpringBoard (status=%ld)",
                  (long)status);
            [self flashIcon:[UIColor systemOrangeColor]];
            return;
        }
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:image];
        } completionHandler:^(BOOL success, NSError *err) {
            NSLog(@"[ClearShot] Photos save success=%d err=%@", success, err);
            dispatch_async(dispatch_get_main_queue(), ^{
                [self flashIcon:(success ? [UIColor systemGreenColor]
                                         : [UIColor systemRedColor])];
            });
        }];
    }];
}

#pragma mark - Visual feedback

- (void)flashIcon:(UIColor *)color {
    UIView *v = self.view;
    if (!v) return;
    UIColor *orig = v.backgroundColor;
    [UIView animateWithDuration:0.12 animations:^{
        v.backgroundColor = color;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0.15 options:0 animations:^{
            v.backgroundColor = orig;
        } completion:nil];
    }];
}

@end
