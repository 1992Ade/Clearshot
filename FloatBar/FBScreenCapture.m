#import "FBScreenCapture.h"
#import <QuartzCore/QuartzCore.h>
#import <mach/mach.h>
#import <dlfcn.h>

// IOSurface forward declarations (headers not shipped by theos/sdks)
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

@interface UIScreen (Private)
- (id)_snapshotWithRect:(CGRect)rect afterScreenUpdates:(BOOL)after;
@end

@implementation FBScreenCapture

+ (UIImage *)captureFullScreenBypassingSecureFlag {
    UIImage *img = [self captureViaCARenderServer];
    if (img) return img;
    img = [self captureViaPrivateUIScreen];
    if (img) return img;
    return [self captureViaPublicRendering];
}

+ (UIImage *)captureViaCARenderServer {
    void *qc = dlopen("/System/Library/Frameworks/QuartzCore.framework/QuartzCore", RTLD_LAZY);
    if (!qc) return nil;

    kern_return_t (*renderFn)(mach_port_t, CFStringRef, IOSurfaceRef, int32_t, int32_t) =
        dlsym(qc, "CARenderServerRenderDisplay");
    CFStringRef *displayIDPtr = dlsym(qc, "kCARenderServerDisplayIDMain");
    if (!renderFn) return nil;

    CGSize screenSize = [UIScreen mainScreen].bounds.size;
    CGFloat scale = [UIScreen mainScreen].scale;
    size_t width = (size_t)(screenSize.width * scale);
    size_t height = (size_t)(screenSize.height * scale);
    size_t bytesPerRow = width * 4;
    size_t allocSize = height * bytesPerRow;

    NSDictionary *props = @{
        (__bridge id)kIOSurfaceWidth: @(width),
        (__bridge id)kIOSurfaceHeight: @(height),
        (__bridge id)kIOSurfaceBytesPerElement: @(4),
        (__bridge id)kIOSurfaceBytesPerRow: @(bytesPerRow),
        (__bridge id)kIOSurfaceAllocSize: @(allocSize),
        (__bridge id)kIOSurfacePixelFormat: @((unsigned)'BGRA'),
    };
    IOSurfaceRef surface = IOSurfaceCreate((__bridge CFDictionaryRef)props);
    if (!surface) return nil;

    CFStringRef displayID = displayIDPtr ? *displayIDPtr : CFSTR("LCD");
    kern_return_t kr = renderFn(MACH_PORT_NULL, displayID, surface, 0, 0);
    if (kr != KERN_SUCCESS) {
        CFRelease((CFTypeRef)surface);
        return nil;
    }

    IOSurfaceLock(surface, kIOSurfaceLockReadOnly, NULL);
    void *base = IOSurfaceGetBaseAddress(surface);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(base, width, height, 8, bytesPerRow, cs,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
    CGImageRef cg = ctx ? CGBitmapContextCreateImage(ctx) : NULL;
    UIImage *img = cg ? [UIImage imageWithCGImage:cg scale:scale orientation:UIImageOrientationUp] : nil;
    if (cg) CGImageRelease(cg);
    if (ctx) CGContextRelease(ctx);
    CGColorSpaceRelease(cs);
    IOSurfaceUnlock(surface, kIOSurfaceLockReadOnly, NULL);
    CFRelease((CFTypeRef)surface);
    return img;
}

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

    void *buf = NULL;
    [inv getReturnValue:&buf];
    id result = (__bridge id)buf;

    if ([result isKindOfClass:[UIView class]]) {
        UIView *v = (UIView *)result;
        UIGraphicsBeginImageContextWithOptions(v.bounds.size, NO, screen.scale);
        [v drawViewHierarchyInRect:v.bounds afterScreenUpdates:NO];
        UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        return img;
    }
    if ([result isKindOfClass:[UIImage class]]) return (UIImage *)result;
    return nil;
}

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
    UIGraphicsBeginImageContextWithOptions(key.bounds.size, NO, [UIScreen mainScreen].scale);
    [key drawViewHierarchyInRect:key.bounds afterScreenUpdates:NO];
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

@end
