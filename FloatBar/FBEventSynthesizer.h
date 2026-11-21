#import <Foundation/Foundation.h>

/// HID event synthesis driven from a standalone TrollStore .tipa (no injection
/// into SpringBoard). Relies on BKSHIDEventPostFast / IOHIDEventSystemClient.
@interface FBEventSynthesizer : NSObject

/// Simulate the hardware Home button press (short press + release).
/// Works on devices with or without a physical Home button; on Face ID devices
/// the system interprets the Consumer-Menu HID as a Home press.
+ (BOOL)synthesizeHomeButtonPress;

/// Simulate the back edge swipe from the left edge.
+ (BOOL)synthesizeBackEdgeSwipe;

/// Simulate the app switcher gesture (swipe up from the bottom edge with a pause).
+ (BOOL)synthesizeAppSwitcherSwipe;

@end
