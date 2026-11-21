#import <UIKit/UIKit.h>
#import "FBButtonConfig.h"

@protocol FBActionHost <NSObject>
/// Called before a capture action so the host can hide the floating bar
/// from the screenshot. Must return quickly.
- (void)actionsWillCapture;
/// Called after a capture action so the host can restore the bar.
/// `success` indicates whether the capture was saved to Photos.
- (void)actionsDidCaptureWithSuccess:(BOOL)success;
@end

@interface FBActions : NSObject

+ (void)performAction:(FBButtonType)type
                 host:(id<FBActionHost>)host;

@end
