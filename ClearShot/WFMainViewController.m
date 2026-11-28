#import "WFMainViewController.h"
#import <Security/Security.h>
#import <SystemConfiguration/CaptiveNetwork.h>

// ============================================================================
// Known-network plist paths. iOS stores WiFi credentials in BOTH a plist
// (SSIDs, last-join dates, autojoin flag) and the Keychain (passwords).
// ============================================================================
static NSString * const kWiFiPlistLegacy =
    @"/var/preferences/SystemConfiguration/com.apple.wifi.plist";
static NSString * const kWiFiPlistiOS15  =
    @"/var/preferences/com.apple.wifi-known-networks.plist";

// ============================================================================
// Model
// ============================================================================
@interface WFNetwork : NSObject
@property (copy) NSString *ssid;
@property (copy) NSString *security;         // "WPA2", "WPA3", "Open", …
@property (strong) NSDate  *lastJoined;      // nil if unknown
@property (assign) BOOL autoJoin;
@property (copy) NSString *bssid;            // if known
@property (copy) NSDictionary *rawEntry;     // for re-writing on delete
@end
@implementation WFNetwork
@end

// ============================================================================

@interface WFMainViewController () <UITableViewDataSource, UITableViewDelegate,
                                      UISearchBarDelegate>
@property (strong, nonatomic) UITableView *table;
@property (strong, nonatomic) UISearchBar *searchBar;
@property (strong, nonatomic) NSString *plistPath;       // whichever worked
@property (strong, nonatomic) NSMutableDictionary *plistRoot;
@property (strong, nonatomic) NSArray<WFNetwork *> *allNetworks;
@property (strong, nonatomic) NSArray<WFNetwork *> *filteredNetworks;
@property (copy, nonatomic)   NSString *currentSSID;     // active connection
@end

@implementation WFMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"Saved WiFi";

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction
                                                       target:self
                                                       action:@selector(didTapExport)];

    self.searchBar = [[UISearchBar alloc] init];
    self.searchBar.placeholder = @"Search SSID…";
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.delegate = self;
    [self.searchBar sizeToFit];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds
                                              style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = self.view.backgroundColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    self.table.tableHeaderView = self.searchBar;
    [self.view addSubview:self.table];

    [self loadKnownNetworks];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self loadKnownNetworks];
    [self.table reloadData];
}

#pragma mark - Loading

- (void)loadKnownNetworks {
    self.currentSSID = [self readCurrentSSID];

    NSString *path = nil;
    NSMutableDictionary *root = nil;
    NSFileManager *fm = [NSFileManager defaultManager];

    if ([fm fileExistsAtPath:kWiFiPlistiOS15]) {
        path = kWiFiPlistiOS15;
        root = [[NSMutableDictionary alloc]
                initWithContentsOfFile:kWiFiPlistiOS15];
    }
    if (!root && [fm fileExistsAtPath:kWiFiPlistLegacy]) {
        path = kWiFiPlistLegacy;
        root = [[NSMutableDictionary alloc]
                initWithContentsOfFile:kWiFiPlistLegacy];
    }
    self.plistPath = path;
    self.plistRoot = root ?: [NSMutableDictionary dictionary];

    NSArray *list = root[@"List of known networks"];        // iOS 11-14 shape
    if (![list isKindOfClass:[NSArray class]]) {
        list = root[@"KnownNetworks"];                      // iOS 15 shape
    }
    if (![list isKindOfClass:[NSArray class]]) list = @[];

    NSMutableArray *nets = [NSMutableArray array];
    for (id entry in list) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = (NSDictionary *)entry;
        WFNetwork *n = [WFNetwork new];
        n.ssid     = d[@"SSID_STR"] ?: d[@"ssid"] ?: d[@"SSID"];
        n.security = d[@"WPA_SECURITY"] ?: d[@"CaptureNetworkInfo"][@"Security"]
                                         ?: ([d[@"WEPKey"] length] ? @"WEP" : @"Open");
        n.bssid    = d[@"BSSID"] ?: d[@"bssid"];
        n.autoJoin = ![d[@"disabled"] boolValue] && ![d[@"AutoJoinDisabled"] boolValue];
        id joinedAt = d[@"lastJoined"] ?: d[@"lastAssociatedAt"]
                                        ?: d[@"LastAssociatedAt"];
        if ([joinedAt isKindOfClass:[NSDate class]]) n.lastJoined = joinedAt;
        n.rawEntry = d;
        if (n.ssid.length) [nets addObject:n];
    }

    // Sort by most-recently joined first; nil dates at the end.
    [nets sortUsingComparator:^NSComparisonResult(WFNetwork *a, WFNetwork *b) {
        if (a.lastJoined && b.lastJoined) return [b.lastJoined compare:a.lastJoined];
        if (a.lastJoined) return NSOrderedAscending;
        if (b.lastJoined) return NSOrderedDescending;
        return [a.ssid caseInsensitiveCompare:b.ssid];
    }];
    self.allNetworks = nets;
    self.filteredNetworks = nets;
}

- (NSString *)readCurrentSSID {
    // CNCopyCurrentNetworkInfo is deprecated in public use but still works
    // for us because we carry com.apple.wifi.* entitlements.
    CFArrayRef ifs = CNCopySupportedInterfaces();
    NSString *ssid = nil;
    if (ifs) {
        for (CFIndex i = 0, c = CFArrayGetCount(ifs); i < c; i++) {
            CFStringRef name = CFArrayGetValueAtIndex(ifs, i);
            CFDictionaryRef info = CNCopyCurrentNetworkInfo(name);
            if (info) {
                NSString *s = (__bridge NSString *)
                              CFDictionaryGetValue(info, kCNNetworkInfoKeySSID);
                if (s.length) { ssid = [s copy]; }
                CFRelease(info);
            }
            if (ssid) break;
        }
        CFRelease(ifs);
    }
    return ssid;
}

#pragma mark - Keychain password reveal

- (NSString *)passwordForSSID:(NSString *)ssid {
    // iOS stores the WPA PSK under the "AirPort" service with the SSID
    // as account. Needs the keychain-access group entitlement bundled
    // with our TrollStore entitlements. Returns nil if not found.
    NSDictionary *q = @{
        (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:      @"AirPort",
        (__bridge id)kSecAttrAccount:      ssid ?: @"",
        (__bridge id)kSecReturnData:       @YES,
        (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (st == errSecSuccess && result) {
        NSString *pw = [[NSString alloc] initWithData:(__bridge_transfer NSData *)result
                                             encoding:NSUTF8StringEncoding];
        return pw;
    }
    return nil;
}

#pragma mark - Forget / delete

- (BOOL)forgetNetwork:(WFNetwork *)net error:(NSError **)err {
    if (!self.plistPath) {
        if (err) *err = [NSError errorWithDomain:@"TrollBox" code:1 userInfo:
            @{NSLocalizedDescriptionKey:@"No known-networks plist path resolved."}];
        return NO;
    }
    NSString *key = self.plistRoot[@"List of known networks"] ? @"List of known networks"
                                                               : @"KnownNetworks";
    NSMutableArray *list = [self.plistRoot[key] mutableCopy];
    [list removeObject:net.rawEntry];
    self.plistRoot[key] = list;

    BOOL ok = [self.plistRoot writeToURL:[NSURL fileURLWithPath:self.plistPath]
                                   error:err];
    if (!ok) return NO;
    [self loadKnownNetworks];
    return YES;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv {
    return self.currentSSID.length ? 2 : 1;
}

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (self.currentSSID.length && s == 0) return 1;
    return self.filteredNetworks.count ?: 1;   // "no networks" placeholder
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (self.currentSSID.length && s == 0) return @"Currently connected";
    return [NSString stringWithFormat:@"Saved networks (%lu)",
            (unsigned long)self.filteredNetworks.count];
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    NSInteger savedSection = self.currentSSID.length ? 1 : 0;
    if (s == savedSection) {
        return @"Tap a network to reveal its password (if stored) or copy it. "
               @"Swipe left to forget.\n\n"
               @"⚠ If iCloud Keychain is on, forgotten networks may resync "
               @"from your other Apple devices within a few hours.";
    }
    return nil;
}

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    static NSString *kId = @"c";
    UITableViewCell *cell = [tv dequeueReusableCellWithIdentifier:kId];
    if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                             reuseIdentifier:kId];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.accessoryType = UITableViewCellAccessoryNone;

    if (self.currentSSID.length && ip.section == 0) {
        cell.textLabel.text = self.currentSSID;
        cell.detailTextLabel.text = @"🟢 Connected now";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (self.filteredNetworks.count == 0) {
        cell.textLabel.text = @"No saved networks yet";
        cell.detailTextLabel.text = nil;
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    WFNetwork *n = self.filteredNetworks[ip.row];
    cell.textLabel.text = n.ssid;
    NSMutableString *sub = [NSMutableString string];
    [sub appendString:(n.security.length ? n.security : @"?")];
    if (n.lastJoined) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterShortStyle;
        fmt.timeStyle = NSDateFormatterNoStyle;
        [sub appendFormat:@" · last %@", [fmt stringFromDate:n.lastJoined]];
    }
    if (!n.autoJoin) [sub appendString:@" · auto-join off"];
    cell.detailTextLabel.text = sub;
    cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
    cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    NSInteger savedSection = self.currentSSID.length ? 1 : 0;
    if (ip.section != savedSection) return;
    if (self.filteredNetworks.count == 0) return;
    [self revealNetwork:self.filteredNetworks[ip.row]];
}

// Separate accessory tap = same action here for clarity.
- (void)tableView:(UITableView *)tv accessoryButtonTappedForRowWithIndexPath:(NSIndexPath *)ip {
    NSInteger savedSection = self.currentSSID.length ? 1 : 0;
    if (ip.section != savedSection) return;
    if (self.filteredNetworks.count == 0) return;
    [self revealNetwork:self.filteredNetworks[ip.row]];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    NSInteger savedSection = self.currentSSID.length ? 1 : 0;
    return ip.section == savedSection && self.filteredNetworks.count > 0;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
  trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    WFNetwork *n = self.filteredNetworks[ip.row];
    UIContextualAction *forget =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                 title:@"Forget"
                                               handler:^(UIContextualAction *a, UIView *v,
                                                         void (^completion)(BOOL)) {
        NSError *err = nil;
        BOOL ok = [self forgetNetwork:n error:&err];
        if (!ok) {
            [self alert:@"Forget failed"
                message:err.localizedDescription ?: @"unknown"];
        }
        [self.table reloadData];
        completion(ok);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[forget]];
}

#pragma mark - Reveal sheet

- (void)revealNetwork:(WFNetwork *)n {
    NSString *pw = [self passwordForSSID:n.ssid];
    NSMutableString *body = [NSMutableString string];
    [body appendFormat:@"SSID: %@\n", n.ssid];
    [body appendFormat:@"Security: %@\n", n.security ?: @"?"];
    if (n.bssid.length) [body appendFormat:@"BSSID: %@\n", n.bssid];
    if (n.lastJoined) {
        NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
        fmt.dateStyle = NSDateFormatterMediumStyle;
        fmt.timeStyle = NSDateFormatterShortStyle;
        [body appendFormat:@"Last joined: %@\n", [fmt stringFromDate:n.lastJoined]];
    }
    [body appendFormat:@"Auto-join: %@\n", n.autoJoin ? @"Yes" : @"No"];
    [body appendString:@"\n"];
    [body appendString:(pw.length ? [NSString stringWithFormat:@"Password: %@", pw]
                                  : @"Password: (not retrievable)")];

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:n.ssid
                              message:body
                              preferredStyle:UIAlertControllerStyleAlert];
    if (pw.length) {
        [ac addAction:[UIAlertAction actionWithTitle:@"Copy password"
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            [UIPasteboard generalPasteboard].string = pw;
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Copy SSID"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [UIPasteboard generalPasteboard].string = n.ssid;
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Close"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Search

- (void)searchBar:(UISearchBar *)sb textDidChange:(NSString *)txt {
    if (txt.length == 0) {
        self.filteredNetworks = self.allNetworks;
    } else {
        NSPredicate *p = [NSPredicate predicateWithFormat:@"ssid CONTAINS[cd] %@", txt];
        self.filteredNetworks = [self.allNetworks filteredArrayUsingPredicate:p];
    }
    [self.table reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)sb { [sb resignFirstResponder]; }

#pragma mark - Export CSV

- (void)didTapExport {
    NSMutableString *csv = [NSMutableString stringWithString:
                              @"SSID,Security,LastJoined,AutoJoin,BSSID,Password\n"];
    NSDateFormatter *fmt = [[NSDateFormatter alloc] init];
    fmt.dateFormat = @"yyyy-MM-dd HH:mm:ss";
    for (WFNetwork *n in self.allNetworks) {
        NSString *pw = [self passwordForSSID:n.ssid] ?: @"";
        NSString *last = n.lastJoined ? [fmt stringFromDate:n.lastJoined] : @"";
        [csv appendFormat:@"\"%@\",%@,%@,%@,%@,\"%@\"\n",
         [n.ssid stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""],
         n.security ?: @"",
         last,
         n.autoJoin ? @"YES" : @"NO",
         n.bssid ?: @"",
         [pw stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
    }

    NSString *tmp = [NSTemporaryDirectory() stringByAppendingPathComponent:
                      @"trollbox-wifi.csv"];
    [csv writeToFile:tmp atomically:YES encoding:NSUTF8StringEncoding error:nil];
    NSURL *url = [NSURL fileURLWithPath:tmp];
    UIActivityViewController *av =
        [[UIActivityViewController alloc] initWithActivityItems:@[url]
                                         applicationActivities:nil];
    av.popoverPresentationController.barButtonItem = self.navigationItem.rightBarButtonItem;
    [self presentViewController:av animated:YES completion:nil];
}

#pragma mark - Alert helper

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
