// ============================================================================
// CSProcessUtils — process management for TrollStore apps.
//
// Why this exists: the original ClearShot wired respring to
//
//     posix_spawn("/usr/bin/killall", ["killall", "SpringBoard"])
//
// which quietly stopped working for a lot of TrollStore apps on iOS 15.7+.
// Spawning a child that successfully kills SpringBoard requires the parent
// to set persona attributes on the posix_spawnattr, otherwise the child
// inherits a reduced identity and gets EPERM.
//
// Two working approaches, both of which we implement:
//
//   1. Direct kill from inside our own process. Our app is a platform
//      binary (TrollStore's `platform-application` entitlement) so it runs
//      as uid 0. We can enumerate PIDs via sysctl and kill(pid, SIGTERM)
//      ourselves — no spawn needed. This is the Andromeda/Geranium approach.
//
//   2. posix_spawn with persona attrs. For cases where we actually need to
//      execute a helper binary. This is TrollFools' approach (via
//      AuxiliaryExecute).
//
// We also expose a `forceRespring` that stacks all three known ways to
// restart SpringBoard, in order of robustness, so a single button press
// has multiple chances to succeed.
// ============================================================================

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CSProcessUtils : NSObject

/// Walk the live process list and kill every process whose last path
/// component matches `name`. Runs entirely in our own process — no spawn.
+ (NSUInteger)killAllProcessesNamed:(NSString *)name;

/// Fire SIGTERM at SpringBoard, FrontBoard and BackBoard, then fall back
/// to the private respring-by-snapshot trick, then exit(0) ourselves if
/// SpringBoard has not restarted us within 2 s.
+ (void)forceRespring;

/// posix_spawn a binary with persona attrs so the child ends up as
/// uid 0 even on iOS 15.7+. Returns child's exit status, or -1 on spawn
/// failure. `stdOut`/`stdErr` capture is optional.
+ (int)rootSpawn:(NSString *)path
              args:(NSArray<NSString *> *)args
            stdOut:(NSString * _Nullable * _Nullable)stdOut
            stdErr:(NSString * _Nullable * _Nullable)stdErr;

/// Convenience for the UI diagnostic sheet.
+ (NSString *)currentProcessIdentitySummary;

@end

NS_ASSUME_NONNULL_END
