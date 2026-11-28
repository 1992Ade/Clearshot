// ============================================================================
// CSInstaller — orchestrates the three things the wrapper app has to do:
//   1. Copy the embedded ClearShotModule.bundle into
//      /Library/ControlCenter/Bundles/ so SpringBoard will pick it up
//   2. Respring (restart SpringBoard) so the newly-installed module loads
//   3. Provide an in-app CARenderServer capture path for the "Test" button,
//      with the same fallback chain the CC module uses at runtime
//
// Also exposes a diagnosticReport the UI shows in a Diagnostics sheet so
// failures on-device have context the user can send back without a mac.
// ============================================================================

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSInstaller : NSObject

// --- Paths -----------------------------------------------------------------
+ (NSString *)systemInstallPath;
+ (NSString *)embeddedBundlePath;
+ (BOOL)isModuleInstalled;

// Record module (the twin that saves video instead of a still). Installed
// alongside the Capture module by installModuleReturningError: — individual
// accessors are exposed for diagnostics and the status label.
+ (NSString *)recordSystemInstallPath;
+ (NSString *)recordEmbeddedBundlePath;
+ (BOOL)isRecordModuleInstalled;

// --- Install ---------------------------------------------------------------
// Installs both the Capture and Record CC bundles. Returns NO on the FIRST
// failure with a verbose error describing which bundle broke.
+ (BOOL)installModuleReturningError:(NSError **)error;

// --- Respring --------------------------------------------------------------
+ (void)respring;

// --- Test capture (same chain as CSModule uses in SpringBoard) ------------
/// Tries CARenderServer first, then UIScreen._snapshotWithRect:
/// (private but widely available), then drawViewHierarchyInRect: against
/// the key window. Only the first path bypasses FLAG_SECURE; the others
/// exist so the Test button can still prove the pipeline works end-to-end.
+ (nullable UIImage *)captureCurrentScreenBypassingSecureFlag;

/// Same as above but with each path tagged — useful in the Test button
/// alert so the user knows which fallback actually produced the image.
+ (nullable UIImage *)captureCurrentScreenReportingPath:(NSString * _Nullable * _Nullable)outPath;

// --- Photos ---------------------------------------------------------------
+ (void)saveImageToPhotos:(UIImage *)image
               completion:(void (^)(BOOL success, NSError * _Nullable error))completion;

// --- Diagnostics (for the UI diagnostic sheet) ----------------------------
+ (NSString *)diagnosticReport;

@end

NS_ASSUME_NONNULL_END
