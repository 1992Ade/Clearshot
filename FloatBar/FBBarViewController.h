#import <UIKit/UIKit.h>

/// Horizontal navigation bar rendered inside the floating PiP window.
/// Rebuilds its buttons when the stored configuration changes.
@interface FBBarViewController : UIViewController

/// Rebuild buttons from FBButtonConfig.enabledOrderedButtons.
- (void)reloadFromConfig;

/// Natural width in points for the current button set (56 pt per button).
@property (nonatomic, readonly) CGFloat preferredBarWidth;

@end
