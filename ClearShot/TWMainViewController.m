#import "TWMainViewController.h"

// LSApplicationWorkspace is the private API TrollFools (and every TS app
// that lists installed apps) uses. It gives us the installed app list,
// bundle IDs, display names and bundle paths — no need for the containers
// registry walk.
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

@interface TWMainViewController ()
@property (strong, nonatomic) NSArray<LSApplicationProxy *> *userApps;
@end

@implementation TWMainViewController

- (instancetype)init {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
    }
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
    // User apps only — same filter as TrollFools: skip ApplicationType =
    // System / Internal / Hidden so we don't list every private framework
    // helper app.
    id ws = [NSClassFromString(@"LSApplicationWorkspace") performSelector:@selector(defaultWorkspace)];
    NSArray *all = [ws performSelector:@selector(allInstalledApplications)];
    NSMutableArray *filtered = [NSMutableArray array];
    for (LSApplicationProxy *p in all) {
        if ([[p valueForKey:@"applicationType"] isEqualToString:@"User"]) {
            [filtered addObject:p];
        }
    }
    // Sort alphabetically by display name.
    [filtered sortUsingComparator:^NSComparisonResult(id a, id b) {
        NSString *na = [a valueForKey:@"localizedName"] ?: @"";
        NSString *nb = [b valueForKey:@"localizedName"] ?: @"";
        return [na caseInsensitiveCompare:nb];
    }];
    self.userApps = filtered;
    [self.tableView reloadData];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == 0) return 1;             // the notice row
    return self.userApps.count;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == 0) return nil;
    return [NSString stringWithFormat:@"Installed user apps (%lu)",
            (unsigned long)self.userApps.count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    static NSString *kNotice = @"notice";
    static NSString *kApp    = @"app";
    UITableViewCell *cell;
    if (indexPath.section == 0) {
        cell = [tableView dequeueReusableCellWithIdentifier:kNotice];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                reuseIdentifier:kNotice];
        cell.textLabel.text = @"Pick dylibs from community repos";
        cell.textLabel.textColor = [UIColor systemYellowColor];
        cell.detailTextLabel.text = @"TrollBox doesn't ship with tweaks; you "
                                    @"provide the .dylib. Three well-maintained "
                                    @"TrollStore-compatible repos: YTLite "
                                    @"(dayanch96) for YouTube, BHInstagram and "
                                    @"BHTwitter (BandarHL) for Instagram and "
                                    @"Twitter. Each repo's README lists the "
                                    @"last free/compatible version.\n\n"
                                    @"Injection UI (port of TrollFools) is WIP; "
                                    @"tap an app below to see its current load "
                                    @"commands.";
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.detailTextLabel.numberOfLines = 0;
        cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:kApp];
        if (!cell) cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle
                                                reuseIdentifier:kApp];
        LSApplicationProxy *p = self.userApps[indexPath.row];
        cell.textLabel.text = [p valueForKey:@"localizedName"];
        cell.textLabel.textColor = [UIColor whiteColor];
        cell.detailTextLabel.text = [p valueForKey:@"applicationIdentifier"];
        cell.detailTextLabel.textColor = [UIColor lightGrayColor];
        cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) return;
    LSApplicationProxy *p = self.userApps[indexPath.row];
    NSURL *bundleURL = [p valueForKey:@"bundleURL"];
    NSString *name = [p valueForKey:@"localizedName"];
    NSString *msg = [NSString stringWithFormat:
                     @"%@\n\nBundle: %@\n\nInjection UI coming in the next build.",
                     name, bundleURL.path];
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:@"Tweak"
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
