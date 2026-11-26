// ============================================================================
// TBSupervisionManager
//
// Factored supervision-plist writer. Used by both the Supervise section
// (SVMainViewController) and the Ad Blocking section (ABMainViewController),
// which both need to toggle IsSupervised + OrganizationName on the same
// CloudConfigurationDetails.plist.
//
// Writes go to a group-owned path, so NSFileManager works at uid=501 without
// rootSpawn.
// ============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBSupervisionManager : NSObject

// Read the IsSupervised flag as iOS sees it (cached plist on disk).
+ (BOOL)isSupervised;

// Returns the OrganizationName currently stamped on the device, or nil.
+ (nullable NSString *)organizationName;

// True if the device looks like it's enrolled in a real MDM (vs our spoof):
// ConfigurationSource != 0, IsMDMUnremovable set, or a non-zero channel
// identifier present. Best-effort heuristic.
+ (BOOL)isSupervisedByExternalMDM;

// Writes the plist with IsSupervised=YES + the standard CloudConfig keys.
// orgName is optional. Returns NO and fills *outErr on failure.
+ (BOOL)supervise:(nullable NSString *)orgName error:(NSError * _Nullable * _Nullable)outErr;

// Writes the plist with IsSupervised=NO (keeps the other keys so iOS doesn't
// re-enter the Setup Assistant flow).
+ (BOOL)unsupervise:(NSError * _Nullable * _Nullable)outErr;

@end

NS_ASSUME_NONNULL_END
