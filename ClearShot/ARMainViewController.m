#import "ARMainViewController.h"
#import <SystemConfiguration/SystemConfiguration.h>

// ============================================================================
// Private StoreKit UI classes (StoreKitUI.framework). Same signatures as
// Muffinstore's MFSRootViewController. Entitlement needed:
// com.apple.itunesstored.private.
// ============================================================================
@interface SKUIItemStateCenter : NSObject
+ (id)defaultCenter;
- (id)_newPurchasesWithItems:(id)items;
- (void)_performPurchases:(id)purchases
         hasBundlePurchase:(BOOL)purchase
         withClientContext:(id)context
           completionBlock:(id)block;
@end
@interface SKUIItem : NSObject
- (id)initWithLookupDictionary:(id)dict;
@end
@interface SKUIItemOffer : NSObject
- (id)initWithLookupDictionary:(id)dict;
@end
@interface SKUIClientContext : NSObject
+ (id)defaultContext;
@end

@interface LSApplicationProxy : NSObject
+ (instancetype)applicationProxyForIdentifier:(NSString*)identifier;
@property (readonly) NSString *bundleIdentifier;
@property (readonly) NSString *localizedName;
@end
@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allApplications;
@end

@interface ARMainViewController ()
@property (strong) NSArray *installedApps;
@property (strong) UIAlertController *progressAlert;
@end

@implementation ARMainViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"AppRepack";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    [self loadInstalledApps];
}

- (void)loadInstalledApps {
    Class ws = NSClassFromString(@"LSApplicationWorkspace");
    if (!ws) { self.installedApps = @[]; return; }
    id workspace = [ws performSelector:@selector(defaultWorkspace)];
    NSArray *apps = [workspace performSelector:@selector(allApplications)];
    NSMutableArray *user = [NSMutableArray array];
    for (id a in apps) {
        NSString *type = [a performSelector:@selector(applicationType)];
        if (![type isEqualToString:@"User"]) continue;
        [user addObject:a];
    }
    [user sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *na = [a performSelector:@selector(localizedName)];
        NSString *nb = [b performSelector:@selector(localizedName)];
        return [na localizedCaseInsensitiveCompare:nb];
    }];
    self.installedApps = user;
}

#pragma mark - Table

// 0: preamble + "Download from AppStore URL" button
// 1: installed apps (pick one, we look up its versions)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;
    return MAX((NSInteger)self.installedApps.count, 1);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    return s == 1 ? @"Installed apps" : @"Start from AppStore URL";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"Port of Muffinstore (github.com/mineek/muffinstore). Uses "
               @"iOS's native Store download flow (SKUIItemStateCenter) to "
               @"fetch an older version of an app that works on this iOS. "
               @"Your Apple ID session already active on this device handles "
               @"authentication — TrollBox never sees your password. "
               @"Version history from apis.bilin.eu.org.";
    }
    if (s == 1) return @"Tap an installed app to pick an older compatible version.";
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
        cell.textLabel.text = @"Enter AppStore URL…";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;

    } else {
        if (self.installedApps.count == 0) {
            cell.textLabel.text = @"No user apps installed";
            cell.textLabel.textColor = [UIColor lightGrayColor];
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            id app = self.installedApps[ip.row];
            cell.textLabel.text = [app performSelector:@selector(localizedName)];
            cell.detailTextLabel.text = [app performSelector:@selector(bundleIdentifier)];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) { [self promptForURL]; return; }
    if (self.installedApps.count == 0) return;
    id app = self.installedApps[ip.row];
    NSString *bid = [app performSelector:@selector(bundleIdentifier)];
    [self lookupBundleID:bid];
}

#pragma mark - Flow

- (void)promptForURL {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"AppStore URL"
                         message:@"Paste the App Store link to the app you "
                                 @"want an older version of."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"https://apps.apple.com/app/idXXXXXXXXX";
        f.autocapitalizationType = UITextAutocapitalizationTypeNone;
        f.autocorrectionType = UITextAutocorrectionTypeNo;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Continue"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSString *link = ac.textFields.firstObject.text;
        long long trackId = [self parseTrackIdFromURL:link];
        if (trackId == 0) {
            [self alert:@"Invalid link" message:@"Couldn't find an id parameter."];
            return;
        }
        [self fetchVersionsForTrackId:trackId];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (long long)parseTrackIdFromURL:(NSString *)link {
    NSRange r = [link rangeOfString:@"/id"];
    if (r.location == NSNotFound) return 0;
    NSString *tail = [link substringFromIndex:NSMaxRange(r)];
    long long val = [tail longLongValue];
    return val;
}

- (void)lookupBundleID:(NSString *)bid {
    [self showProgress:@"Looking up on iTunes…"];
    NSString *urlStr = [NSString stringWithFormat:
        @"https://itunes.apple.com/lookup?bundleId=%@&limit=1&media=software", bid];
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr]
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissProgressAnimated:YES completion:^{
                    if (err || !data) {
                        [self alert:@"Lookup failed"
                            message:err.localizedDescription ?: @"empty response"];
                        return;
                    }
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                          options:0 error:nil];
                    NSArray *results = json[@"results"];
                    if (results.count == 0) {
                        [self alert:@"No match"
                            message:@"iTunes doesn't know this bundle ID."];
                        return;
                    }
                    long long trackId = [results.firstObject[@"trackId"] longLongValue];
                    [self fetchVersionsForTrackId:trackId];
                }];
            });
        }];
    [t resume];
}

- (void)fetchVersionsForTrackId:(long long)trackId {
    [self showProgress:@"Fetching version history…"];
    NSString *urlStr = [NSString stringWithFormat:
        @"https://apis.bilin.eu.org/history/%lld", trackId];
    NSURLSessionDataTask *t = [[NSURLSession sharedSession] dataTaskWithURL:[NSURL URLWithString:urlStr]
        completionHandler:^(NSData *data, NSURLResponse *r, NSError *err) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self dismissProgressAnimated:YES completion:^{
                    if (err || !data) {
                        [self promptManualVersionId:trackId
                                         withError:err.localizedDescription];
                        return;
                    }
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data
                                                                          options:0 error:nil];
                    NSArray *versions = json[@"data"];
                    if (versions.count == 0) {
                        [self promptManualVersionId:trackId
                                         withError:@"No records for this app on bilin.eu.org."];
                        return;
                    }
                    [self presentVersionPickerForTrackId:trackId versions:versions];
                }];
            });
        }];
    [t resume];
}

- (void)presentVersionPickerForTrackId:(long long)trackId versions:(NSArray *)versions {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:@"Pick a version"
                         message:[NSString stringWithFormat:@"%lu versions in catalog",
                                  (unsigned long)versions.count]
                  preferredStyle:UIAlertControllerStyleActionSheet];
    // Show the most recent 10 inline; for more, offer a manual entry.
    NSInteger n = MIN((NSInteger)versions.count, 10);
    for (NSInteger i = versions.count - 1, k = 0; i >= 0 && k < n; i--, k++) {
        NSDictionary *v = versions[i];
        NSString *title = [NSString stringWithFormat:@"%@ (id %@)",
                           v[@"bundle_version"] ?: @"?",
                           v[@"external_identifier"] ?: @"?"];
        [ac addAction:[UIAlertAction actionWithTitle:title
                                               style:UIAlertActionStyleDefault
                                             handler:^(UIAlertAction *a) {
            long long vid = [v[@"external_identifier"] longLongValue];
            [self downloadTrack:trackId version:vid];
        }]];
    }
    [ac addAction:[UIAlertAction actionWithTitle:@"Enter version ID…"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [self promptManualVersionId:trackId withError:nil];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Latest compatible (iOS picks)"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        // Passing 0 as the version id means: let Apple's Store server pick
        // the latest version compatible with this device.
        [self downloadTrack:trackId version:0];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    // iPad needs a sourceView / sourceRect for ActionSheet.
    ac.popoverPresentationController.sourceView = self.view;
    ac.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width/2, 0, 1, 1);
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)promptManualVersionId:(long long)trackId withError:(NSString *)err {
    UIAlertController *ac = [UIAlertController
        alertControllerWithTitle:err ? @"Catalog unavailable" : @"Manual version"
                         message:err ?: @"Enter the external_identifier of the version you want."
                  preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"Version ID (integer)";
        f.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Download"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        long long vid = [ac.textFields.firstObject.text longLongValue];
        [self downloadTrack:trackId version:vid];
    }]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Latest compatible (iOS picks)"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [self downloadTrack:trackId version:0];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Store download (SKUIItemStateCenter — Muffinstore mechanism)

- (void)downloadTrack:(long long)trackId version:(long long)versionId {
    [self showProgress:@"Sending Store purchase request…"];

    NSString *adamId = [NSString stringWithFormat:@"%lld", trackId];
    NSString *appExtVrsId = versionId > 0
        ? [NSString stringWithFormat:@"%lld", versionId] : @"0";

    // Exactly the buyParams Muffinstore builds. productType=C + price=0 =
    // free purchase ; clientBuyId=1 marks it as a user-initiated download ;
    // appExtVrsId=0 means "latest compatible" per Apple's server, otherwise
    // the specific version id. trolled=1 is a Muffinstore convention left
    // in for parity.
    NSString *offer;
    if (versionId == 0) {
        offer = [NSString stringWithFormat:
            @"productType=C&price=0&salableAdamId=%@&pricingParameters=STDQ"
            @"&clientBuyId=1&installed=0&trolled=1", adamId];
    } else {
        offer = [NSString stringWithFormat:
            @"productType=C&price=0&salableAdamId=%@&pricingParameters=STDQ"
            @"&appExtVrsId=%@&clientBuyId=1&installed=0&trolled=1",
            adamId, appExtVrsId];
    }

    Class itemC   = NSClassFromString(@"SKUIItem");
    Class offerC  = NSClassFromString(@"SKUIItemOffer");
    Class ctrC    = NSClassFromString(@"SKUIItemStateCenter");
    Class ctxC    = NSClassFromString(@"SKUIClientContext");
    if (!itemC || !offerC || !ctrC || !ctxC) {
        [self dismissProgressAnimated:YES completion:^{
            [self alert:@"StoreKitUI missing"
                message:@"Private SKUI* classes aren't exposed in this build. "
                        @"TrollBox needs the com.apple.itunesstored.private "
                        @"entitlement; rebuild with ldid that preserves it."];
        }];
        return;
    }

    SKUIItemOffer *so = [[offerC alloc] initWithLookupDictionary:@{ @"buyParams": offer }];
    SKUIItem *item = [[itemC alloc] initWithLookupDictionary:@{ @"_itemOffer": adamId }];
    [item setValue:so forKey:@"_itemOffer"];
    [item setValue:@"iosSoftware" forKey:@"_itemKindString"];
    if (versionId > 0) {
        [item setValue:@(versionId) forKey:@"_versionIdentifier"];
    }

    SKUIItemStateCenter *center = [ctrC performSelector:@selector(defaultCenter)];
    id purchases = [center _newPurchasesWithItems:@[item]];
    [center _performPurchases:purchases
             hasBundlePurchase:NO
             withClientContext:[ctxC performSelector:@selector(defaultContext)]
               completionBlock:^(id result) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissProgressAnimated:YES completion:^{
                [self alert:@"Download started"
                    message:@"iOS is downloading the app in the background. "
                            @"Check your Home Screen for the install progress "
                            @"ring."];
            }];
        });
    }];
}

#pragma mark - Progress alert

- (void)showProgress:(NSString *)msg {
    self.progressAlert = [UIAlertController
        alertControllerWithTitle:@"Working"
                         message:msg
                  preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:self.progressAlert animated:YES completion:nil];
}

- (void)dismissProgressAnimated:(BOOL)animated completion:(void (^)(void))c {
    if (self.progressAlert) {
        [self.progressAlert dismissViewControllerAnimated:animated completion:c];
        self.progressAlert = nil;
    } else if (c) {
        c();
    }
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
