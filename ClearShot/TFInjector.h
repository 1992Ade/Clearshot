// ============================================================================
// TFInjector — orchestrate dylib / bundle injection into a target .app.
//
// High-level steps per inject call:
//   1. Resolve the target app's .app directory on disk from its bundleId.
//   2. Copy the dylib (or .bundle, or unpacked .deb) into
//      <App.app>/Frameworks/<leafname>.
//   3. Patch the main executable's Mach-O to add LC_LOAD_DYLIB pointing to
//      @executable_path/Frameworks/<leafname> (TFMachO).
//   4. Ad-hoc re-sign the modified executable (TFCodesign).
//   5. Record the injection in NSUserDefaults so the UI can show "already
//      injected" and support eject.
//
// Eject reverses step 2-4. LSApplicationWorkspace's registerApplication
// bump is called afterwards in both directions so SpringBoard picks up the
// change; the user is advised to force-quit the app and re-launch it.
// ============================================================================

#import <Foundation/Foundation.h>

@class LSApplicationProxy;

@interface TFInjector : NSObject

// Inject `dylibOnDiskPath` into the app identified by `bundleId`. Returns
// the leafname used inside the app's Frameworks directory on success, or
// nil + sets `err`.
+ (NSString *)injectDylibAtPath:(NSString *)dylibOnDiskPath
                      intoAppID:(NSString *)bundleId
                          error:(NSError **)err;

// Remove a previously-injected dylib. `leafname` is what was returned by
// injectDylibAtPath:intoAppID:error: or is listed by injectedDylibLeafsForAppID:.
+ (BOOL)ejectDylibLeaf:(NSString *)leafname
             fromAppID:(NSString *)bundleId
                 error:(NSError **)err;

// Enumerate dylibs currently injected into `bundleId` — reads both our own
// NSUserDefaults registry AND the live LC_LOAD_DYLIB commands in the target
// binary, so if the user injected via another tool (TrollFools standalone)
// we still see it.
+ (NSArray<NSString *> *)injectedDylibLeafsForAppID:(NSString *)bundleId;

// Resolve the full on-disk .app directory for a bundleId.
+ (NSString *)appDirForBundleId:(NSString *)bundleId;

@end
