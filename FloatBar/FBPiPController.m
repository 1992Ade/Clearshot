#import "FBPiPController.h"
#import "FBBarViewController.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

API_AVAILABLE(ios(15.0))
@interface FBPiPController () <AVPictureInPictureControllerDelegate>
@property (strong, nonatomic) UIView *hostView;
@property (strong, nonatomic) AVPictureInPictureController *pipController;
@property (strong, nonatomic) AVPictureInPictureVideoCallViewController *callVC;
@property (strong, nonatomic) FBBarViewController *barVC;
@end

@implementation FBPiPController

+ (BOOL)isAvailable {
    if (@available(iOS 15.0, *)) {
        return [AVPictureInPictureController isPictureInPictureSupported];
    }
    return NO;
}

- (instancetype)initWithHostView:(UIView *)hostView {
    if ((self = [super init])) {
        self.hostView = hostView;
        if (@available(iOS 15.0, *)) {
            [self setup];
        }
    }
    return self;
}

- (void)setup API_AVAILABLE(ios(15.0)) {
    self.barVC = [FBBarViewController new];

    self.callVC = [[AVPictureInPictureVideoCallViewController alloc] init];
    self.callVC.preferredContentSize = CGSizeMake(self.barVC.preferredBarWidth, 56);
    [self.callVC addChildViewController:self.barVC];
    self.barVC.view.frame = self.callVC.view.bounds;
    self.barVC.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.callVC.view addSubview:self.barVC.view];
    [self.barVC didMoveToParentViewController:self.callVC];

    AVPictureInPictureControllerContentSource *source =
        [[AVPictureInPictureControllerContentSource alloc] initWithActiveVideoCallSourceView:self.hostView
                                                                         contentViewController:self.callVC];
    self.pipController = [[AVPictureInPictureController alloc] initWithContentSource:source];
    self.pipController.canStartPictureInPictureAutomaticallyFromInline = YES;
    self.pipController.delegate = self;
}

- (BOOL)isActive {
    if (@available(iOS 15.0, *)) {
        return self.pipController.isPictureInPictureActive;
    }
    return NO;
}

- (void)start {
    if (@available(iOS 15.0, *)) {
        if (!self.pipController.isPictureInPictureActive) {
            [self.pipController startPictureInPicture];
        }
    }
}

- (void)stop {
    if (@available(iOS 15.0, *)) {
        if (self.pipController.isPictureInPictureActive) {
            [self.pipController stopPictureInPicture];
        }
    }
}

- (void)reloadConfig {
    if (@available(iOS 15.0, *)) {
        [self.barVC reloadFromConfig];
        self.callVC.preferredContentSize = CGSizeMake(self.barVC.preferredBarWidth, 56);
    }
}

#pragma mark - AVPictureInPictureControllerDelegate

- (void)pictureInPictureController:(AVPictureInPictureController *)pipc failedToStartPictureInPictureWithError:(NSError *)error API_AVAILABLE(ios(15.0)) {
    NSLog(@"[FloatBar] PiP failed to start: %@", error);
}

@end
