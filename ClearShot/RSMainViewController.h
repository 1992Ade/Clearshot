// ============================================================================
// RSMainViewController — "ResSetter" section.
//
// Port of ResolutionSetterSwift by Hao Nguyen (haoict), with UX rewritten
// per 2026-11-27 session: a single persisted multiplier factor + Apply
// button, instead of the old saved-presets list. Writes canvas_width /
// canvas_height to
//
//   /var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist
//
// Reboot reverts unless the "Re-apply at every boot" persistence toggle is on.
// The second persistence toggle, "Don't lock device after respring", is the
// SBDontLockAfterCrash trick migrated from Jaility's standalone app.
// ============================================================================

#import <UIKit/UIKit.h>

@interface RSMainViewController : UIViewController
@end
