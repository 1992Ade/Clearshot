#import "RSMainViewController.h"
#import "CSProcessUtils.h"

static NSString * const kGfxPlist =
    @"/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist";
static NSString * const kSavedPresetsKey = @"TBResSetterSavedPresets";

// Persist-across-reboot: LaunchDaemon that copies a backup of the gfx prefs
// into place before backboardd reads them at boot.
static NSString * const kAutoApplyDaemonPath =
    @"/Library/LaunchDaemons/com.trollbox.ressetter.plist";
static NSString * const kAutoApplyBackupPath =
    @"/var/mobile/Library/Preferences/TrollBoxGfxBackup.plist";
static NSString * const kAutoApplyDaemonLabel = @"com.trollbox.ressetter";

@interface RSPreset : NSObject <NSSecureCoding>
@property (copy, nonatomic) NSString *name;
@property (assign, nonatomic) NSInteger width;
@property (assign, nonatomic) NSInteger height;
@end

@implementation RSPreset
+ (BOOL)supportsSecureCoding { return YES; }
- (instancetype)initWithCoder:(NSCoder *)c {
    if ((self = [super init])) {
        _name   = [[c decodeObjectOfClass:NSString.class forKey:@"n"] copy];
        _width  = [c decodeIntegerForKey:@"w"];
        _height = [c decodeIntegerForKey:@"h"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)c {
    [c encodeObject:_name forKey:@"n"];
    [c encodeInteger:_width forKey:@"w"];
    [c encodeInteger:_height forKey:@"h"];
}
@end

@interface RSMainViewController () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) UITableView *table;
@property (strong, nonatomic) NSMutableArray<RSPreset *> *saved;
@end

@implementation RSMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"ResSetter";

    [self loadSaved];

    self.navigationItem.rightBarButtonItem =
        [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd
                                                       target:self
                                                       action:@selector(didTapAdd)];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds
                                              style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = self.view.backgroundColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

#pragma mark - Persistence

- (void)loadSaved {
    NSData *d = [[NSUserDefaults standardUserDefaults] dataForKey:kSavedPresetsKey];
    NSMutableArray *arr = nil;
    if (d) {
        NSError *err = nil;
        NSSet *classes = [NSSet setWithObjects:NSArray.class, RSPreset.class, nil];
        arr = [[NSKeyedUnarchiver unarchivedObjectOfClasses:classes
                                                   fromData:d
                                                      error:&err] mutableCopy];
        if (err) NSLog(@"[TrollBox/Res] decode err=%@", err);
    }
    self.saved = arr ?: [NSMutableArray array];
}

- (void)saveSaved {
    NSError *err = nil;
    NSData *d = [NSKeyedArchiver archivedDataWithRootObject:self.saved
                                      requiringSecureCoding:YES
                                                      error:&err];
    if (err) NSLog(@"[TrollBox/Res] encode err=%@", err);
    if (d) [[NSUserDefaults standardUserDefaults] setObject:d forKey:kSavedPresetsKey];
}

#pragma mark - Device native

- (CGSize)deviceNativeSize {
    // Native pixel size of the display — not affected by scale, not
    // affected by a previous ResSetter apply (iOS reports the current
    // scaled size via mainScreen.bounds; nativeBounds is the hardware
    // panel resolution).
    UIScreen *s = [UIScreen mainScreen];
    CGRect nb = [s respondsToSelector:@selector(nativeBounds)] ? s.nativeBounds : s.bounds;
    return CGSizeMake(nb.size.width, nb.size.height);
}

- (CGSize)deviceCurrentPointSize {
    // What UIKit currently reports as the point-size viewport. If a previous
    // ResSetter write is in effect this reflects that.
    return [UIScreen mainScreen].bounds.size;
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 3; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 2;        // Device native + current
    if (s == 1) return MAX((NSInteger)self.saved.count, 1);
    return 1;                    // Persistence toggle
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"This device";
    if (s == 1) return @"Your saved resolutions";
    return @"Persistence";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        return @"Tap a saved resolution to apply it. "
               @"Reboot to revert — unless Persistence is on.";
    }
    if (s == 2) {
        return @"iOS clears the custom resolution on every reboot. Turn this "
               @"on to re-apply the last-used resolution automatically after "
               @"each boot, via a LaunchDaemon that runs before backboardd.\n\n"
               @"⚠️ If the chosen resolution ever boots to a black screen, "
               @"hold Volume Down + Side to power off, then boot in safe mode "
               @"to disable this toggle.";
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

    if (ip.section == 0) {
        CGSize native  = [self deviceNativeSize];
        CGSize current = [self deviceCurrentPointSize];
        CGFloat scale = [UIScreen mainScreen].scale;
        if (ip.row == 0) {
            cell.textLabel.text = @"Native hardware panel";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d pixels",
                                         (int)native.width, (int)native.height];
        } else {
            cell.textLabel.text = @"Current (what iOS reports now)";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d points · @%.0fx",
                                         (int)current.width, (int)current.height, scale];
        }
    } else if (ip.section == 1) {
        if (self.saved.count == 0) {
            cell.textLabel.text = @"No saved resolutions yet";
            cell.textLabel.textColor = [UIColor lightGrayColor];
            cell.detailTextLabel.text = @"Tap + in the top-right to add one.";
            cell.selectionStyle = UITableViewCellSelectionStyleNone;
        } else {
            RSPreset *p = self.saved[ip.row];
            cell.textLabel.text = p.name.length ? p.name : @"Preset";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%ld × %ld",
                                         (long)p.width, (long)p.height];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
            cell.accessoryType = UITableViewCellAccessoryDetailDisclosureButton;
        }
    } else {
        cell.textLabel.text = @"Re-apply last preset at every boot";
        cell.detailTextLabel.text = [self autoApplyActive]
            ? @"✅ LaunchDaemon installed"
            : @"Off — resolution reverts to native on reboot";
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [self autoApplyActive];
        [sw addTarget:self action:@selector(didToggleAutoApply:)
             forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    }
    return cell;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 0 || ip.section == 2) return;
    if (self.saved.count == 0) return;
    RSPreset *p = self.saved[ip.row];
    [self confirmApply:p];
}

// Swipe-to-delete on saved entries.
- (BOOL)tableView:(UITableView *)tv canEditRowAtIndexPath:(NSIndexPath *)ip {
    return ip.section == 1 && self.saved.count > 0;
}

- (void)tableView:(UITableView *)tv commitEditingStyle:(UITableViewCellEditingStyle)style
                                      forRowAtIndexPath:(NSIndexPath *)ip {
    if (style != UITableViewCellEditingStyleDelete) return;
    [self.saved removeObjectAtIndex:ip.row];
    [self saveSaved];
    [tv reloadData];
}

#pragma mark - Actions

- (void)didTapAdd {
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"New resolution"
                              message:@"Keep width and height reasonable. "
                                      @"Values too far from the native panel "
                                      @"can leave a black screen; reboot to "
                                      @"recover."
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"Name (optional)";
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"Width (pixels)";
        f.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [ac addTextFieldWithConfigurationHandler:^(UITextField *f) {
        f.placeholder = @"Height (pixels)";
        f.keyboardType = UIKeyboardTypeNumberPad;
    }];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Save"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        NSString *name = ac.textFields[0].text;
        NSInteger w = ac.textFields[1].text.integerValue;
        NSInteger h = ac.textFields[2].text.integerValue;
        if (w <= 0 || h <= 0) return;
        RSPreset *p = [[RSPreset alloc] init];
        p.name = name.length ? name : [NSString stringWithFormat:@"%ld × %ld", (long)w, (long)h];
        p.width = w; p.height = h;
        [self.saved addObject:p];
        [self saveSaved];
        [self.table reloadData];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)confirmApply:(RSPreset *)p {
    NSString *msg = [NSString stringWithFormat:
                     @"Apply %ld × %ld?\n\nA respring is needed to pick up "
                     @"the change. Reboot to revert to the original.",
                     (long)p.width, (long)p.height];
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Apply resolution"
                              message:msg
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Apply"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [self applyPreset:p];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)applyPreset:(RSPreset *)p {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kGfxPlist];
    if (existing) [d addEntriesFromDictionary:existing];
    d[@"canvas_width"]  = @(p.width);
    d[@"canvas_height"] = @(p.height);
    d[@"screenWidth"]   = @(p.width);
    d[@"screenHeight"]  = @(p.height);

    NSError *writeErr = nil;
    BOOL ok = [d writeToURL:[NSURL fileURLWithPath:kGfxPlist] error:&writeErr];
    if (!ok) {
        [self alert:@"Write failed"
            message:[NSString stringWithFormat:@"%@\n\nTarget: %@",
                     writeErr.localizedDescription ?: @"unknown", kGfxPlist]];
        return;
    }

    // If the auto-apply toggle is on, refresh the backup so next boot
    // restores THIS preset (not whatever was saved earlier).
    if ([self autoApplyActive]) {
        [self writeBackupForWidth:p.width height:p.height];
    }

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Applied"
                              message:@"Respring now to pick up the new "
                                      @"resolution?"
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring now"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [CSProcessUtils forceRespring];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Persist-across-reboot

- (BOOL)autoApplyActive {
    return [[NSFileManager defaultManager] fileExistsAtPath:kAutoApplyDaemonPath];
}

- (BOOL)writeBackupForWidth:(NSInteger)w height:(NSInteger)h {
    NSDictionary *payload = @{
        @"canvas_width":  @(w),
        @"canvas_height": @(h),
        @"screenWidth":   @(w),
        @"screenHeight":  @(h),
    };
    NSError *err = nil;
    BOOL ok = [payload writeToURL:[NSURL fileURLWithPath:kAutoApplyBackupPath]
                            error:&err];
    if (!ok) NSLog(@"[TrollBox/Res] backup write err=%@", err);
    return ok;
}

- (BOOL)installAutoApplyDaemonForWidth:(NSInteger)w height:(NSInteger)h
                                 error:(NSError **)outErr {
    if (![self writeBackupForWidth:w height:h]) {
        if (outErr) *outErr = [NSError errorWithDomain:@"TrollBox" code:10
                                               userInfo:@{NSLocalizedDescriptionKey:
            @"Couldn't write the backup plist the LaunchDaemon depends on."}];
        return NO;
    }

    NSString *shellCmd = [NSString stringWithFormat:
        @"/bin/cp -f '%@' '%@'", kAutoApplyBackupPath, kGfxPlist];
    NSDictionary *daemon = @{
        @"Label": kAutoApplyDaemonLabel,
        @"ProgramArguments": @[ @"/bin/sh", @"-c", shellCmd ],
        @"RunAtLoad":  @YES,
        @"UserName":   @"root",
        @"GroupName":  @"wheel",
    };

    // Write the plist to a tmp path we can touch, then rootSpawn /bin/cp it
    // to /Library/LaunchDaemons/ (which is root:wheel 0755).
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          @"com.trollbox.ressetter.plist"];
    if (![daemon writeToURL:[NSURL fileURLWithPath:tmpPath] error:outErr]) {
        return NO;
    }

    int rc = [CSProcessUtils rootSpawn:@"/bin/cp"
                                  args:@[@"-f", tmpPath, kAutoApplyDaemonPath]
                                stdOut:NULL stdErr:NULL];
    if (rc != 0) {
        if (outErr) *outErr = [NSError errorWithDomain:@"TrollBox" code:11
                                               userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"rootSpawn cp exit=%d", rc]}];
        return NO;
    }
    // launchd rejects plists not owned by root:wheel with mode 0644.
    [CSProcessUtils rootSpawn:@"/usr/sbin/chown" args:@[@"root:wheel", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
    [CSProcessUtils rootSpawn:@"/bin/chmod"     args:@[@"0644", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
    return YES;
}

- (void)removeAutoApplyDaemon {
    [CSProcessUtils rootSpawn:@"/bin/rm" args:@[@"-f", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
    // Leave the backup plist alone; harmless.
}

- (void)didToggleAutoApply:(UISwitch *)sw {
    if (sw.on) {
        if (self.saved.count == 0) {
            [self alert:@"No preset saved"
                message:@"Save at least one resolution preset first (tap + "
                        @"in the top-right), then apply it. The persist "
                        @"toggle will remember that preset for next boot."];
            sw.on = NO;
            return;
        }
        RSPreset *p = self.saved.lastObject;
        UIAlertController *ac = [UIAlertController
                                  alertControllerWithTitle:@"Re-apply at every boot"
                                  message:[NSString stringWithFormat:
                                           @"Install a LaunchDaemon that "
                                           @"restores %ld × %ld at each boot?\n\n"
                                           @"If the resolution ever stops "
                                           @"booting cleanly, boot in safe "
                                           @"mode and turn this off.",
                                           (long)p.width, (long)p.height]
                                  preferredStyle:UIAlertControllerStyleAlert];
        [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                               style:UIAlertActionStyleCancel
                                             handler:^(UIAlertAction *a) {
            sw.on = NO;
        }]];
        [ac addAction:[UIAlertAction actionWithTitle:@"Install daemon"
                                               style:UIAlertActionStyleDestructive
                                             handler:^(UIAlertAction *a) {
            NSError *err = nil;
            BOOL ok = [self installAutoApplyDaemonForWidth:p.width height:p.height
                                                     error:&err];
            if (!ok) {
                sw.on = NO;
                [self alert:@"Install failed"
                    message:[NSString stringWithFormat:@"%@\n\nTarget: %@",
                             err.localizedDescription ?: @"unknown",
                             kAutoApplyDaemonPath]];
            }
            [self.table reloadData];
        }]];
        [self presentViewController:ac animated:YES completion:nil];
    } else {
        [self removeAutoApplyDaemon];
        [self.table reloadData];
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
