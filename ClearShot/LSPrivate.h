// ============================================================================
// Private CoreLocation header for CLSimulationManager.
// Straight port of Andromeda/Geranium's LocSimPrivateHeaders.h — the API
// surface is identical because CoreLocation is a system framework on both
// sides. We only need appendSimulatedLocation / start / stop / flush.
// ============================================================================

#import <Foundation/Foundation.h>
#import <stdint.h>

@interface CLSimulationManager : NSObject
@property (assign, nonatomic) uint8_t  locationDeliveryBehavior;
@property (assign, nonatomic) double   locationDistance;
@property (assign, nonatomic) double   locationInterval;
@property (assign, nonatomic) double   locationSpeed;
@property (assign, nonatomic) uint8_t  locationRepeatBehavior;
- (void)clearSimulatedLocations;
- (void)startLocationSimulation;
- (void)stopLocationSimulation;
- (void)appendSimulatedLocation:(id)arg1;
- (void)flush;
- (void)loadScenarioFromURL:(id)arg1;
- (void)setSimulatedWifiPower:(BOOL)arg1;
- (void)startWifiSimulation;
- (void)stopWifiSimulation;
- (void)setSimulatedCell:(id)arg1;
- (void)startCellSimulation;
- (void)stopCellSimulation;
@end
