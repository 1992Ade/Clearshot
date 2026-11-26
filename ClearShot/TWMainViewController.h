// ============================================================================
// TWMainViewController — "Tweaks" section.
//
// Target: feature-parity with TrollFools (Lessica/TrollFools). TrollFools
// lets you inject or eject dylibs and tweak bundles into any .app on the
// device, without jailbreak, by rewriting the app's main Mach-O load
// commands. The heavy lifting lives in InjectorV3 (Swift) which parses
// LC_LOAD_DYLIB and friends and rewrites the binary in place.
//
// This file is the first slice: the user-facing app picker + per-app
// injection list. The MachO editor port (InjectorV3) is intentionally
// stubbed and marked TODO — porting ~3k lines of Swift through MachO
// parsing is its own commit, and we want the rest of TrollBox buildable
// while that work happens.
// ============================================================================

#import <UIKit/UIKit.h>

@interface TWMainViewController : UITableViewController
@end
