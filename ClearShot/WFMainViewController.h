// ============================================================================
// WFMainViewController — "Saved WiFi" section.
//
// Lists every WiFi network iOS remembers across all its prefs plists, lets
// the user reveal stored passwords (via Keychain query), forget networks
// (via direct plist write — iOS re-reads on next wake), and export the
// whole list as CSV.
//
// Prefs plist paths vary by iOS version:
//   - iOS 11-14 : /var/preferences/SystemConfiguration/com.apple.wifi.plist
//   - iOS 15+  : /var/preferences/com.apple.wifi-known-networks.plist
// We probe both at launch and use whichever is non-empty.
// ============================================================================

#import <UIKit/UIKit.h>

@interface WFMainViewController : UIViewController
@end
