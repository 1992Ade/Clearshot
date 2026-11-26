// ============================================================================
// LSMainViewController — "LocSim" section.
//
// Minimal first-pass UI: two coordinate text fields + preset buttons for
// a few well-known places, Start / Stop, and a live "Currently simulating"
// status card. Deliberately no map/joystick here — those are 2k+ lines of
// Swift in Andromeda; we'll port them in a follow-up once the core
// CLSimulationManager path is proven to work with our entitlements.
// ============================================================================

#import <UIKit/UIKit.h>

@interface LSMainViewController : UIViewController
@end
