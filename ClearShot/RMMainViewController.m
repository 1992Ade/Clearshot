#import "RMMainViewController.h"
#import "CSProcessUtils.h"

@interface LSApplicationProxy : NSObject
@property (readonly) NSString *bundleIdentifier;
@property (readonly) NSURL *dataContainerURL;
@end
@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allApplications;
@end

// ============================================================================
// Target descriptor — a label + path(s) + how to clean it.
//
// Historical variants:
//   - plain (directory + globPattern): walk directory, delete files matching
//     the pattern — e.g. *.synced files under CrashReporter/Analytics.
//   - orphanContainers: walk app-container GUIDs, delete the whole folder
//     for any bundleId that isn't installed.
//
// New variants added 2026-11-28:
//   - appSubpath: for each installed user app, walk a per-container subpath
//     (e.g. "Library/Caches" or "tmp") and delete everything inside.
//   - whitelistSubdirs: a parent directory + an array of allow-listed
//     subdirectory names to clean under it. Used for system caches where
//     we only want to zap daemon-specific entries, not the whole dir.
// ============================================================================
@interface RMTarget : NSObject
@property (copy)   NSString *title;
@property (copy)   NSString *footer;
@property (copy)   NSString *directory;          // walked recursively
@property (copy)   NSString *globPattern;        // nil = everything under directory
@property (assign) BOOL     needsRoot;           // use rootSpawn /bin/rm as fallback
@property (assign) BOOL     orphanContainers;    // compare against installed apps
@property (assign) BOOL     appSubpath;          // walk per-app subpath
@property (copy)   NSString *perAppRelative;     // e.g. "Library/Caches"
@property (assign) BOOL     whitelistSubdirs;    // only clean specific subdirs
@property (copy)   NSArray<NSString *> *allowedSubdirs;
@property (assign) unsigned long long scannedBytes;
@property (assign) BOOL     selected;            // UI toggle state
@end
@implementation RMTarget
@end

@interface RMMainViewController ()
@property (strong) NSArray<RMTarget *> *targets;
@property (assign) BOOL scanned;
@property (strong) UILabel *totalLabel;
@end

@implementation RMMainViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Reclaim Space";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;

    self.targets = [self buildTargets];
    for (RMTarget *t in self.targets) t.selected = YES;
}

- (NSArray<RMTarget *> *)buildTargets {
    NSMutableArray *arr = [NSMutableArray array];

    // --- iOS-forgotten log piles ---

    RMTarget *analytics = [RMTarget new];
    analytics.title = @"Analytics panics";
    analytics.footer = @"iOS collects crash diagnostics here but never deletes them.";
    analytics.directory = @"/private/var/mobile/Library/Logs/CrashReporter/Analytics";
    analytics.globPattern = @".synced";  // only *.synced files, iOS leaves these
    analytics.needsRoot = NO;
    [arr addObject:analytics];

    RMTarget *crashes = [RMTarget new];
    crashes.title = @"Crash reports";
    crashes.footer = @"Per-app crash .ips files piled up in DiagnosticReports.";
    crashes.directory = @"/private/var/mobile/Library/Logs/CrashReporter";
    crashes.globPattern = @".synced";
    crashes.needsRoot = NO;
    [arr addObject:crashes];

    RMTarget *support = [RMTarget new];
    support.title = @"AppleSupport / Feedback logs";
    support.footer = @"Logs produced by the Feedback Assistant.";
    support.directory = @"/private/var/mobile/Library/Logs/AppleSupport";
    support.globPattern = nil;
    support.needsRoot = NO;
    [arr addObject:support];

    RMTarget *sysLogs = [RMTarget new];
    sysLogs.title = @"Rotated system logs";
    sysLogs.footer = @"Old /var/log/*.log.* files (needs root — works with setuid(0)).";
    sysLogs.directory = @"/private/var/log";
    sysLogs.globPattern = @".log.";  // only rotated ones
    sysLogs.needsRoot = YES;
    [arr addObject:sysLogs];

    RMTarget *orphans = [RMTarget new];
    orphans.title = @"Orphaned app containers";
    orphans.footer = @"Data left behind by apps that have been uninstalled.";
    orphans.directory = @"/private/var/mobile/Containers/Data/Application";
    orphans.globPattern = nil;
    orphans.needsRoot = NO;
    orphans.orphanContainers = YES;
    [arr addObject:orphans];

    // --- Per-app data piles (what gets listed under Settings → Storage
    //     → "App Data" in a bloated sum) ---

    RMTarget *appCaches = [RMTarget new];
    appCaches.title = @"App caches";
    appCaches.footer = @"Library/Caches of every installed app — apps "
                        @"re-generate these transparently on next use.";
    appCaches.directory = @"/private/var/mobile/Containers/Data/Application";
    appCaches.appSubpath = YES;
    appCaches.perAppRelative = @"Library/Caches";
    [arr addObject:appCaches];

    RMTarget *appTmp = [RMTarget new];
    appTmp.title = @"App tmp";
    appTmp.footer = @"tmp/ of every installed app (iOS is supposed to clean "
                     @"these on launch; it often doesn't).";
    appTmp.directory = @"/private/var/mobile/Containers/Data/Application";
    appTmp.appSubpath = YES;
    appTmp.perAppRelative = @"tmp";
    [arr addObject:appTmp];

    // --- System-wide caches (what makes "Système" balloon in Storage) ---

    RMTarget *systemCaches = [RMTarget new];
    systemCaches.title = @"System caches";
    systemCaches.footer = @"System-wide Apple caches — safe subset only "
                           @"(skip Spotlight, Photo thumbnails, Messages).";
    systemCaches.directory = @"/private/var/mobile/Library/Caches";
    systemCaches.whitelistSubdirs = YES;
    systemCaches.allowedSubdirs = @[
        @"com.apple.icloud.searchpartyuseragent",
        @"com.apple.dyld",
        @"com.apple.LinkPresentation",
        @"com.apple.AppStore",
        @"com.apple.newsd",
        @"com.apple.VideoSubscriberAccount",
        @"com.apple.icloud.fmfd",
    ];
    [arr addObject:systemCaches];

    RMTarget *daemonCaches = [RMTarget new];
    daemonCaches.title = @"Daemon caches (safe)";
    daemonCaches.footer = @"WebKit / nsurlsessiond / Suggestions / CloudKit. "
                           @"Daemons re-build these automatically.";
    daemonCaches.directory = @"/private/var/mobile/Library/Caches";
    daemonCaches.whitelistSubdirs = YES;
    daemonCaches.allowedSubdirs = @[
        @"com.apple.WebKit.Networking",
        @"com.apple.WebKit.WebContent",
        @"com.apple.WebKit.GPU",
        @"com.apple.nsurlsessiond",
        @"com.apple.suggestions",
        @"CloudKit",
    ];
    [arr addObject:daemonCaches];

    return arr;
}

#pragma mark - Table

// 0: Scan button + preamble
// 1: targets
// 2: Reclaim button

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    if (s == 1) return self.targets.count;
    return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 1) return @"Targets";
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"iOS 14+ clears many of its own caches on demand — most "
               @"\"cleanup\" tools are placebo. These five targets are the "
               @"ones iOS actually leaves lying around: analytics panics, "
               @"crash reports, support logs, rotated system logs, and "
               @"containers from uninstalled apps.";
    }
    if (s == 1) {
        if (!self.scanned) return @"Tap Scan to see how much each target currently holds.";
        return @"Toggle what you want to purge, then tap Reclaim.";
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
        cell.textLabel.text = self.scanned ? @"Rescan" : @"Scan";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;

    } else if (ip.section == 1) {
        RMTarget *t = self.targets[ip.row];
        cell.textLabel.text = t.title;
        cell.detailTextLabel.text = t.footer;
        cell.detailTextLabel.numberOfLines = 0;

        if (self.scanned) {
            UILabel *size = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 100, 44)];
            size.text = [self humanBytes:t.scannedBytes];
            size.textColor = [UIColor systemGreenColor];
            size.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightSemibold];
            size.textAlignment = NSTextAlignmentRight;
            UIView *wrap = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 150, 44)];
            [wrap addSubview:size];
            UISwitch *sw = [[UISwitch alloc] init];
            sw.on = t.selected;
            sw.tag = ip.row;
            [sw addTarget:self action:@selector(toggleTarget:)
                 forControlEvents:UIControlEventValueChanged];
            sw.frame = CGRectMake(100, (44 - sw.frame.size.height) / 2,
                                  sw.frame.size.width, sw.frame.size.height);
            [wrap addSubview:sw];
            cell.accessoryView = wrap;
        }
        cell.selectionStyle = UITableViewCellSelectionStyleNone;

    } else {
        cell.textLabel.text = self.scanned
            ? [NSString stringWithFormat:@"Reclaim %@", [self humanBytes:[self selectedTotal]]]
            : @"Scan first";
        cell.textLabel.textColor = self.scanned
            ? [UIColor systemGreenColor] : [UIColor systemGrayColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) [self doScan];
    else if (ip.section == 2 && self.scanned) [self doReclaim];
}

- (void)toggleTarget:(UISwitch *)sw {
    self.targets[sw.tag].selected = sw.on;
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:2]
                  withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Scan

- (unsigned long long)selectedTotal {
    unsigned long long total = 0;
    for (RMTarget *t in self.targets) if (t.selected) total += t.scannedBytes;
    return total;
}

- (void)doScan {
    UIAlertController *progress = [UIAlertController
        alertControllerWithTitle:@"Scanning"
                         message:@"Walking filesystem…"
                  preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progress animated:YES completion:nil];

    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        for (RMTarget *t in self.targets) {
            t.scannedBytes = [self scanTarget:t];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [progress dismissViewControllerAnimated:YES completion:^{
                self.scanned = YES;
                [self.tableView reloadData];
            }];
        });
    });
}

- (unsigned long long)scanTarget:(RMTarget *)t {
    if (t.orphanContainers)   return [self scanOrphanedContainers:t.directory];
    if (t.appSubpath)         return [self scanAppSubpath:t.directory
                                              perAppRelative:t.perAppRelative];
    if (t.whitelistSubdirs)   return [self scanWhitelistedSubdirs:t.directory
                                                              names:t.allowedSubdirs];
    return [self scanDirectory:t.directory pattern:t.globPattern];
}

- (unsigned long long)scanDirectory:(NSString *)dir pattern:(NSString *)pattern {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:dir];
    unsigned long long total = 0;
    NSString *rel;
    while ((rel = [e nextObject])) {
        if (pattern && ![rel containsString:pattern]) continue;
        NSString *full = [dir stringByAppendingPathComponent:rel];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        if ([attrs[NSFileType] isEqualToString:NSFileTypeRegular]) {
            total += [attrs[NSFileSize] unsignedLongLongValue];
        }
    }
    return total;
}

- (unsigned long long)scanOrphanedContainers:(NSString *)containersDir {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSSet *installedBundles = [self installedBundleIDs];
    // Containers are named by GUID; the actual bundleIdentifier lives in each
    // container's .com.apple.mobile_container_manager.metadata.plist.
    NSArray *guids = [fm contentsOfDirectoryAtPath:containersDir error:nil];
    unsigned long long total = 0;
    for (NSString *guid in guids) {
        NSString *containerPath = [containersDir stringByAppendingPathComponent:guid];
        NSString *metaPath = [containerPath stringByAppendingPathComponent:
                              @".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        if (bid && ![installedBundles containsObject:bid]) {
            total += [self scanDirectory:containerPath pattern:nil];
        }
    }
    return total;
}

- (NSSet *)installedBundleIDs {
    NSMutableSet *s = [NSMutableSet set];
    Class wsClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!wsClass) return s;
    id ws = [wsClass performSelector:@selector(defaultWorkspace)];
    NSArray *apps = [ws performSelector:@selector(allApplications)];
    for (id app in apps) {
        NSString *bid = [app performSelector:@selector(bundleIdentifier)];
        if (bid) [s addObject:bid];
    }
    return s;
}

#pragma mark - App-subpath (Library/Caches, tmp, …)

- (unsigned long long)scanAppSubpath:(NSString *)containersDir
                        perAppRelative:(NSString *)relPath {
    // For every installed app's data container, size up <container>/<relPath>.
    NSFileManager *fm = [NSFileManager defaultManager];
    NSSet *installed = [self installedBundleIDs];
    NSArray *guids = [fm contentsOfDirectoryAtPath:containersDir error:nil];
    unsigned long long total = 0;
    for (NSString *guid in guids) {
        NSString *containerPath = [containersDir stringByAppendingPathComponent:guid];
        NSString *metaPath = [containerPath stringByAppendingPathComponent:
                              @".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        // Only count containers whose app is still installed — orphans are
        // handled by the dedicated "Orphaned app containers" target.
        if (!bid || ![installed containsObject:bid]) continue;
        NSString *subPath = [containerPath stringByAppendingPathComponent:relPath];
        total += [self scanDirectory:subPath pattern:nil];
    }
    return total;
}

#pragma mark - Whitelisted subdirs under a parent

- (unsigned long long)scanWhitelistedSubdirs:(NSString *)parent
                                         names:(NSArray<NSString *> *)names {
    NSFileManager *fm = [NSFileManager defaultManager];
    unsigned long long total = 0;
    for (NSString *name in names) {
        NSString *path = [parent stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:path]) {
            total += [self scanDirectory:path pattern:nil];
        }
    }
    return total;
}

#pragma mark - Reclaim

- (void)doReclaim {
    unsigned long long total = [self selectedTotal];
    NSString *msg = [NSString stringWithFormat:
        @"About to delete %@ across %ld categories. Continue?",
        [self humanBytes:total],
        (long)[[self.targets valueForKeyPath:@"@sum.selected"] integerValue]];
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Reclaim space"
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Reclaim"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [self performReclaim];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)performReclaim {
    unsigned long long freed = 0;
    NSUInteger failures = 0;
    for (RMTarget *t in self.targets) {
        if (!t.selected) continue;
        unsigned long long before = t.scannedBytes;
        failures += [self cleanTarget:t];
        unsigned long long after = [self scanTarget:t];
        freed += (before > after) ? (before - after) : 0;
        t.scannedBytes = after;
    }
    [self.tableView reloadData];
    NSString *msg = [NSString stringWithFormat:@"Freed %@. Thanks for cleaning up.",
                     [self humanBytes:freed]];
    if (failures > 0) {
        msg = [msg stringByAppendingFormat:@"\n\n(%lu files couldn't be deleted — "
                                             @"see About Device → Diagnostics.)",
               (unsigned long)failures];
    }
    [self alert:@"Done" message:msg];
}

// Returns the number of files that failed to delete so we can report back to
// the user instead of pretending everything went fine.
- (NSUInteger)cleanTarget:(RMTarget *)t {
    if (t.orphanContainers)  return [self cleanOrphanedContainers:t];
    if (t.appSubpath)        return [self cleanAppSubpath:t];
    if (t.whitelistSubdirs)  return [self cleanWhitelistedSubdirs:t];
    return [self cleanPlainDirectory:t];
}

- (NSUInteger)cleanOrphanedContainers:(RMTarget *)t {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSSet *installed = [self installedBundleIDs];
    NSArray *guids = [fm contentsOfDirectoryAtPath:t.directory error:nil];
    NSUInteger fails = 0;
    for (NSString *guid in guids) {
        NSString *path = [t.directory stringByAppendingPathComponent:guid];
        NSString *metaPath = [path stringByAppendingPathComponent:
                              @".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        if (bid && ![installed containsObject:bid]) {
            NSError *err = nil;
            if (![fm removeItemAtPath:path error:&err]) {
                NSLog(@"[TrollBox/Reclaim] orphan rm %@ err=%@", path, err);
                fails++;
            }
        }
    }
    return fails;
}

- (NSUInteger)cleanPlainDirectory:(RMTarget *)t {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:t.directory];
    NSString *rel;
    NSUInteger fails = 0;
    while ((rel = [e nextObject])) {
        if (t.globPattern && ![rel containsString:t.globPattern]) continue;
        NSString *full = [t.directory stringByAppendingPathComponent:rel];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        if (![attrs[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
        if (![self deleteFile:full needsRoot:t.needsRoot]) fails++;
    }
    return fails;
}

- (NSUInteger)cleanAppSubpath:(RMTarget *)t {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSSet *installed = [self installedBundleIDs];
    NSArray *guids = [fm contentsOfDirectoryAtPath:t.directory error:nil];
    NSUInteger fails = 0;
    for (NSString *guid in guids) {
        NSString *containerPath = [t.directory stringByAppendingPathComponent:guid];
        NSString *metaPath = [containerPath stringByAppendingPathComponent:
                              @".com.apple.mobile_container_manager.metadata.plist"];
        NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
        NSString *bid = meta[@"MCMMetadataIdentifier"];
        if (!bid || ![installed containsObject:bid]) continue;
        NSString *subPath = [containerPath stringByAppendingPathComponent:t.perAppRelative];
        fails += [self deleteContentsOfDirectory:subPath needsRoot:NO];
    }
    return fails;
}

- (NSUInteger)cleanWhitelistedSubdirs:(RMTarget *)t {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSUInteger fails = 0;
    for (NSString *name in t.allowedSubdirs) {
        NSString *path = [t.directory stringByAppendingPathComponent:name];
        if ([fm fileExistsAtPath:path]) {
            fails += [self deleteContentsOfDirectory:path needsRoot:NO];
        }
    }
    return fails;
}

// Deletes the children of `dir` but keeps the dir itself so iOS doesn't
// recreate it empty during the next operation.
- (NSUInteger)deleteContentsOfDirectory:(NSString *)dir needsRoot:(BOOL)needsRoot {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *children = [fm contentsOfDirectoryAtPath:dir error:nil];
    NSUInteger fails = 0;
    for (NSString *name in children) {
        NSString *full = [dir stringByAppendingPathComponent:name];
        if (![self deleteFile:full needsRoot:needsRoot]) fails++;
    }
    return fails;
}

// Common delete path with error capture + rootSpawn fallback.
- (BOOL)deleteFile:(NSString *)path needsRoot:(BOOL)needsRoot {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    if ([fm removeItemAtPath:path error:&err]) return YES;
    // If the file is root-owned and setuid(0) didn't elevate, fall back to
    // rootSpawn /bin/rm to force it.
    if (needsRoot || [err.domain isEqualToString:NSCocoaErrorDomain]) {
        int rc = [CSProcessUtils rootSpawn:@"/bin/rm" args:@[@"-rf", path]
                                    stdOut:NULL stdErr:NULL];
        if (rc == 0) return YES;
        NSLog(@"[TrollBox/Reclaim] rm %@ err=%@ (rootSpawn rc=%d)", path, err, rc);
    } else {
        NSLog(@"[TrollBox/Reclaim] rm %@ err=%@", path, err);
    }
    return NO;
}

#pragma mark - Helpers

- (NSString *)humanBytes:(unsigned long long)bytes {
    NSByteCountFormatter *f = [[NSByteCountFormatter alloc] init];
    f.countStyle = NSByteCountFormatterCountStyleBinary;
    return [f stringFromByteCount:(long long)bytes];
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
