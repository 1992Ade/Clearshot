#import "BCMainViewController.h"
#import "CSProcessUtils.h"

// Same path Cowabunga's BadgeChanger.swift targets. SpringBoard reads this
// file when drawing a badge; replacing it changes every badge system-wide.
static NSString * const kBadgeBitmapPath =
    @"/var/mobile/Library/Caches/MappedImageCache/Persistent/"
    @"SBIconBadgeView.BadgeBackground:26:26.cpbitmap";

// NSUserDefaults keys for persist-on-apply. Written when the user taps
// Apply (not on every slider drag) so abandoned tweaks don't overwrite
// the user's last confirmed choice.
static NSString * const kBCPersistHexKey    = @"TBBadgeColorLastHex";
static NSString * const kBCPersistRadiusKey = @"TBBadgeColorLastRadius";

static NSString *BCColorToHex(UIColor *c) {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [c getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"#%02X%02X%02X",
            (int)roundf(r * 255), (int)roundf(g * 255), (int)roundf(b * 255)];
}
static UIColor *BCHexToColor(NSString *hex) {
    if (![hex hasPrefix:@"#"] || hex.length != 7) return nil;
    unsigned int rgb = 0;
    [[NSScanner scannerWithString:[hex substringFromIndex:1]] scanHexInt:&rgb];
    return [UIColor colorWithRed:((rgb >> 16) & 0xFF) / 255.0
                           green:((rgb >> 8)  & 0xFF) / 255.0
                            blue:(rgb         & 0xFF) / 255.0
                           alpha:1.0];
}

// Private UIImage selector that writes a Core-Animation-compatible bitmap
// file. Same one Cowabunga uses via its `Dynamic` runtime helper; we go
// straight through performSelector so we don't drag a dependency in.
@interface UIImage (CSPrivateCPBitmap)
- (void)writeToCPBitmapFile:(NSString *)path flags:(int)flags;
@end

@interface BCMainViewController ()
@property (strong, nonatomic) UIView *previewIcon;
@property (strong, nonatomic) UIView *badgeDot;
@property (strong, nonatomic) UILabel *badgeCount;
@property (strong, nonatomic) UILabel *statusLabel;

// Current picker state.
@property (strong, nonatomic) UIColor *chosenColor;
@property (assign, nonatomic) CGFloat  chosenRadius;  // 1…24, same range as upstream
@end

@implementation BCMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"Badge Color";

    // Restore last-applied choice first; fall back to defaults only if the
    // user has never tapped Apply (= no persisted values yet).
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *savedHex = [d stringForKey:kBCPersistHexKey];
    UIColor *savedColor = savedHex ? BCHexToColor(savedHex) : nil;
    self.chosenColor  = savedColor ?: [UIColor systemRedColor];
    CGFloat savedRadius = [d doubleForKey:kBCPersistRadiusKey];
    self.chosenRadius = (savedRadius > 0 ? savedRadius : 24);

    [self buildUI];
    [self refreshPreview];
    [self refreshStatus];
}

#pragma mark - UI

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
    title.text = @"Badge Color";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    [self.view addSubview:title];
    y += 48;

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 80)];
    sub.text = @"Replaces the system badge bitmap SpringBoard uses for "
               @"notification pips, system-wide. Pick a colour and a radius, "
               @"tap Apply, then respring.";
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:14];
    sub.numberOfLines = 0;
    [self.view addSubview:sub];
    y += 90;

    // iOS 16+ warning. Upstream's UI hides this feature entirely there; we
    // keep it visible but tell the user so they're not surprised.
    if (@available(iOS 16.0, *)) {
        UILabel *warn = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
        warn.text = @"⚠️ iOS 16+ no longer honours this cache for most "
                    @"badges. You can still try — the file will be written "
                    @"— but you may see no change after respring.";
        warn.textColor = [UIColor systemYellowColor];
        warn.font = [UIFont systemFontOfSize:12];
        warn.numberOfLines = 0;
        [self.view addSubview:warn];
        y += 48;
    }

    // Live preview: a square icon placeholder with a dot in the corner.
    CGFloat iconSize = 110;
    CGFloat iconX = (w - iconSize) / 2.0;
    self.previewIcon = [[UIView alloc] initWithFrame:CGRectMake(iconX, y, iconSize, iconSize)];
    self.previewIcon.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    self.previewIcon.layer.cornerRadius = iconSize * 0.22;
    [self.view addSubview:self.previewIcon];

    CGFloat badgeSize = 38;
    self.badgeDot = [[UIView alloc] initWithFrame:CGRectMake(iconSize - badgeSize/2 - 2,
                                                              -badgeSize/2 + 2,
                                                              badgeSize, badgeSize)];
    [self.previewIcon addSubview:self.badgeDot];

    self.badgeCount = [[UILabel alloc] initWithFrame:self.badgeDot.bounds];
    self.badgeCount.text = @"1";
    self.badgeCount.textColor = [UIColor whiteColor];
    self.badgeCount.font = [UIFont systemFontOfSize:22 weight:UIFontWeightSemibold];
    self.badgeCount.textAlignment = NSTextAlignmentCenter;
    [self.badgeDot addSubview:self.badgeCount];

    y += iconSize + 24;

    // Status label.
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 20)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:12];
    [self.view addSubview:self.statusLabel];
    y += 28;

    // Color picker row.
    UILabel *colLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 140, 44)];
    colLabel.text = @"Badge colour";
    colLabel.textColor = [UIColor whiteColor];
    colLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.view addSubview:colLabel];

    UIButton *colBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    colBtn.frame = CGRectMake(w - 20 - 44, y, 44, 44);
    colBtn.backgroundColor = self.chosenColor;
    colBtn.layer.cornerRadius = 10;
    colBtn.layer.borderColor = [UIColor whiteColor].CGColor;
    colBtn.layer.borderWidth = 1;
    colBtn.tag = 1001;
    [colBtn addTarget:self action:@selector(didTapPickColor) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:colBtn];
    y += 56;

    // Radius slider row. Upstream clamps to 0…24 but passes max(1, radius)
    // into drawing, so 1…24 is the effective range.
    UILabel *radLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 140, 20)];
    radLabel.text = @"Corner radius";
    radLabel.textColor = [UIColor whiteColor];
    radLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    [self.view addSubview:radLabel];

    UISlider *radSlider = [[UISlider alloc] initWithFrame:CGRectMake(20, y + 22, w - 40, 32)];
    radSlider.minimumValue = 1;
    radSlider.maximumValue = 24;
    radSlider.value = self.chosenRadius;
    radSlider.tintColor = [UIColor systemPinkColor];
    [radSlider addTarget:self action:@selector(didChangeRadius:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:radSlider];
    y += 68;

    // Apply + Reset buttons.
    UIButton *apply = [self makeButton:@"Apply"
                                     y:y
                                 color:[UIColor systemBlueColor]
                                action:@selector(didTapApply)];
    (void)apply;
    y += 62;

    [self makeButton:@"Reset (delete badge bitmap)"
                   y:y
               color:[UIColor colorWithWhite:0.22 alpha:1.0]
              action:@selector(didTapReset)];
    y += 62;

    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 60)];
    footer.text = @"Apply writes the new bitmap, then prompts for a respring. "
                  @"Reset deletes the file so iOS falls back to the default red.";
    footer.textColor = [UIColor grayColor];
    footer.font = [UIFont systemFontOfSize:12];
    footer.numberOfLines = 0;
    [self.view addSubview:footer];
}

- (UIButton *)makeButton:(NSString *)title y:(CGFloat)y color:(UIColor *)color action:(SEL)sel {
    CGFloat w = self.view.bounds.size.width;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, y, w - 40, 52);
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 12;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

#pragma mark - Preview

- (void)refreshPreview {
    self.badgeDot.backgroundColor = self.chosenColor;
    // Match the upstream heuristic: badge size × (radius / 24) controls how
    // round the pill looks. Our badge is 38 px in the preview.
    self.badgeDot.layer.cornerRadius = 38.0 * self.chosenRadius / 24.0;
    // Keep the chosen-colour button in sync too.
    UIButton *colBtn = [self.view viewWithTag:1001];
    colBtn.backgroundColor = self.chosenColor;
}

- (void)refreshStatus {
    BOOL present = [[NSFileManager defaultManager] fileExistsAtPath:kBadgeBitmapPath];
    if (present) {
        self.statusLabel.text = @"Badge bitmap currently overridden.";
        self.statusLabel.textColor = [UIColor systemGreenColor];
    } else {
        self.statusLabel.text = @"No override — iOS is drawing the default badge.";
        self.statusLabel.textColor = [UIColor lightGrayColor];
    }
}

#pragma mark - Actions

- (void)didChangeRadius:(UISlider *)s {
    self.chosenRadius = s.value;
    [self refreshPreview];
}

- (void)didTapPickColor {
    if (@available(iOS 14.0, *)) {
        UIColorPickerViewController *pc = [[UIColorPickerViewController alloc] init];
        pc.selectedColor = self.chosenColor;
        pc.supportsAlpha = NO;
        pc.delegate = (id<UIColorPickerViewControllerDelegate>)self;
        [self presentViewController:pc animated:YES completion:nil];
    } else {
        [self alert:@"Needs iOS 14+"
            message:@"System colour picker requires iOS 14 or later."];
    }
}

- (void)colorPickerViewControllerDidSelectColor:(UIColorPickerViewController *)vc
                                       API_AVAILABLE(ios(14.0)) {
    self.chosenColor = vc.selectedColor;
    [self refreshPreview];
}

- (void)didTapApply {
    CGFloat radius = MAX(1, self.chosenRadius);
    BOOL isPad = (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad);
    CGFloat drawSize = isPad ? radius * 2 : radius;

    UIImage *circle = [self circleImageOfSize:drawSize color:self.chosenColor];
    if (!circle) {
        [self alert:@"Draw failed" message:@"Couldn't render the badge image."];
        return;
    }

    // Wipe then write — same order as Cowabunga's BadgeChanger.
    NSError *rmErr = nil;
    [[NSFileManager defaultManager] removeItemAtPath:kBadgeBitmapPath error:&rmErr];
    if (rmErr && rmErr.code != NSFileNoSuchFileError) {
        NSLog(@"[TrollBox/Badge] pre-remove err=%@", rmErr);
    }

    if (![circle respondsToSelector:@selector(writeToCPBitmapFile:flags:)]) {
        [self alert:@"Write unavailable"
            message:@"The private UIImage CPBitmap writer isn't exposed on "
                    @"this iOS version."];
        return;
    }
    [circle writeToCPBitmapFile:kBadgeBitmapPath flags:1];

    BOOL wrote = [[NSFileManager defaultManager] fileExistsAtPath:kBadgeBitmapPath];
    [self refreshStatus];

    // Persist-on-apply: remember THIS choice so reopening the section shows
    // the user's last confirmed look instead of the defaults.
    if (wrote) {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [d setObject:BCColorToHex(self.chosenColor) forKey:kBCPersistHexKey];
        [d setDouble:self.chosenRadius              forKey:kBCPersistRadiusKey];
        [d synchronize];
    }
    if (!wrote) {
        [self alert:@"Write didn't take"
            message:[NSString stringWithFormat:@"The file wasn't created at:\n%@",
                     kBadgeBitmapPath]];
        return;
    }

    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Applied"
                              message:@"Respring now to see the new badge?"
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Later"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Respring now"
                                           style:UIAlertActionStyleDefault
                                         handler:^(UIAlertAction *a) {
        [CSProcessUtils forceRespring];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)didTapReset {
    NSError *err = nil;
    BOOL ok = [[NSFileManager defaultManager] removeItemAtPath:kBadgeBitmapPath
                                                          error:&err];
    if (!ok && err && err.code != NSFileNoSuchFileError) {
        [self alert:@"Remove failed"
            message:err.localizedDescription ?: @"unknown"];
        return;
    }
    // Clear the persisted choice too, so a fresh open of the section comes
    // back to the stock red/24 defaults.
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d removeObjectForKey:kBCPersistHexKey];
    [d removeObjectForKey:kBCPersistRadiusKey];
    [d synchronize];

    [self refreshStatus];
    [self alert:@"Reset" message:@"Badge override removed. Respring to see the default badge."];
}

#pragma mark - Drawing

- (UIImage *)circleImageOfSize:(CGFloat)size color:(UIColor *)color {
    if (size < 1) size = 1;
    CGSize s = CGSizeMake(size, size);
    UIGraphicsBeginImageContextWithOptions(s, NO, 0);
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) { UIGraphicsEndImageContext(); return nil; }
    CGContextSaveGState(ctx);
    CGContextSetFillColorWithColor(ctx, color.CGColor);
    CGContextFillEllipseInRect(ctx, CGRectMake(0, 0, size, size));
    CGContextRestoreGState(ctx);
    UIImage *img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return img;
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
