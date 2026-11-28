#import "TBSpringBoardPrefs.h"

static NSString * const kSpringBoardPlist =
    @"/var/Managed Preferences/mobile/com.apple.springboard.plist";
static NSString * const kDontLockKey = @"SBDontLockAfterCrash";

@implementation TBSpringBoardPrefs

+ (BOOL)dontLockActive {
    NSDictionary *p = [NSDictionary dictionaryWithContentsOfFile:kSpringBoardPlist];
    return [p[kDontLockKey] boolValue];
}

+ (BOOL)setDontLockActive:(BOOL)on error:(NSError **)err {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kSpringBoardPlist];
    if (existing) [d addEntriesFromDictionary:existing];

    if (on) d[kDontLockKey] = @YES;
    else    [d removeObjectForKey:kDontLockKey];

    NSString *parent = [kSpringBoardPlist stringByDeletingLastPathComponent];
    if (![[NSFileManager defaultManager] fileExistsAtPath:parent]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:parent
                                  withIntermediateDirectories:YES
                                                    attributes:nil error:nil];
    }
    return [d writeToURL:[NSURL fileURLWithPath:kSpringBoardPlist] error:err];
}

@end
