// ============================================================================
// TBHomeViewController — TrollBox launcher.
//
// Scrollable grid of section cards (ClearShot, LocSim, Supervise, Tweaks,
// Icons, Ad Blocking, ResSetter, About). Tapping a card pushes the
// section's root view controller onto the navigation stack.
//
// Grid instead of UITabBar because iOS caps the visible tab bar at five
// items — with eight sections we'd lose everything past LocSim under
// "More". Andromeda's own home layout follows the same pattern.
// ============================================================================

#import <UIKit/UIKit.h>

@interface TBHomeViewController : UIViewController
@end
