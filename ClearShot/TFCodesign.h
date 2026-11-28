// ============================================================================
// TFCodesign — ad-hoc re-sign a Mach-O after we patched its load commands.
//
// Modified Mach-O binaries break their existing code signature, so iOS
// refuses to launch the app until we regenerate a valid LC_CODE_SIGNATURE
// payload. The simplest tool for the job is `ldid -S`, bundled with every
// TrollStore toolchain, Procursus bootstrap, and most jailbroken devices.
// We probe a handful of common install paths and invoke the first one we
// find via rootSpawn (we're already at euid=0 thanks to setuid(0)).
//
// If no ldid is installed anywhere we can find it, the method returns
// failure with a clear error message pointing the user at where to get it.
// Nothing in TFCodesign writes outside the file it was asked to sign.
// ============================================================================

#import <Foundation/Foundation.h>

@interface TFCodesign : NSObject

// Ad-hoc sign the Mach-O at `path`, replacing whatever LC_CODE_SIGNATURE
// payload was there before. `entitlementsPath` is optional — pass nil to
// just sign with no entitlements (enough for tweak injection into a third-
// party app that doesn't need our entitlements).
+ (BOOL)signMachOAtPath:(NSString *)path
       entitlementsPath:(NSString *)entitlementsPath
                  error:(NSError **)err;

// Path to the ldid we'll use (first match in a known list), or nil if none
// is available. Cached across calls.
+ (NSString *)availableLdidPath;

@end
