#import "ABMainViewController.h"
#import "TBSupervisionManager.h"
#import "CSProcessUtils.h"

// Private MCProfileConnection — we have the entitlement
// com.apple.managedconfiguration.profiled-access which lets us install /
// remove profiles silently (no "Profile Downloaded" Settings dance).
@interface MCProfileConnection : NSObject
+ (instancetype)sharedConnection;
- (id)installProfileData:(NSData *)data outError:(NSError **)err;
- (id)installProfileAtURL:(NSURL *)url outError:(NSError **)err;
- (id)removeProfileWithIdentifier:(NSString *)identifier outError:(NSError **)err;
- (NSArray *)installedProfilesWithScope:(int)scope;
@end

// NSUserDefaults keys for toggle persistence.
static NSString * const kABToggleNoFB       = @"TBABToggleNoFB";
static NSString * const kABToggleNoXXX      = @"TBABToggleNoXXX";
static NSString * const kABToggleNoOTA      = @"TBABToggleNoOTA";
static NSString * const kABLastRefreshDate  = @"TBABLastStevenBlackRefresh";

// Identifier that must match the one in our proxy-payload.plist template.
static NSString * const kABProfileIdentifier = @"com.trollbox.adblock";

// Sandbox location where a user-refreshed PAC is cached. If present, overrides
// the bundled baseline.
static NSString *ABSandboxPACPath(NSString *baseName) {
    NSArray *dirs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory,
                                                         NSUserDomainMask, YES);
    NSString *dir = [dirs.firstObject stringByAppendingPathComponent:@"AdBlockPACs"];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    return [dir stringByAppendingPathComponent:
            [NSString stringWithFormat:@"Updated_%@", baseName]];
}

@interface ABMainViewController ()
@property (strong, nonatomic) UISwitch *noFBSwitch;
@property (strong, nonatomic) UISwitch *noXXXSwitch;
@property (strong, nonatomic) UISwitch *noOTASwitch;
@property (strong, nonatomic) UISwitch *superviseSwitch;
@end

@implementation ABMainViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Ad Blocking";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    self.noFBSwitch  = [self switchOn:[d boolForKey:kABToggleNoFB]];
    self.noXXXSwitch = [self switchOn:[d boolForKey:kABToggleNoXXX]];
    self.noOTASwitch = [self switchOn:[d boolForKey:kABToggleNoOTA]];
    self.superviseSwitch = [self switchOn:[TBSupervisionManager isSupervised]];

    [self.noFBSwitch  addTarget:self action:@selector(didToggleFilter:)
                forControlEvents:UIControlEventValueChanged];
    [self.noXXXSwitch addTarget:self action:@selector(didToggleFilter:)
                forControlEvents:UIControlEventValueChanged];
    [self.noOTASwitch addTarget:self action:@selector(didToggleFilter:)
                forControlEvents:UIControlEventValueChanged];
    [self.superviseSwitch addTarget:self action:@selector(didToggleSupervise:)
                   forControlEvents:UIControlEventValueChanged];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    self.superviseSwitch.on = [TBSupervisionManager isSupervised];
    [self.tableView reloadData];
}

- (UISwitch *)switchOn:(BOOL)on {
    UISwitch *s = [[UISwitch alloc] init];
    s.on = on;
    return s;
}

#pragma mark - Table sections

// 0: Preamble + Enable (+ Status)
// 1: Filters (3 toggles)
// 2: Supervision (status + toggle)
// 3: Install / Remove / Refresh
// 4: Blocklist maintenance (dates + refresh button)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 5; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    switch (s) {
        case 0: return 1;   // status
        case 1: return 3;   // noFB, noXXX, noOTA
        case 2: return 2;   // status + toggle
        case 3: return 2;   // generate+install, remove
        case 4: return 2;   // date row + refresh button
    }
    return 0;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    switch (s) {
        case 1: return @"Filters";
        case 2: return @"Supervision";
        case 3: return @"Profile";
        case 4: return @"Blocklist maintenance";
    }
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"Blocks ads, trackers, crypto-miners and anti-revoke "
               @"endpoints system-wide via a Global HTTP Proxy profile "
               @"(MYbloXX mechanism, PACs embedded locally — ~83,000 "
               @"domains merged from MYbloXX + StevenBlack). No MITM, no "
               @"HTTPS decryption, no third-party server sees your traffic.";
    }
    if (s == 1) {
        return @"• Allow Facebook/Instagram login: unblocks only "
               @"graph.facebook.com + graph.instagram.com (the login SDK "
               @"endpoints). Keeps all FB tracking blocked.\n"
               @"• Block adult content: adds ~45 wildcard filters on top "
               @"of the baseline.\n"
               @"• Block iOS updates: installs a fake tvOS Beta Software "
               @"Profile that silences Software Update. Reversible.";
    }
    if (s == 2) {
        return @"iOS only accepts the Global HTTP Proxy payload on a "
               @"supervised device. TrollBox spoofs supervision by writing "
               @"a plist (same mechanism as the Supervise tab).";
    }
    if (s == 4) {
        return @"The app ships with a baseline merged at build time. Tap "
               @"Refresh to pull a fresher StevenBlack list and merge it "
               @"in-place. Re-apply the profile after refreshing.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
                              initWithStyle:UITableViewCellStyleSubtitle
                             reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];

    if (ip.section == 0) {
        BOOL installed = [self isProfileInstalled];
        cell.textLabel.text = installed ? @"✅ Profile installed" : @"❌ No profile installed";
        cell.detailTextLabel.text = installed
            ? [self currentConfigurationSummary]
            : @"Pick filters below, then tap Install.";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

    } else if (ip.section == 1) {
        if (ip.row == 0) {
            cell.textLabel.text = @"Allow Facebook/Instagram login";
            cell.accessoryView = self.noFBSwitch;
        } else if (ip.row == 1) {
            cell.textLabel.text = @"Block adult content";
            cell.accessoryView = self.noXXXSwitch;
        } else {
            cell.textLabel.text = @"Block iOS updates (tvOS Beta trick)";
            cell.accessoryView = self.noOTASwitch;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

    } else if (ip.section == 2) {
        if (ip.row == 0) {
            if ([TBSupervisionManager isSupervisedByExternalMDM]) {
                cell.textLabel.text = @"⚠️ External MDM detected";
                cell.detailTextLabel.text = @"Don't override — your MDM may push policies.";
            } else if ([TBSupervisionManager isSupervised]) {
                NSString *org = [TBSupervisionManager organizationName];
                cell.textLabel.text = @"✅ Supervised (spoofed by TrollBox)";
                cell.detailTextLabel.text = org.length ? org : @"No organisation name set.";
            } else {
                cell.textLabel.text = @"❌ Not supervised";
                cell.detailTextLabel.text = @"Required for ad blocking profile install.";
            }
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Spoof supervision";
            cell.accessoryView = self.superviseSwitch;
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }

    } else if (ip.section == 3) {
        if (ip.row == 0) {
            cell.textLabel.text = @"Generate & install profile";
            cell.textLabel.textColor = [UIColor systemBlueColor];
        } else {
            cell.textLabel.text = @"Remove profile";
            cell.textLabel.textColor = [UIColor systemOrangeColor];
        }
        cell.textLabel.textAlignment = NSTextAlignmentCenter;

    } else { // section 4
        if (ip.row == 0) {
            NSDate *last = [[NSUserDefaults standardUserDefaults] objectForKey:kABLastRefreshDate];
            cell.textLabel.text = @"Last in-app refresh";
            if (last) {
                NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
                fmt.dateStyle = NSDateFormatterMediumStyle;
                fmt.timeStyle = NSDateFormatterShortStyle;
                cell.detailTextLabel.text = [fmt stringFromDate:last];
            } else {
                cell.detailTextLabel.text = @"never (using bundled baseline)";
            }
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = @"Refresh blocklist from StevenBlack";
            cell.textLabel.textColor = [UIColor systemGreenColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 3 && ip.row == 0) [self doInstallProfile];
    else if (ip.section == 3 && ip.row == 1) [self doRemoveProfile];
    else if (ip.section == 4 && ip.row == 1) [self doRefreshStevenBlack];
}

#pragma mark - Toggle handlers

- (void)didToggleFilter:(UISwitch *)sw {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setBool:self.noFBSwitch.on  forKey:kABToggleNoFB];
    [d setBool:self.noXXXSwitch.on forKey:kABToggleNoXXX];
    [d setBool:self.noOTASwitch.on forKey:kABToggleNoOTA];
    [d synchronize];
}

- (void)didToggleSupervise:(UISwitch *)sw {
    if ([TBSupervisionManager isSupervisedByExternalMDM]) {
        [self alert:@"External MDM"
            message:@"This device is supervised by an external MDM. "
                    @"TrollBox won't overwrite that configuration."];
        sw.on = YES;
        return;
    }
    NSError *err = nil;
    BOOL ok;
    if (sw.on) {
        ok = [TBSupervisionManager supervise:nil error:&err];
    } else {
        ok = [TBSupervisionManager unsupervise:&err];
    }
    if (!ok) {
        [self alert:@"Supervision write failed"
            message:err.localizedDescription ?: @"unknown"];
        sw.on = !sw.on;
        return;
    }
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                  withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - PAC selection

- (NSString *)pickedPACBaseName {
    BOOL noFB  = self.noFBSwitch.on;
    BOOL noXXX = self.noXXXSwitch.on;
    if  (noFB && noXXX) return @"MYbloXXnoFBnoXXX.pac";
    if  (noFB)          return @"MYbloXXnoFB.pac";
    if  (noXXX)         return @"MYbloXXnoXXX.pac";
    return @"MYbloXX.pac";
}

- (NSString *)pickedPACPath {
    NSString *name = [self pickedPACBaseName];
    NSString *sandbox = ABSandboxPACPath(name);
    if ([[NSFileManager defaultManager] fileExistsAtPath:sandbox]) return sandbox;
    NSString *bundled = [[NSBundle mainBundle] pathForResource:
                         [name stringByDeletingPathExtension]
                                                        ofType:@"pac"
                                                   inDirectory:@"AdBlock/PAC"];
    if (!bundled) {
        // Fallback: Makefile may have placed them directly under the .app root/AdBlock/PAC/.
        NSString *appPath = [[NSBundle mainBundle] bundlePath];
        bundled = [appPath stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"AdBlock/PAC/%@", name]];
        if (![[NSFileManager defaultManager] fileExistsAtPath:bundled]) bundled = nil;
    }
    return bundled;
}

#pragma mark - Install / remove

- (NSString *)currentConfigurationSummary {
    NSMutableArray *bits = [NSMutableArray array];
    if (self.noFBSwitch.on)  [bits addObject:@"FB login OK"];
    if (self.noXXXSwitch.on) [bits addObject:@"adults blocked"];
    if (self.noOTASwitch.on) [bits addObject:@"iOS updates blocked"];
    if (bits.count == 0)     [bits addObject:@"standard"];
    return [bits componentsJoinedByString:@", "];
}

- (BOOL)isProfileInstalled {
    Class mcClass = NSClassFromString(@"MCProfileConnection");
    if (!mcClass) return NO;
    MCProfileConnection *mc = [mcClass sharedConnection];
    NSArray *profiles = [mc installedProfilesWithScope:0];
    for (id prof in profiles) {
        if ([[prof valueForKey:@"profileIdentifier"] isEqualToString:kABProfileIdentifier])
            return YES;
    }
    return NO;
}

- (void)doInstallProfile {
    // 0. Must be supervised.
    if (![TBSupervisionManager isSupervised]) {
        [self alert:@"Supervision required"
            message:@"Turn on \"Spoof supervision\" in the Supervision "
                    @"section above first. iOS refuses the Global HTTP "
                    @"Proxy payload on non-supervised devices."];
        return;
    }

    // 1. Load the PAC.
    NSString *pacPath = [self pickedPACPath];
    if (!pacPath) {
        [self alert:@"PAC missing"
            message:[NSString stringWithFormat:
                     @"Couldn't find the embedded PAC %@. The app bundle "
                     @"may have been built without AdBlock/PAC/ assets.",
                     [self pickedPACBaseName]]];
        return;
    }
    NSData *pacData = [NSData dataWithContentsOfFile:pacPath];
    if (!pacData.length) {
        [self alert:@"PAC empty" message:pacPath];
        return;
    }
    NSString *pacB64 = [pacData base64EncodedStringWithOptions:0];
    NSString *pacDataURL = [@"data:application/x-ns-proxy-autoconfig;base64," stringByAppendingString:pacB64];

    // 2. Load the proxy payload template, substitute the PAC data: URL.
    NSString *proxyTplPath = [self templatePath:@"proxy-payload.plist"];
    NSMutableDictionary *proxyPayload = [[NSMutableDictionary alloc]
        initWithContentsOfFile:proxyTplPath];
    if (!proxyPayload) {
        [self alert:@"Template missing"
            message:[NSString stringWithFormat:
                     @"proxy-payload.plist template not found at:\n%@",
                     proxyTplPath]];
        return;
    }
    proxyPayload[@"ProxyPACURL"] = pacDataURL;

    // 3. Compose the mobileconfig.
    NSMutableArray *payloads = [NSMutableArray arrayWithObject:proxyPayload];
    if (self.noOTASwitch.on) {
        NSString *otaTplPath = [self templatePath:@"tvos-beta-payload.plist"];
        NSDictionary *otaPayload = [NSDictionary dictionaryWithContentsOfFile:otaTplPath];
        if (otaPayload) [payloads addObject:otaPayload];
    }
    NSDictionary *mobileconfig = @{
        @"PayloadType":              @"Configuration",
        @"PayloadVersion":           @1,
        @"PayloadIdentifier":        kABProfileIdentifier,
        @"PayloadUUID":              [[NSUUID UUID] UUIDString],
        @"PayloadDisplayName":       @"TrollBox Ad Blocking",
        @"PayloadDescription":       @"Blocks ads and trackers system-wide.",
        @"PayloadOrganization":      @"TrollBox",
        @"PayloadRemovalDisallowed": @NO,
        @"PayloadContent":           payloads,
    };

    // 4. Serialise and install.
    NSError *plistErr = nil;
    NSData *profileData = [NSPropertyListSerialization
                            dataWithPropertyList:mobileconfig
                                          format:NSPropertyListXMLFormat_v1_0
                                         options:0
                                           error:&plistErr];
    if (!profileData) {
        [self alert:@"Serialize failed"
            message:plistErr.localizedDescription ?: @"unknown"];
        return;
    }

    Class mcClass = NSClassFromString(@"MCProfileConnection");
    if (mcClass) {
        MCProfileConnection *mc = [mcClass sharedConnection];
        NSError *installErr = nil;
        id ret = [mc installProfileData:profileData outError:&installErr];
        (void)ret;
        if (installErr) {
            [self alert:@"Install failed"
                message:[NSString stringWithFormat:
                         @"MCProfileConnection install error:\n%@\n\n"
                         @"Falling back: the profile has been saved to Files; "
                         @"install it from Settings → Profile Downloaded.",
                         installErr.localizedDescription]];
            [self shareProfileFallback:profileData];
        } else {
            [self alert:@"Installed"
                message:[NSString stringWithFormat:
                         @"Ad Blocking profile installed (%@). "
                         @"Open Safari or any app and check that ads are gone.",
                         [self currentConfigurationSummary]]];
            [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                          withRowAnimation:UITableViewRowAnimationAutomatic];
        }
    } else {
        // No MCProfileConnection (e.g. SideStore build with stripped entitlement)
        // — fall back to the Settings → Profile Downloaded flow.
        [self shareProfileFallback:profileData];
    }
}

- (void)shareProfileFallback:(NSData *)data {
    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      @"TrollBoxAdBlock.mobileconfig"];
    [data writeToFile:tmp atomically:YES];
    UIActivityViewController *av = [[UIActivityViewController alloc]
                                     initWithActivityItems:@[[NSURL fileURLWithPath:tmp]]
                                     applicationActivities:nil];
    [self presentViewController:av animated:YES completion:nil];
}

- (void)doRemoveProfile {
    Class mcClass = NSClassFromString(@"MCProfileConnection");
    if (!mcClass) {
        [self alert:@"Not available"
            message:@"MCProfileConnection isn't exposed in this build. "
                    @"Remove the profile manually via Settings → General → "
                    @"VPN & Device Management."];
        return;
    }
    MCProfileConnection *mc = [mcClass sharedConnection];
    NSError *err = nil;
    [mc removeProfileWithIdentifier:kABProfileIdentifier outError:&err];
    if (err) {
        [self alert:@"Remove failed"
            message:err.localizedDescription ?: @"unknown"];
    } else {
        [self alert:@"Removed"
            message:@"Ad Blocking profile removed."];
        [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:0]
                      withRowAnimation:UITableViewRowAnimationAutomatic];
    }
}

#pragma mark - Template path lookup

- (NSString *)templatePath:(NSString *)name {
    NSString *bundled = [[NSBundle mainBundle] pathForResource:
                         [name stringByDeletingPathExtension]
                                                        ofType:[name pathExtension]
                                                   inDirectory:@"AdBlock/Templates"];
    if (bundled) return bundled;
    NSString *appPath = [[NSBundle mainBundle] bundlePath];
    NSString *fallback = [appPath stringByAppendingPathComponent:
                           [NSString stringWithFormat:@"AdBlock/Templates/%@", name]];
    return fallback;
}

#pragma mark - StevenBlack refresh

- (void)doRefreshStevenBlack {
    UIAlertController *progress = [UIAlertController
        alertControllerWithTitle:@"Refreshing"
                         message:@"Downloading StevenBlack hosts…"
                  preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];

    NSURL *url = [NSURL URLWithString:
        @"https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts"];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithURL:url
        completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [progress dismissViewControllerAnimated:YES completion:^{
                    if (error || !data.length) {
                        [self alert:@"Download failed"
                            message:error.localizedDescription ?: @"empty response"];
                        return;
                    }
                    [self mergeStevenBlackData:data];
                }];
            });
        }];
    [task resume];
}

- (void)mergeStevenBlackData:(NSData *)hostsData {
    NSString *hosts = [[NSString alloc] initWithData:hostsData encoding:NSUTF8StringEncoding];
    if (!hosts) {
        [self alert:@"Parse failed" message:@"StevenBlack hosts file isn't UTF-8."];
        return;
    }
    // Parse "0.0.0.0 domain.tld" lines (ignoring comments / IPv6 / localhost).
    NSMutableSet *domains = [NSMutableSet set];
    [hosts enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             NSCharacterSet.whitespaceCharacterSet];
        if ([trimmed hasPrefix:@"#"] || trimmed.length == 0) return;
        NSArray *parts = [trimmed componentsSeparatedByCharactersInSet:
                           NSCharacterSet.whitespaceCharacterSet];
        if (parts.count < 2) return;
        if (![parts[0] isEqualToString:@"0.0.0.0"]) return;
        NSString *dom = [parts[1] lowercaseString];
        if (dom.length > 3 && [dom containsString:@"."] && ![dom hasPrefix:@"#"]) {
            [domains addObject:dom];
        }
    }];

    // For each of our 4 base PACs, re-write the bad_da_host_JSON with the
    // union of the existing block list + the fresh domains.
    NSArray *bases = @[ @"MYbloXX.pac", @"MYbloXXnoFB.pac",
                        @"MYbloXXnoXXX.pac", @"MYbloXXnoFBnoXXX.pac" ];
    NSInteger updated = 0;
    for (NSString *name in bases) {
        NSString *src = [[NSBundle mainBundle] pathForResource:
                         [name stringByDeletingPathExtension]
                                                        ofType:@"pac"
                                                   inDirectory:@"AdBlock/PAC"];
        if (!src) {
            NSString *appPath = [[NSBundle mainBundle] bundlePath];
            src = [appPath stringByAppendingPathComponent:
                   [NSString stringWithFormat:@"AdBlock/PAC/%@", name]];
        }
        NSString *pac = [NSString stringWithContentsOfFile:src
                                                 encoding:NSUTF8StringEncoding
                                                    error:nil];
        if (!pac) continue;

        NSString *merged = [self mergePAC:pac withDomains:domains isNoFB:[name containsString:@"noFB"]];
        NSString *dst = ABSandboxPACPath(name);
        if ([merged writeToFile:dst atomically:YES
                       encoding:NSUTF8StringEncoding error:nil]) {
            updated++;
        }
    }

    [[NSUserDefaults standardUserDefaults] setObject:[NSDate date] forKey:kABLastRefreshDate];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [self.tableView reloadData];

    [self alert:@"Refreshed"
        message:[NSString stringWithFormat:
                 @"Updated %ld of 4 PACs with %lu fresh domains from "
                 @"StevenBlack. Re-tap \"Generate & install profile\" to "
                 @"apply.",
                 (long)updated, (unsigned long)domains.count]];
}

- (NSString *)mergePAC:(NSString *)pac withDomains:(NSSet *)fresh isNoFB:(BOOL)isNoFB {
    // Locate the bad_da_host_JSON={...} block, parse, union with fresh,
    // re-serialise.
    NSRange r = [pac rangeOfString:@"bad_da_host_JSON={"];
    if (r.location == NSNotFound) return pac;  // leave the PAC as-is

    NSUInteger start = NSMaxRange(r) - 1;  // points at '{'
    NSInteger depth = 0;
    NSUInteger end = start;
    for (NSUInteger i = start; i < pac.length; i++) {
        unichar c = [pac characterAtIndex:i];
        if (c == '{') depth++;
        else if (c == '}') {
            depth--;
            if (depth == 0) { end = i + 1; break; }
        }
    }
    if (end <= start) return pac;

    NSString *jsonText = [pac substringWithRange:NSMakeRange(start, end - start)];
    NSData *jsonData = [jsonText dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *existing = [NSJSONSerialization JSONObjectWithData:jsonData
                                                              options:0
                                                                error:nil];
    NSMutableSet *all = [NSMutableSet setWithArray:existing.allKeys];
    [all unionSet:fresh];
    if (isNoFB) {
        [all removeObject:@"graph.facebook.com"];
        [all removeObject:@"graph.instagram.com"];
    }

    // Serialise deterministically.
    NSArray *sorted = [all.allObjects sortedArrayUsingSelector:@selector(compare:)];
    NSMutableString *out = [NSMutableString stringWithCapacity:sorted.count * 40];
    [out appendString:@"{"];
    for (NSUInteger i = 0; i < sorted.count; i++) {
        if (i > 0) [out appendString:@","];
        [out appendFormat:@"\"%@\":null", sorted[i]];
    }
    [out appendString:@"}"];

    NSMutableString *merged = [pac mutableCopy];
    [merged replaceCharactersInRange:NSMakeRange(start, end - start) withString:out];
    return merged;
}

#pragma mark - Helpers

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
