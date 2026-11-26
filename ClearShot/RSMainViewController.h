// ============================================================================
// RSMainViewController — "ResSetter" section.
//
// Port of ResolutionSetterSwift by Hao Nguyen (haoict). Changes the logical
// display size iOS reports by writing canvas_width / canvas_height to
//
//   /var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist
//
// Reboot reverts to the original. We expose only two kinds of entries,
// matching the user's request: the current device resolution and whatever
// custom resolutions the user has saved. No preset examples ("iPhone 14",
// "iPad Pro" etc.) — that was the original app's approach and we skip it.
// ============================================================================

#import <UIKit/UIKit.h>

@interface RSMainViewController : UIViewController
@end
