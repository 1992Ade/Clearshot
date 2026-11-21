#import "FBActions.h"
#import "FBEventSynthesizer.h"
#import "FBScreenCapture.h"
#import <Photos/Photos.h>
#import <AudioToolbox/AudioToolbox.h>
#import <QuartzCore/QuartzCore.h>

@implementation FBActions

+ (void)performAction:(FBButtonType)type host:(id<FBActionHost>)host {
    switch (type) {
        case FBButtonTypeHome:
            [self performOnBackground:^{
                [FBEventSynthesizer synthesizeHomeButtonPress];
            }];
            break;
        case FBButtonTypeBack:
            [self performOnBackground:^{
                [FBEventSynthesizer synthesizeBackEdgeSwipe];
            }];
            break;
        case FBButtonTypeAppSwitcher:
            [self performOnBackground:^{
                [FBEventSynthesizer synthesizeAppSwitcherSwipe];
            }];
            break;
        case FBButtonTypeCapture:
            [self runCaptureWithHost:host];
            break;
    }
}

+ (void)performOnBackground:(void (^)(void))block {
    // Gesture synthesis sleeps between frames; keep the main queue responsive.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), block);
}

#pragma mark - Capture flow

+ (void)runCaptureWithHost:(id<FBActionHost>)host {
    if (!host) return;

    // 1. Tell the host to hide the bar so it doesn't appear in the screenshot.
    [host actionsWillCapture];
    [CATransaction flush];

    // 2. Give the compositor a frame to drop the bar from on-screen output.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.05 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        UIImage *img = [FBScreenCapture captureFullScreenBypassingSecureFlag];

        if (!img) {
            [host actionsDidCaptureWithSuccess:NO];
            return;
        }

        // 3. Restore the bar immediately after capture.
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            [PHAssetChangeRequest creationRequestForAssetFromImage:img];
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    AudioServicesPlaySystemSound(1108);
                }
                [host actionsDidCaptureWithSuccess:success];
            });
        }];
    });
}

@end
