#import "RSMainViewController.h"
#import "CSProcessUtils.h"
#import "TBSpringBoardPrefs.h"
#import <sys/stat.h>
#import <unistd.h>

// ============================================================================
// Paths and keys
// ============================================================================

static NSString * const kGfxPlist =
    @"/var/mobile/Library/Preferences/com.apple.iokit.IOMobileGraphicsFamily.plist";

// Don't-lock-after-respring lives in a helper now (TBSpringBoardPrefs) and
// is mirrored in SpringBoard Tweaks, Badge Color and ClearShot.

// LaunchDaemon that re-applies the saved backup on every boot.
static NSString * const kAutoApplyDaemonPath =
    @"/Library/LaunchDaemons/com.trollbox.ressetter.plist";
static NSString * const kAutoApplyBackupPath =
    @"/var/mobile/Library/Preferences/TrollBoxGfxBackup.plist";
static NSString * const kAutoApplyDaemonLabel = @"com.trollbox.ressetter";

// NSUserDefaults keys.
static NSString * const kFactorKey      = @"TBResSetterFactor";
static NSString * const kLastWidthKey   = @"TBResSetterLastWidth";
static NSString * const kLastHeightKey  = @"TBResSetterLastHeight";

// The gfx plist keys ResSetter writes/removes.
static NSString * const kGfxCanvasWidth  = @"canvas_width";
static NSString * const kGfxCanvasHeight = @"canvas_height";
static NSString * const kGfxScreenWidth  = @"screenWidth";
static NSString * const kGfxScreenHeight = @"screenHeight";

// Slider bounds.
static const double kFactorMin = 1.0;
static const double kFactorMax = 1.5;

// ============================================================================

@interface RSMainViewController () <UITableViewDataSource, UITableViewDelegate>
@property (strong, nonatomic) UITableView *table;
@property (assign, nonatomic) double factor;
@property (strong, nonatomic) UISlider *factorSlider;
@property (strong, nonatomic) UILabel *factorReadout;
@property (strong, nonatomic) UISwitch *autoApplySwitch;
@property (strong, nonatomic) UISwitch *dontLockSwitch;
@end

@implementation RSMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"ResSetter";

    [self loadFactor];

    self.table = [[UITableView alloc] initWithFrame:self.view.bounds
                                              style:UITableViewStyleInsetGrouped];
    self.table.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.table.backgroundColor = self.view.backgroundColor;
    self.table.dataSource = self;
    self.table.delegate = self;
    [self.view addSubview:self.table];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.table reloadData];
}

#pragma mark - Factor persistence

- (void)loadFactor {
    double f = [[NSUserDefaults standardUserDefaults] doubleForKey:kFactorKey];
    if (f < kFactorMin || f > kFactorMax) f = 1.0;
    self.factor = f;
}

- (void)saveFactor:(double)f {
    self.factor = f;
    [[NSUserDefaults standardUserDefaults] setDouble:f forKey:kFactorKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark - Device native (LANDSCAPE form)

// iOS expects canvas_width / canvas_height in the gfx plist to be the
// landscape-orientation form of the panel (width = long side, height =
// short side). UIScreen.nativeBounds returns portrait form (width = short
// side, height = long side) on a portrait phone, so we MAX / MIN on the
// way out — same convention haoict's ResolutionSetterSwift uses. A bug
// in a previous build wrote the portrait form and caused the x1.2
// artifacts a user reported.
- (CGSize)deviceNativeSize {
    UIScreen *s = [UIScreen mainScreen];
    CGRect nb = [s respondsToSelector:@selector(nativeBounds)] ? s.nativeBounds : s.bounds;
    CGFloat longer  = MAX(nb.size.width, nb.size.height);
    CGFloat shorter = MIN(nb.size.width, nb.size.height);
    return CGSizeMake(longer, shorter);
}

// Same convention for the "Current" reading — read whatever's in the plist,
// normalize to landscape form.
- (CGSize)currentPixelSize {
    NSDictionary *d = [NSDictionary dictionaryWithContentsOfFile:kGfxPlist];
    NSNumber *w = d[kGfxCanvasWidth];
    NSNumber *h = d[kGfxCanvasHeight];
    if (w.doubleValue > 0 && h.doubleValue > 0) {
        CGFloat longer  = MAX(w.doubleValue, h.doubleValue);
        CGFloat shorter = MIN(w.doubleValue, h.doubleValue);
        return CGSizeMake(longer, shorter);
    }
    return [self deviceNativeSize];
}

- (CGSize)targetPixelSize {
    CGSize n = [self deviceNativeSize];
    return CGSizeMake(round(n.width * self.factor),
                      round(n.height * self.factor));
}

#pragma mark - Table layout
// 0: This device (Native + Current)
// 1: Multiplier (slider, target preview, apply)
// 2: Reset to native (single destructive button)
// 3: Persistence (re-apply boot + don't lock)

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tv { return 4; }

- (NSInteger)tableView:(UITableView *)tv numberOfRowsInSection:(NSInteger)s {
    if (s == 0) return 2;         // native + current
    if (s == 1) return 3;         // slider row, target row, apply row
    if (s == 2) return 1;         // reset
    return 2;                      // 2 persistence toggles
}

- (NSString *)tableView:(UITableView *)tv titleForHeaderInSection:(NSInteger)s {
    if (s == 0) return @"This device";
    if (s == 1) return @"Multiplier";
    if (s == 2) return @"Recover";
    return @"Persistence";
}

- (NSString *)tableView:(UITableView *)tv titleForFooterInSection:(NSInteger)s {
    if (s == 1) {
        return @"Slide between ×1.00 and ×1.50. The multiplier is persisted. "
               @"Target = native × factor, rounded to whole pixels in the "
               @"landscape canvas form the gfx plist expects. Tap Apply to "
               @"write it, respring to pick it up.";
    }
    if (s == 2) {
        return @"Reset to native nukes every trace ResSetter left behind: the "
               @"LaunchDaemon (if installed), the saved backup plist, the "
               @"canvas_* keys in the gfx plist, and the persisted factor in "
               @"NSUserDefaults. Use this if any prior apply left the device "
               @"with visual artifacts.";
    }
    if (s == 3) {
        return @"• Re-apply at every boot: installs a LaunchDaemon that "
               @"restores the last-applied size before backboardd reads it.\n\n"
               @"• Don't lock device after respring: writes "
               @"SBDontLockAfterCrash=YES to SpringBoard's managed prefs. "
               @"Mirrored in SpringBoard Tweaks, Badge Color and ClearShot "
               @"— change any one, all four stay in sync.";
    }
    return nil;
}

#pragma mark - Table cells

- (UITableViewCell *)tableView:(UITableView *)tv cellForRowAtIndexPath:(NSIndexPath *)ip {
    UITableViewCell *cell = [[UITableViewCell alloc]
                              initWithStyle:UITableViewCellStyleSubtitle
                             reuseIdentifier:nil];
    cell.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.textLabel.textColor = [UIColor whiteColor];
    cell.detailTextLabel.textColor = [UIColor lightGrayColor];
    cell.accessoryType = UITableViewCellAccessoryNone;
    cell.accessoryView = nil;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    cell.textLabel.textAlignment = NSTextAlignmentLeft;
    cell.textLabel.font = [UIFont systemFontOfSize:17];

    if (ip.section == 0) {
        if (ip.row == 0) {
            CGSize n = [self deviceNativeSize];
            cell.textLabel.text = @"Native hardware panel";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d pixels (landscape)",
                                         (int)n.width, (int)n.height];
        } else {
            CGSize c = [self currentPixelSize];
            cell.textLabel.text = @"Current";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d pixels",
                                         (int)c.width, (int)c.height];
        }

    } else if (ip.section == 1) {
        if (ip.row == 0) {
            cell.textLabel.text = nil;
            cell.detailTextLabel.text = nil;
            [self installSliderCell:cell];

        } else if (ip.row == 1) {
            CGSize t = [self targetPixelSize];
            cell.textLabel.text = @"Target";
            cell.detailTextLabel.text = [NSString stringWithFormat:
                                         @"%d × %d pixels",
                                         (int)t.width, (int)t.height];

        } else {
            cell.textLabel.text = @"Apply";
            cell.textLabel.textColor = [UIColor systemBlueColor];
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
            cell.selectionStyle = UITableViewCellSelectionStyleDefault;
        }

    } else if (ip.section == 2) {
        cell.textLabel.text = @"Reset to native";
        cell.textLabel.textColor = [UIColor systemRedColor];
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;

    } else {
        if (ip.row == 0) {
            cell.textLabel.text = @"Re-apply at every boot";
            BOOL on = [self autoApplyActive];
            cell.detailTextLabel.text = on
                ? @"LaunchDaemon installed."
                : @"Off — resolution reverts to native on reboot.";
            if (!self.autoApplySwitch) {
                self.autoApplySwitch = [[UISwitch alloc] init];
                [self.autoApplySwitch addTarget:self action:@selector(didToggleAutoApply:)
                                forControlEvents:UIControlEventValueChanged];
            }
            self.autoApplySwitch.on = on;
            cell.accessoryView = self.autoApplySwitch;
        } else {
            cell.textLabel.text = @"Don't lock device after respring";
            BOOL on = [self dontLockActive];
            cell.detailTextLabel.text = on
                ? @"SBDontLockAfterCrash = YES."
                : @"Off — passcode prompt returns after respring.";
            if (!self.dontLockSwitch) {
                self.dontLockSwitch = [[UISwitch alloc] init];
                [self.dontLockSwitch addTarget:self action:@selector(didToggleDontLock:)
                               forControlEvents:UIControlEventValueChanged];
            }
            self.dontLockSwitch.on = on;
            cell.accessoryView = self.dontLockSwitch;
        }
    }
    return cell;
}

- (CGFloat)tableView:(UITableView *)tv heightForRowAtIndexPath:(NSIndexPath *)ip {
    if (ip.section == 1 && ip.row == 0) return 72;  // give the slider room
    return UITableViewAutomaticDimension;
}

- (void)tableView:(UITableView *)tv didSelectRowAtIndexPath:(NSIndexPath *)ip {
    [tv deselectRowAtIndexPath:ip animated:YES];
    if (ip.section == 1 && ip.row == 2) [self confirmApply];
    else if (ip.section == 2)           [self confirmReset];
}

#pragma mark - Slider cell

- (void)installSliderCell:(UITableViewCell *)cell {
    for (UIView *v in [cell.contentView.subviews copy]) [v removeFromSuperview];

    if (!self.factorSlider) {
        self.factorSlider = [[UISlider alloc] init];
        self.factorSlider.minimumValue = (float)kFactorMin;
        self.factorSlider.maximumValue = (float)kFactorMax;
        self.factorSlider.tintColor    = [UIColor systemBlueColor];
        [self.factorSlider addTarget:self action:@selector(didSlideFactor:)
                     forControlEvents:UIControlEventValueChanged];
    }
    self.factorSlider.value = (float)self.factor;

    if (!self.factorReadout) {
        self.factorReadout = [[UILabel alloc] init];
        self.factorReadout.font = [UIFont monospacedDigitSystemFontOfSize:17
                                                                   weight:UIFontWeightSemibold];
        self.factorReadout.textColor = [UIColor whiteColor];
        self.factorReadout.textAlignment = NSTextAlignmentRight;
    }
    self.factorReadout.text = [NSString stringWithFormat:@"×%.2f", self.factor];

    UILabel *header = [[UILabel alloc] init];
    header.text = @"Factor";
    header.textColor = [UIColor whiteColor];
    header.font = [UIFont systemFontOfSize:15];
    header.translatesAutoresizingMaskIntoConstraints = NO;

    self.factorSlider.translatesAutoresizingMaskIntoConstraints = NO;
    self.factorReadout.translatesAutoresizingMaskIntoConstraints = NO;

    [cell.contentView addSubview:header];
    [cell.contentView addSubview:self.factorReadout];
    [cell.contentView addSubview:self.factorSlider];

    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [header.topAnchor     constraintEqualToAnchor:cell.contentView.topAnchor constant:10],

        [self.factorReadout.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [self.factorReadout.centerYAnchor  constraintEqualToAnchor:header.centerYAnchor],
        [self.factorReadout.widthAnchor    constraintEqualToConstant:72],

        [self.factorSlider.leadingAnchor  constraintEqualToAnchor:cell.contentView.leadingAnchor constant:20],
        [self.factorSlider.trailingAnchor constraintEqualToAnchor:cell.contentView.trailingAnchor constant:-20],
        [self.factorSlider.topAnchor      constraintEqualToAnchor:header.bottomAnchor constant:8],
        [self.factorSlider.bottomAnchor   constraintEqualToAnchor:cell.contentView.bottomAnchor constant:-8],
    ]];
}

- (void)didSlideFactor:(UISlider *)s {
    // Snap to 0.01 steps for stable readout.
    double v = round(s.value * 100.0) / 100.0;
    [self saveFactor:v];
    self.factorReadout.text = [NSString stringWithFormat:@"×%.2f", self.factor];
    // Just refresh the Target row.
    [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:1 inSection:1]]
                      withRowAnimation:UITableViewRowAnimationNone];
}

#pragma mark - Apply

- (void)confirmApply {
    CGSize t = [self targetPixelSize];
    NSString *msg = [NSString stringWithFormat:
                     @"Apply %d × %d pixels (native × %.2f)?\n\n"
                     @"A respring is needed to pick up the change. Reboot "
                     @"reverts to native unless Re-apply at boot is on.",
                     (int)t.width, (int)t.height, self.factor];
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Apply resolution"
                              message:msg
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Apply"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [self applyTargetSize:t];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)applyTargetSize:(CGSize)t {
    NSInteger w = (NSInteger)t.width;
    NSInteger h = (NSInteger)t.height;

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:kGfxPlist];
    if (existing) [d addEntriesFromDictionary:existing];
    d[kGfxCanvasWidth]  = @(w);
    d[kGfxCanvasHeight] = @(h);
    d[kGfxScreenWidth]  = @(w);
    d[kGfxScreenHeight] = @(h);

    NSError *writeErr = nil;
    BOOL ok = [d writeToURL:[NSURL fileURLWithPath:kGfxPlist] error:&writeErr];
    if (!ok) {
        [self alert:@"Write failed"
            message:[NSString stringWithFormat:@"%@\n\nTarget: %@",
                     writeErr.localizedDescription ?: @"unknown", kGfxPlist]];
        return;
    }

    [[NSUserDefaults standardUserDefaults] setInteger:w forKey:kLastWidthKey];
    [[NSUserDefaults standardUserDefaults] setInteger:h forKey:kLastHeightKey];
    [[NSUserDefaults standardUserDefaults] synchronize];

    if ([self autoApplyActive]) [self writeBackupForWidth:w height:h];
    [self.table reloadData];

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Applied"
                              message:@"Respring now to pick up the new size?"
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Later"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring now"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [CSProcessUtils forceRespring];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Reset (nuke everything)

- (void)confirmReset {
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Reset to native"
                              message:@"Nuke ResSetter's full state:\n\n"
                                      @"  • Remove the LaunchDaemon (if installed)\n"
                                      @"  • Remove the saved backup plist\n"
                                      @"  • Delete the canvas_* keys in the gfx plist\n"
                                      @"  • Reset the persisted factor to ×1.00\n\n"
                                      @"Then respring to the native resolution.\n\n"
                                      @"Use this if a prior apply left the device "
                                      @"with visual artifacts or wrong resolution."
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Reset + respring"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [self performReset];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)performReset {
    NSFileManager *fm = [NSFileManager defaultManager];

    // 1) Remove the LaunchDaemon file. unlink() works at euid=0 after
    //    setuid(0). If it fails we also try rootSpawn /bin/rm as a belt-
    //    and-braces fallback.
    const char *daemonC = [kAutoApplyDaemonPath fileSystemRepresentation];
    if (unlink(daemonC) != 0 && access(daemonC, F_OK) == 0) {
        [CSProcessUtils rootSpawn:@"/bin/rm" args:@[@"-f", kAutoApplyDaemonPath]
                           stdOut:NULL stdErr:NULL];
    }

    // 2) Remove the backup plist.
    [fm removeItemAtPath:kAutoApplyBackupPath error:nil];

    // 3) Delete the canvas_* keys from the gfx plist WITHOUT touching the
    //    rest of the file. If no other keys remain, remove the plist
    //    entirely so iOS reads its defaults.
    NSMutableDictionary *d = [[NSMutableDictionary alloc]
                                initWithContentsOfFile:kGfxPlist];
    if (d) {
        [d removeObjectForKey:kGfxCanvasWidth];
        [d removeObjectForKey:kGfxCanvasHeight];
        [d removeObjectForKey:kGfxScreenWidth];
        [d removeObjectForKey:kGfxScreenHeight];
        if (d.count == 0) {
            [fm removeItemAtPath:kGfxPlist error:nil];
        } else {
            [d writeToURL:[NSURL fileURLWithPath:kGfxPlist] error:nil];
        }
    }

    // 4) Reset the NSUserDefaults keys.
    NSUserDefaults *u = [NSUserDefaults standardUserDefaults];
    [u removeObjectForKey:kFactorKey];
    [u removeObjectForKey:kLastWidthKey];
    [u removeObjectForKey:kLastHeightKey];
    [u synchronize];
    self.factor = 1.0;

    [self.table reloadData];

    // 5) Prompt for immediate respring so backboardd re-reads defaults.
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Reset done"
                              message:@"Daemon removed, backup removed, gfx plist "
                                      @"keys deleted, factor back to ×1.00.\n\n"
                                      @"Respring now to drop to native resolution."
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Later"
                                           style:UIAlertActionStyleCancel handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring now"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        [CSProcessUtils forceRespring];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Persist across reboot (LaunchDaemon)

- (BOOL)autoApplyActive {
    return [[NSFileManager defaultManager] fileExistsAtPath:kAutoApplyDaemonPath];
}

- (BOOL)writeBackupForWidth:(NSInteger)w height:(NSInteger)h {
    NSDictionary *payload = @{
        kGfxCanvasWidth:  @(w),
        kGfxCanvasHeight: @(h),
        kGfxScreenWidth:  @(w),
        kGfxScreenHeight: @(h),
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
        @"Label":            kAutoApplyDaemonLabel,
        @"ProgramArguments": @[ @"/bin/sh", @"-c", shellCmd ],
        @"RunAtLoad":        @YES,
        @"UserName":         @"root",
        @"GroupName":        @"wheel",
    };

    // Preferred path: setuid(0) in main.m gives us euid=0, so NSFileManager
    // writes to /Library/LaunchDaemons/ directly. chown / chmod are syscall
    // calls, no spawn needed.
    NSError *writeErr = nil;
    BOOL direct = [daemon writeToURL:[NSURL fileURLWithPath:kAutoApplyDaemonPath]
                                error:&writeErr];
    if (direct) {
        chown([kAutoApplyDaemonPath fileSystemRepresentation], 0, 0);
        chmod([kAutoApplyDaemonPath fileSystemRepresentation], 0644);
        struct stat st;
        if (stat([kAutoApplyDaemonPath fileSystemRepresentation], &st) == 0 &&
            st.st_uid == 0 && st.st_gid == 0 && (st.st_mode & 0777) == 0644) {
            return YES;
        }
        NSLog(@"[TrollBox/Res] direct write stat drift — falling back to rootSpawn");
    } else {
        NSLog(@"[TrollBox/Res] direct write err=%@ — falling back to rootSpawn",
              writeErr);
    }

    // Fallback: rootSpawn.
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                          @"com.trollbox.ressetter.plist"];
    if (![daemon writeToURL:[NSURL fileURLWithPath:tmpPath] error:outErr]) return NO;

    NSString *out = nil, *errStr = nil;
    int rc = [CSProcessUtils rootSpawn:@"/bin/cp"
                                  args:@[@"-f", tmpPath, kAutoApplyDaemonPath]
                                stdOut:&out stdErr:&errStr];
    if (rc != 0) {
        if (outErr) *outErr = [NSError errorWithDomain:@"TrollBox" code:11
                                               userInfo:@{NSLocalizedDescriptionKey:
            [NSString stringWithFormat:@"rootSpawn cp exit=%d%@%@",
             rc,
             errStr.length ? [@"\nstderr: " stringByAppendingString:errStr] : @"",
             out.length    ? [@"\nstdout: " stringByAppendingString:out]    : @""]}];
        return NO;
    }
    [CSProcessUtils rootSpawn:@"/usr/sbin/chown" args:@[@"root:wheel", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
    [CSProcessUtils rootSpawn:@"/bin/chmod"     args:@[@"0644", kAutoApplyDaemonPath]
                       stdOut:NULL stdErr:NULL];
    return YES;
}

- (void)removeAutoApplyDaemon {
    const char *p = [kAutoApplyDaemonPath fileSystemRepresentation];
    if (unlink(p) != 0 && access(p, F_OK) == 0) {
        [CSProcessUtils rootSpawn:@"/bin/rm" args:@[@"-f", kAutoApplyDaemonPath]
                           stdOut:NULL stdErr:NULL];
    }
}

- (void)didToggleAutoApply:(UISwitch *)sw {
    if (sw.on) {
        NSInteger w = [[NSUserDefaults standardUserDefaults] integerForKey:kLastWidthKey];
        NSInteger h = [[NSUserDefaults standardUserDefaults] integerForKey:kLastHeightKey];
        if (w <= 0 || h <= 0) {
            [self alert:@"Apply once first"
                message:@"Set a factor and tap Apply at least once so the "
                        @"daemon has a size to restore."];
            sw.on = NO;
            return;
        }
        UIAlertController *ac = [UIAlertController
                                  alertControllerWithTitle:@"Re-apply at every boot"
                                  message:[NSString stringWithFormat:
                                           @"Install a LaunchDaemon that restores "
                                           @"%ld × %ld at each boot?",
                                           (long)w, (long)h]
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
            BOOL ok = [self installAutoApplyDaemonForWidth:w height:h error:&err];
            if (!ok) {
                sw.on = NO;
                [self alert:@"Install failed"
                    message:[NSString stringWithFormat:@"%@\n\nTarget:\n%@",
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

#pragma mark - Don't lock after respring (via shared TBSpringBoardPrefs)

- (BOOL)dontLockActive { return [TBSpringBoardPrefs dontLockActive]; }

- (void)didToggleDontLock:(UISwitch *)sw {
    NSError *err = nil;
    if (![TBSpringBoardPrefs setDontLockActive:sw.on error:&err]) {
        sw.on = !sw.on;
        [self alert:@"Write failed"
            message:err.localizedDescription ?: @"unknown"];
        return;
    }
    [self.table reloadSections:[NSIndexSet indexSetWithIndex:3]
              withRowAnimation:UITableViewRowAnimationAutomatic];
}

#pragma mark - Alerts

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
