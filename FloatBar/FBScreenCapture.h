#import <UIKit/UIKit.h>

/// Screen capture that bypasses software-level FLAG_SECURE / protected-content
/// filters via the private CARenderServer path. Does NOT bypass hardware DRM
/// (Netflix/Disney+ secure pipeline on A11+ stays black).
@interface FBScreenCapture : NSObject
+ (UIImage * _Nullable)captureFullScreenBypassingSecureFlag;
@end
