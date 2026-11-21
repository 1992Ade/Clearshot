#import "FBEventSynthesizer.h"
#import <UIKit/UIKit.h>
#import <mach/mach_time.h>
#import <dlfcn.h>

// IOHIDEvent symbols live inside IOKit but aren't exported; resolve at runtime.
typedef uint32_t IOHIDDigitizerEventMask;
typedef CFTypeRef IOHIDEventRef;

typedef IOHIDEventRef (*CreateFingerEventFn)(
    CFAllocatorRef, uint64_t, uint32_t, uint32_t,
    IOHIDDigitizerEventMask,
    float, float, float, float, float,
    Boolean, Boolean, uint32_t);

typedef IOHIDEventRef (*CreateKeyboardEventFn)(
    CFAllocatorRef, uint64_t, uint32_t usagePage, uint32_t usage,
    Boolean isKeyDown, uint32_t options);

typedef void (*BKSHIDPostFn)(IOHIDEventRef);

#pragma mark - resolvers

static CreateFingerEventFn resolve_finger(void) {
    static CreateFingerEventFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *paths[] = {
            "/System/Library/Frameworks/IOKit.framework/IOKit",
            "/System/Library/PrivateFrameworks/IOKit.framework/IOKit",
            NULL
        };
        for (int i = 0; paths[i] && !fn; i++) {
            void *h = dlopen(paths[i], RTLD_LAZY);
            if (h) fn = (CreateFingerEventFn)dlsym(h, "IOHIDEventCreateDigitizerFingerEvent");
        }
        if (!fn) fn = (CreateFingerEventFn)dlsym(RTLD_DEFAULT, "IOHIDEventCreateDigitizerFingerEvent");
    });
    return fn;
}

static CreateKeyboardEventFn resolve_keyboard(void) {
    static CreateKeyboardEventFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *paths[] = {
            "/System/Library/Frameworks/IOKit.framework/IOKit",
            "/System/Library/PrivateFrameworks/IOKit.framework/IOKit",
            NULL
        };
        for (int i = 0; paths[i] && !fn; i++) {
            void *h = dlopen(paths[i], RTLD_LAZY);
            if (h) fn = (CreateKeyboardEventFn)dlsym(h, "IOHIDEventCreateKeyboardEvent");
        }
        if (!fn) fn = (CreateKeyboardEventFn)dlsym(RTLD_DEFAULT, "IOHIDEventCreateKeyboardEvent");
    });
    return fn;
}

static BKSHIDPostFn resolve_post(void) {
    static BKSHIDPostFn fn = NULL;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/BackBoardServices.framework/BackBoardServices", RTLD_LAZY);
        if (h) {
            fn = (BKSHIDPostFn)dlsym(h, "BKSHIDEventPostFast");
            if (!fn) fn = (BKSHIDPostFn)dlsym(h, "BKSHIDEventPost");
        }
    });
    return fn;
}

#pragma mark - helpers

static void post_touch(CGPoint p, Boolean down) {
    CreateFingerEventFn create = resolve_finger();
    BKSHIDPostFn post = resolve_post();
    if (!create || !post) return;

    IOHIDDigitizerEventMask mask = 1 | 2; // touch + position
    IOHIDEventRef ev = create(
        kCFAllocatorDefault, mach_absolute_time(),
        1, 2, mask,
        (float)p.x, (float)p.y, 0.0f,
        down ? 1.0f : 0.0f, 0.0f,
        down, down, 0);
    if (!ev) return;
    post(ev);
    CFRelease(ev);
}

#pragma mark - public

@implementation FBEventSynthesizer

+ (BOOL)synthesizeHomeButtonPress {
    CreateKeyboardEventFn create = resolve_keyboard();
    BKSHIDPostFn post = resolve_post();
    if (!create || !post) return NO;

    // Consumer page (0x0C), Menu usage (0x40) → SpringBoard treats this as Home.
    const uint32_t kHIDPage_Consumer = 0x0C;
    const uint32_t kHIDUsage_Csmr_Menu = 0x40;

    IOHIDEventRef down = create(kCFAllocatorDefault, mach_absolute_time(),
                                kHIDPage_Consumer, kHIDUsage_Csmr_Menu, true, 0);
    if (!down) return NO;
    post(down);
    CFRelease(down);

    [NSThread sleepForTimeInterval:0.08];

    IOHIDEventRef up = create(kCFAllocatorDefault, mach_absolute_time(),
                              kHIDPage_Consumer, kHIDUsage_Csmr_Menu, false, 0);
    if (!up) return YES;
    post(up);
    CFRelease(up);
    return YES;
}

+ (BOOL)synthesizeBackEdgeSwipe {
    if (!resolve_finger() || !resolve_post()) return NO;

    CGRect sb = [UIScreen mainScreen].bounds;
    CGFloat y = sb.size.height / 2.0;
    CGFloat startX = 2.0;
    CGFloat endX = sb.size.width * 0.55;
    int steps = 25;

    post_touch(CGPointMake(startX, y), YES);
    [NSThread sleepForTimeInterval:0.02];
    for (int i = 1; i <= steps; i++) {
        CGFloat x = startX + (endX - startX) * ((CGFloat)i / steps);
        post_touch(CGPointMake(x, y), YES);
        [NSThread sleepForTimeInterval:0.012];
    }
    post_touch(CGPointMake(endX, y), NO);
    return YES;
}

+ (BOOL)synthesizeAppSwitcherSwipe {
    if (!resolve_finger() || !resolve_post()) return NO;

    CGRect sb = [UIScreen mainScreen].bounds;
    CGFloat x = sb.size.width / 2.0;
    CGFloat startY = sb.size.height - 2.0;
    CGFloat endY = sb.size.height * 0.5;
    int steps = 30;

    post_touch(CGPointMake(x, startY), YES);
    [NSThread sleepForTimeInterval:0.02];
    for (int i = 1; i <= steps; i++) {
        CGFloat yy = startY + (endY - startY) * ((CGFloat)i / steps);
        post_touch(CGPointMake(x, yy), YES);
        [NSThread sleepForTimeInterval:0.015];
    }
    [NSThread sleepForTimeInterval:0.4];
    post_touch(CGPointMake(x, endY), NO);
    return YES;
}

@end
