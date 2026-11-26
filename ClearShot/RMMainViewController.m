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
// Target descriptor — a label + path(s) + whether it needs rootSpawn to clean.
// ============================================================================
@interface RMTarget : NSObject
@property (copy) NSString *title;
@property (copy) NSString *footer;
@property (copy) NSString *directory;       // walked recursively
@property (copy) NSString *globPattern;     // nil = everything under directory
@property (assign) BOOL needsRoot;          // use rootSpawn /bin/rm
@property (assign) BOOL orphanContainers;   // special: compare against installed apps
@property (assign) unsigned long long scannedBytes;
@property (assign) BOOL selected;           // UI toggle state
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
    sysLogs.footer = @"Old /var/log/*.log.* files (requires rootSpawn to delete).";
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
            if (t.orphanContainers) {
                t.scannedBytes = [self scanOrphanedContainers:t.directory];
            } else {
                t.scannedBytes = [self scanDirectory:t.directory pattern:t.globPattern];
            }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            [progress dismissViewControllerAnimated:YES completion:^{
                self.scanned = YES;
                [self.tableView reloadData];
            }];
        });
    });
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
    for (RMTarget *t in self.targets) {
        if (!t.selected) continue;
        unsigned long long before = t.scannedBytes;
        [self cleanTarget:t];
        // Re-scan to measure what's actually gone.
        unsigned long long after = t.orphanContainers
            ? [self scanOrphanedContainers:t.directory]
            : [self scanDirectory:t.directory pattern:t.globPattern];
        freed += (before > after) ? (before - after) : 0;
        t.scannedBytes = after;
    }
    [self.tableView reloadData];
    [self alert:@"Done"
        message:[NSString stringWithFormat:@"Freed %@. Thanks for cleaning up.",
                 [self humanBytes:freed]]];
}

- (void)cleanTarget:(RMTarget *)t {
    if (t.orphanContainers) {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSSet *installed = [self installedBundleIDs];
        NSArray *guids = [fm contentsOfDirectoryAtPath:t.directory error:nil];
        for (NSString *guid in guids) {
            NSString *path = [t.directory stringByAppendingPathComponent:guid];
            NSString *metaPath = [path stringByAppendingPathComponent:
                                  @".com.apple.mobile_container_manager.metadata.plist"];
            NSDictionary *meta = [NSDictionary dictionaryWithContentsOfFile:metaPath];
            NSString *bid = meta[@"MCMMetadataIdentifier"];
            if (bid && ![installed containsObject:bid]) {
                [fm removeItemAtPath:path error:nil];
            }
        }
        return;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSDirectoryEnumerator *e = [fm enumeratorAtPath:t.directory];
    NSString *rel;
    while ((rel = [e nextObject])) {
        if (t.globPattern && ![rel containsString:t.globPattern]) continue;
        NSString *full = [t.directory stringByAppendingPathComponent:rel];
        NSDictionary *attrs = [fm attributesOfItemAtPath:full error:nil];
        if (![attrs[NSFileType] isEqualToString:NSFileTypeRegular]) continue;
        if (t.needsRoot) {
            [CSProcessUtils rootSpawn:@"/bin/rm" args:@[@"-f", full]
                               stdOut:NULL stdErr:NULL];
        } else {
            [fm removeItemAtPath:full error:nil];
        }
    }
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
