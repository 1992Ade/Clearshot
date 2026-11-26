// ============================================================================
// LSManager — thin wrapper over CLSimulationManager, ported from Andromeda's
// LocSimManager.swift. One shared instance so flush/start/stop pair up.
// ============================================================================

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

NS_ASSUME_NONNULL_BEGIN

@interface LSManager : NSObject

/// Start feeding `location` as the device's current CLLocation.
+ (void)startWithLocation:(CLLocation *)location;

/// Stop simulation and clear whatever was queued.
+ (void)stop;

/// True if we've started a sim this session. CLSimulationManager has no
/// isSimulating property so we track it ourselves.
+ (BOOL)isActive;

@end

NS_ASSUME_NONNULL_END
