// ============================================================================
// TBSpringBoardPrefs — tiny helper that reads/writes the SBDontLockAfterCrash
// key in /var/Managed Preferences/mobile/com.apple.springboard.plist.
//
// Mirrored UI for this toggle lives in four places:
//   • SpringBoard Tweaks section (canonical home)
//   • ResSetter → Persistence (respring-heavy workflow)
//   • Badge Color → Persistence row (Apply respring)
//   • ClearShot → Persistence row (CC install respring)
//
// Each VC reads the current value via +dontLockActive and writes via
// +setDontLockActive:error:. All four stay in sync automatically because
// they all touch the same plist key.
// ============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBSpringBoardPrefs : NSObject

+ (BOOL)dontLockActive;
+ (BOOL)setDontLockActive:(BOOL)on error:(NSError **)err;

@end

NS_ASSUME_NONNULL_END
