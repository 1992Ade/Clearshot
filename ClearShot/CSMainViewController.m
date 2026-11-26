#import "CSMainViewController.h"
#import "CSInstaller.h"
#import "CSProcessUtils.h"

@interface CSMainViewController ()
@property (strong, nonatomic) UIScrollView *scrollView;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UIButton *installBtn;
@property (strong, nonatomic) UIButton *respringBtn;
@property (strong, nonatomic) UIButton *openSettingsBtn;
@property (strong, nonatomic) UIButton *testCaptureBtn;
@property (strong, nonatomic) UIButton *diagnosticsBtn;
@end

@implementation CSMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    [self buildUI];
    [self refreshStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

- (void)buildUI {
    // Wrap everything in a scroll view so the Diagnostics button fits on
    // the iPhone SE 1st-gen screen (4-inch).
    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth |
                                       UIViewAutoresizingFlexibleHeight;
    self.scrollView.alwaysBounceVertical = YES;
    [self.view addSubview:self.scrollView];

    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 70;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 44)];
    title.text = @"ClearShot";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    [self.scrollView addSubview:title];
    y += 50;

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 80)];
    sub.text = @"Control Center screenshot that bypasses the FLAG_SECURE / "
               @"protected-content filter used by banking, auth and messenger apps.";
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:14];
    sub.numberOfLines = 0;
    [self.scrollView addSubview:sub];
    y += 90;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, w - 40, 110)];
    card.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    card.layer.cornerRadius = 14;
    [self.scrollView addSubview:card];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, card.bounds.size.width - 28, 90)];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:self.statusLabel];
    y += 124;

    self.installBtn = [self makeButton:@"1 · Install Control Center module"
                                     y:y
                                 color:[UIColor systemBlueColor]
                                action:@selector(didTapInstall)];
    y += 62;

    self.respringBtn = [self makeButton:@"2 · Respring now"
                                      y:y
                                  color:[UIColor systemOrangeColor]
                                 action:@selector(didTapRespring)];
    y += 62;

    self.openSettingsBtn = [self makeButton:@"3 · Open Control Center settings"
                                          y:y
                                      color:[UIColor colorWithWhite:0.22 alpha:1.0]
                                     action:@selector(didTapOpenSettings)];
    y += 62;

    self.testCaptureBtn = [self makeButton:@"Test · Capture current screen"
                                         y:y
                                     color:[UIColor colorWithWhite:0.18 alpha:1.0]
                                    action:@selector(didTapTestCapture)];
    y += 62;

    // Diagnostics button — fires the full on-device inspection and shows it
    // in a scrollable sheet so it can be screenshotted and sent back.
    self.diagnosticsBtn = [self makeButton:@"Diagnostics"
                                         y:y
                                     color:[UIColor colorWithRed:0.3 green:0.2 blue:0.4 alpha:1.0]
                                    action:@selector(didTapDiagnostics)];
    y += 72;

    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 80)];
    footer.text = @"After step 1 + 2, open Settings → Control Center and add "
                  @"'ClearShot' to your included controls. Then swipe into "
                  @"Control Center from any app and tap it.\n\n"
                  @"If anything fails, tap Diagnostics and screenshot the result.";
    footer.textColor = [UIColor grayColor];
    footer.font = [UIFont systemFontOfSize:12];
    footer.numberOfLines = 0;
    [self.scrollView addSubview:footer];
    y += 90;

    self.scrollView.contentSize = CGSizeMake(w, y);
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
    [self.scrollView addSubview:b];
    return b;
}

#pragma mark - Status

- (void)refreshStatus {
    if ([CSInstaller isModuleInstalled]) {
        self.statusLabel.text = @"✅ Module installed in\n/Library/ControlCenter/Bundles/\n\nIf it doesn't appear in Settings yet, respring.";
        self.statusLabel.textColor = [UIColor systemGreenColor];
    } else {
        self.statusLabel.text = @"⚠️ Module not installed yet.\n\nTap step 1 to copy ClearShotModule.bundle to the system Control Center directory.";
        self.statusLabel.textColor = [UIColor systemOrangeColor];
    }
}

#pragma mark - Actions

- (void)didTapInstall {
    NSError *err = nil;
    BOOL ok = [CSInstaller installModuleReturningError:&err];
    if (ok) {
        [self alert:@"Installed"
            message:@"Module copied to /Library/ControlCenter/Bundles/.\n\nNow respring (step 2)."];
    } else {
        // Verbose error — the user can screenshot the whole thing.
        [self longMessageSheet:@"Install failed"
                       message:(err.localizedDescription ?: @"unknown")];
    }
    [self refreshStatus];
}

- (void)didTapRespring {
    [self alert:@"Respring"
         message:@"SpringBoard will be restarted. Your screen will go black for ~3 s."
    confirmTitle:@"Respring"
   confirmHandler:^{
        [CSInstaller respring];
    }];
}

- (void)didTapOpenSettings {
    NSURL *u = [NSURL URLWithString:@"App-Prefs:root=ControlCenter"];
    if ([[UIApplication sharedApplication] canOpenURL:u]) {
        [[UIApplication sharedApplication] openURL:u options:@{} completionHandler:nil];
    } else {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
                                           options:@{}
                                 completionHandler:nil];
    }
}

- (void)didTapTestCapture {
    NSString *path = nil;
    UIImage *shot = [CSInstaller captureCurrentScreenReportingPath:&path];
    if (!shot) {
        [self longMessageSheet:@"Capture failed"
                       message:[NSString stringWithFormat:
                                @"No capture method produced an image.\n\n%@\n\n"
                                @"If this persists, tap Diagnostics for details.",
                                path ?: @"(no path)"]];
        return;
    }
    [CSInstaller saveImageToPhotos:shot completion:^(BOOL ok, NSError *err) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSString *title = ok ? @"Saved" : @"Save failed";
            NSString *msg;
            if (ok) {
                msg = [NSString stringWithFormat:
                       @"Screenshot saved to your Photos library.\n\nPath used:\n%@",
                       path];
            } else {
                msg = [NSString stringWithFormat:
                       @"Photos save error: %@\n\nCapture path used:\n%@",
                       err.localizedDescription ?: @"unknown", path];
            }
            [self longMessageSheet:title message:msg];
        });
    }];
}

- (void)didTapDiagnostics {
    NSString *report = [CSInstaller diagnosticReport];
    [self longMessageSheet:@"Diagnostics" message:report];
}

#pragma mark - Helpers

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

- (void)alert:(NSString *)title
       message:(NSString *)msg
  confirmTitle:(NSString *)confirmTitle
confirmHandler:(void (^)(void))handler {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:confirmTitle
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction * _Nonnull action) {
        if (handler) handler();
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

// For diagnostics / install errors: a full-height modal with the message in
// a scrollable UITextView so even long reports are readable (UIAlertController
// truncates long bodies on small screens).
- (void)longMessageSheet:(NSString *)title message:(NSString *)msg {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];

    UILabel *header = [[UILabel alloc] init];
    header.text = title;
    header.textColor = [UIColor whiteColor];
    header.font = [UIFont systemFontOfSize:22 weight:UIFontWeightBold];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:header];

    UITextView *tv = [[UITextView alloc] init];
    tv.text = msg;
    tv.editable = NO;
    tv.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    tv.textColor = [UIColor whiteColor];
    tv.font = [UIFont fontWithName:@"Menlo" size:12];
    tv.layer.cornerRadius = 8;
    tv.textContainerInset = UIEdgeInsetsMake(10, 10, 10, 10);
    tv.translatesAutoresizingMaskIntoConstraints = NO;
    [vc.view addSubview:tv];

    UIButton *copy = [UIButton buttonWithType:UIButtonTypeSystem];
    [copy setTitle:@"Copy" forState:UIControlStateNormal];
    [copy setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    copy.backgroundColor = [UIColor systemBlueColor];
    copy.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    copy.layer.cornerRadius = 10;
    copy.translatesAutoresizingMaskIntoConstraints = NO;
    [copy addTarget:self action:@selector(copyFromTextView:) forControlEvents:UIControlEventTouchUpInside];
    copy.accessibilityValue = msg;    // stash the text for the action handler
    [vc.view addSubview:copy];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setTitle:@"Close" forState:UIControlStateNormal];
    [close setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    close.backgroundColor = [UIColor colorWithWhite:0.25 alpha:1.0];
    close.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    close.layer.cornerRadius = 10;
    close.translatesAutoresizingMaskIntoConstraints = NO;
    [close addTarget:self action:@selector(dismissSheet:) forControlEvents:UIControlEventTouchUpInside];
    [vc.view addSubview:close];

    UILayoutGuide *g = vc.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [header.topAnchor      constraintEqualToAnchor:g.topAnchor constant:20],
        [header.leadingAnchor  constraintEqualToAnchor:g.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-20],

        [tv.topAnchor      constraintEqualToAnchor:header.bottomAnchor constant:16],
        [tv.leadingAnchor  constraintEqualToAnchor:g.leadingAnchor constant:16],
        [tv.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [tv.bottomAnchor   constraintEqualToAnchor:copy.topAnchor constant:-12],

        [copy.leadingAnchor  constraintEqualToAnchor:g.leadingAnchor constant:16],
        [copy.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-12],
        [copy.heightAnchor   constraintEqualToConstant:48],
        [copy.widthAnchor    constraintEqualToAnchor:close.widthAnchor],

        [close.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-16],
        [close.heightAnchor   constraintEqualToConstant:48],
        [close.bottomAnchor   constraintEqualToAnchor:g.bottomAnchor constant:-16],
    ]];

    vc.modalPresentationStyle = UIModalPresentationFullScreen;
    [self presentViewController:vc animated:YES completion:nil];
}

- (void)copyFromTextView:(UIButton *)sender {
    NSString *txt = sender.accessibilityValue;
    if (txt) [UIPasteboard generalPasteboard].string = txt;
    // Flash button to confirm.
    UIColor *orig = sender.backgroundColor;
    [UIView animateWithDuration:0.1 animations:^{
        sender.backgroundColor = [UIColor systemGreenColor];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.3 delay:0.2 options:0 animations:^{
            sender.backgroundColor = orig;
        } completion:nil];
    }];
}

- (void)dismissSheet:(UIButton *)sender {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end
