#import "TBSupervisionManager.h"

// Same path SVMainViewController used to write to. iOS reads this plist to
// decide whether the device is supervised; MobileConfigurationUtility /
// Managed Configuration code both honour IsSupervised = YES from here.
static NSString * const kCloudConfigPath =
    @"/var/containers/Shared/SystemGroup/"
    @"systemgroup.com.apple.configurationprofiles/"
    @"Library/ConfigurationProfiles/CloudConfigurationDetails.plist";

@implementation TBSupervisionManager

+ (NSDictionary *)readPlist {
    return [NSDictionary dictionaryWithContentsOfFile:kCloudConfigPath];
}

+ (BOOL)isSupervised {
    NSDictionary *p = [self readPlist];
    return [p[@"IsSupervised"] boolValue];
}

+ (NSString *)organizationName {
    NSString *name = [self readPlist][@"OrganizationName"];
    return name.length ? name : nil;
}

+ (BOOL)isSupervisedByExternalMDM {
    NSDictionary *p = [self readPlist];
    if (!p) return NO;
    // ConfigurationSource: 0 is "user / local", non-zero typically means a
    // DEP / ABM enrollment.
    NSNumber *src = p[@"ConfigurationSource"];
    if (src && src.integerValue != 0) return YES;
    // IsMDMUnremovable tells us an MDM profile is locked to the device.
    if ([p[@"IsMDMUnremovable"] boolValue]) return YES;
    // Presence of a ManagingOrganization string set by a DEP server.
    NSString *mo = p[@"ManagingOrganization"];
    if (mo.length) return YES;
    return NO;
}

+ (BOOL)writeDict:(NSDictionary *)dict error:(NSError **)outErr {
    NSString *parent = [kCloudConfigPath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:parent]) {
        [fm createDirectoryAtPath:parent
       withIntermediateDirectories:YES attributes:nil error:nil];
    }
    return [dict writeToURL:[NSURL fileURLWithPath:kCloudConfigPath]
                      error:outErr];
}

+ (BOOL)supervise:(NSString *)orgName error:(NSError **)outErr {
    NSMutableDictionary *dict = [@{
        @"AllowPairing":                 @YES,
        @"CloudConfigurationUIComplete": @YES,
        @"ConfigurationSource":          @0,
        @"IsSupervised":                 @YES,
        @"PostSetupProfileWasInstalled": @YES,
    } mutableCopy];
    if (orgName.length) dict[@"OrganizationName"] = orgName;
    return [self writeDict:dict error:outErr];
}

+ (BOOL)unsupervise:(NSError **)outErr {
    NSDictionary *dict = @{
        @"AllowPairing":                 @YES,
        @"CloudConfigurationUIComplete": @YES,
        @"ConfigurationSource":          @0,
        @"IsSupervised":                 @NO,
        @"PostSetupProfileWasInstalled": @YES,
    };
    return [self writeDict:dict error:outErr];
}

@end
