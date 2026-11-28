#import "TWMainViewController.h"
#import "TFInjector.h"
#import "TFMachO.h"
#import "TFCodesign.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

// ============================================================================
// LSApplicationWorkspace surface — same pattern used elsewhere in TrollBox.
// ============================================================================
@interface LSApplicationProxy : NSObject
@property (readonly) NSString *localizedName;
@property (readonly) NSString *applicationIdentifier;
@property (readonly) NSURL *bundleURL;
@property (readonly) NSString *applicationType;
@end
@interface LSApplicationWorkspace : NSObject
+ (id)defaultWorkspace;
- (NSArray *)allInstalledApplications;
@end

// ============================================================================
// Per-app detail — shows injected dylibs + offers "Inject new…" + eject swipe
// ============================================================================

@interface TWAppDetailViewController : UITableViewController <UIDocumentPickerDelegate>
@property (copy) NSString *bundleId;
@property (copy) NSString *appName;
@property (strong) NSArray<NSString *> *injected;
@end

@implementation TWAppDetailViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {}
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    self.title = self.appName ?: @"Tweaks";
    [self reload];
}

- (void)reload {
    self.injected = [TFInjector injectedDylibLeafsForAppID:self.bundleId] ?: @[];
    [self.tableView reloadData];
}

#pragma mark - Table

// 0: injected dylibs (or "nothing injected" placeholder)
// 1: inject new / open ldid-status

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return MAX((NSInteger)self.injected.count, 1);
    return 1;
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"Currently injected";
    return @"Actions";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0 && self.injected.count > 0) {
        return @"Swipe a row to eject. The target app re-signs itself and "
               @"relaunches with the new load commands on next open.";
    }
    if (s == 1) {
        NSString *ldid = [TFCodesign availableLdidPath];
        if (ldid) return [NSString stringWithFormat:@"ldid: %@", ldid];
        return @"⚠ ldid not found on device. Install it (TrollFools bundles "
               @"it, or Procursus / Dopamine repos ship it) so TrollBox can "
               @"re-sign the modified executable.";
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
        if (self.injected.count == 0) {
            cell.textLabel.text = @"No tweaks injected yet";
            cell.textLabel.textColor = [UIColor lightGrayColor];
            cell.detailTextLabel.text = @"Use \"Inject new…\" below to pick a .dylib.";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            cell.textLabel.text = self.injected[ip.row];
            cell.detailTextLabel.text = @"Swipe to eject";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        }
    } else {
        cell.textLabel.text = @"Inject new .dylib / .bundle…";
        cell.textLabel.textColor = [UIColor systemBlueColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1) [self pickDylib];
}

- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == 0 && self.injected.count > 0;
}

- (UISwipeActionsConfiguration *)tableView:(UITableView *)tv
  trailingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)ip {
    NSString *leaf = self.injected[ip.row];
    UIContextualAction *eject =
        [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                 title:@"Eject"
                                               handler:^(UIContextualAction *a, UIView *v,
                                                         void (^completion)(BOOL)) {
        NSError *err = nil;
        BOOL ok = [TFInjector ejectDylibLeaf:leaf
                                   fromAppID:self.bundleId
                                       error:&err];
        if (!ok) {
            [self alert:@"Eject failed"
                message:err.localizedDescription ?: @"unknown"];
        }
        [self reload];
        completion(ok);
    }];
    return [UISwipeActionsConfiguration configurationWithActions:@[eject]];
}

#pragma mark - Inject flow

- (void)pickDylib {
    if (@available(iOS 14.0, *)) {
        NSMutableArray *types = [NSMutableArray array];
        UTType *dylib = [UTType typeWithFilenameExtension:@"dylib"];
        if (dylib) [types addObject:dylib];
        UTType *bundleT = [UTType typeWithFilenameExtension:@"bundle"];
        if (bundleT) [types addObject:bundleT];
        UTType *debT = [UTType typeWithFilenameExtension:@"deb"];
        if (debT) [types addObject:debT];
        if (types.count == 0) [types addObject:UTTypeData];

        UIDocumentPickerViewController *dp =
            [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:types
                                                                    asCopy:YES];
        dp.delegate = self;
        [self presentViewController:dp animated:YES completion:nil];
    } else {
        [self alert:@"iOS 14+ required" message:@"UIDocumentPicker needs iOS 14 or later."];
    }
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller
  didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *src = urls.firstObject;
    if (!src) return;

    [self presentProgress:@"Injecting…"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *err = nil;
        NSString *leaf = [TFInjector injectDylibAtPath:src.path
                                             intoAppID:self.bundleId
                                                 error:&err];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self dismissProgress:^{
                if (!leaf) {
                    [self alert:@"Injection failed"
                        message:err.localizedDescription ?: @"unknown"];
                } else {
                    [self alert:@"Injected"
                        message:[NSString stringWithFormat:
                                  @"%@ installed in %@'s Frameworks. "
                                  @"Force-quit and re-open the app to trigger it.",
                                  leaf, self.appName]];
                }
                [self reload];
            }];
        });
    });
}

#pragma mark - Progress + alert

- (void)presentProgress:(NSString *)msg {
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Working"
                              message:msg
                              preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)dismissProgress:(void (^)(void))c {
    [self.presentedViewController dismissViewControllerAnimated:YES completion:c];
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end

// ============================================================================
// Main Tweaks screen
// ============================================================================

@interface TWMainViewController ()
@property (strong, nonatomic) NSArray<LSApplicationProxy *> *userApps;
@end

@implementation TWMainViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {}
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Tweaks";
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.tableView.backgroundColor = self.view.backgroundColor;
    [self reloadApps];
}

- (void)reloadApps {
    id ws = [NSClassFromString(@"LSApplicationWorkspace")
             performSelector:@selector(defaultWorkspace)];
    NSArray *all = [ws performSelector:@selector(allInstalledApplications)];
    NSMutableArray *filtered = [NSMutableArray array];
    for (LSApplicationProxy *p in all) {
        if ([[p valueForKey:@"applicationType"] isEqualToString:@"User"]) {
            [filtered addObject:p];
        }
    }
    [filtered sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *na = [a valueForKey:@"localizedName"] ?: @"";
        NSString *nb = [b valueForKey:@"localizedName"] ?: @"";
        return [na caseInsensitiveCompare:nb];
    }];
    self.userApps = filtered;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 2; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 1;         // preamble
    return MAX((NSInteger)self.userApps.count, 1);
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 1) return [NSString stringWithFormat:@"Installed user apps (%lu)",
                         (unsigned long)self.userApps.count];
    return nil;
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 0) {
        return @"Inject dylibs or tweak bundles into installed apps. TrollBox "
               @"doesn't ship with tweaks — you provide the .dylib or .deb. "
               @"Known good TrollStore-compatible sources:\n\n"
               @"• YouTube: YTLite (dayanch96), YouTube Reborn (lillie-dev), uYouPlus (qnblackcat)\n"
               @"• Social: BHInstagram, BHTwitter (BandarHL), Barcelona (EthanArbuckle)\n"
               @"• System: Choicy (opa334) — tweak injection control panel\n\n"
               @"Tap an app below to see its currently-injected tweaks and "
               @"inject new ones. Legality of each tweak depends on your "
               @"jurisdiction and the target app's ToS.";
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
        cell.textLabel.text = @"🔧  Pick dylibs from community repos";
        cell.textLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = @"Full details in the section footer below.";
        cell.detailTextLabel.numberOfLines = 0;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    if (self.userApps.count == 0) {
        cell.textLabel.text = @"No user apps installed";
        cell.textLabel.textColor = [UIColor lightGrayColor];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }

    LSApplicationProxy *p = self.userApps[ip.row];
    cell.textLabel.text = [p valueForKey:@"localizedName"];
    cell.detailTextLabel.text = [p valueForKey:@"applicationIdentifier"];
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

    // Show the live injected-count as a hint.
    NSString *bid = [p valueForKey:@"applicationIdentifier"];
    NSUInteger n = [[TFInjector injectedDylibLeafsForAppID:bid] count];
    if (n > 0) {
        cell.detailTextLabel.text =
            [NSString stringWithFormat:@"%@ · %lu tweak%@ injected",
             bid, (unsigned long)n, n == 1 ? @"" : @"s"];
        cell.detailTextLabel.textColor = [UIColor systemGreenColor];
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0) return;
    if (self.userApps.count == 0) return;

    LSApplicationProxy *p = self.userApps[ip.row];
    TWAppDetailViewController *det = [[TWAppDetailViewController alloc] init];
    det.bundleId = [p valueForKey:@"applicationIdentifier"];
    det.appName  = [p valueForKey:@"localizedName"];
    [self.navigationController pushViewController:det animated:YES];
}

@end
