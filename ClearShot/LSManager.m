#import "LSManager.h"
#import "LSPrivate.h"

@implementation LSManager

static CLSimulationManager *sSim = nil;
static BOOL sActive = NO;

+ (CLSimulationManager *)shared {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        sSim = [[CLSimulationManager alloc] init];
    });
    return sSim;
}

+ (void)startWithLocation:(CLLocation *)location {
    CLSimulationManager *s = [self shared];
    [s stopLocationSimulation];
    [s clearSimulatedLocations];
    [s appendSimulatedLocation:location];
    [s flush];
    [s startLocationSimulation];
    sActive = YES;

    // Andromeda posts this darwin notification after every change — iOS
    // uses it to re-evaluate automatic time-zone updates. Keeps the UI
    // (time on lock screen, Weather app) in sync with the fake location.
    CFNotificationCenterPostNotificationWithOptions(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("AutomaticTimeZoneUpdateNeeded"),
        NULL, NULL, kCFNotificationDeliverImmediately);
}

+ (void)stop {
    CLSimulationManager *s = [self shared];
    [s stopLocationSimulation];
    [s clearSimulatedLocations];
    [s flush];
    sActive = NO;

    CFNotificationCenterPostNotificationWithOptions(
        CFNotificationCenterGetDarwinNotifyCenter(),
        CFSTR("AutomaticTimeZoneUpdateNeeded"),
        NULL, NULL, kCFNotificationDeliverImmediately);
}

+ (BOOL)isActive { return sActive; }

@end
