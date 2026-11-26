#import "SVMainViewController.h"
#import "CSProcessUtils.h"
#import "TBSupervisionManager.h"

// Plist-write logic now lives in TBSupervisionManager so the Ad Blocking
// section can reuse it. This view controller is a thin UI shell on top.

@interface SVMainViewController ()
@property (strong, nonatomic) UITextField *orgNameField;
@property (strong, nonatomic) UILabel *statusLabel;
@end

@implementation SVMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"Supervise";
    [self buildUI];
    [self refreshStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

#pragma mark - UI

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
    title.text = @"Supervise";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    [self.view addSubview:title];
    y += 48;

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 100)];
    sub.text = @"Marks this device as supervised and optionally stamps it "
               @"with your own organisation name. iOS treats supervised "
               @"devices differently in Settings, Lock Screen and MDM.";
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:14];
    sub.numberOfLines = 0;
    [self.view addSubview:sub];
    y += 110;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, w - 40, 72)];
    card.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    card.layer.cornerRadius = 12;
    [self.view addSubview:card];

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, card.bounds.size.width - 28, 72)];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.numberOfLines = 0;
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    [card addSubview:self.statusLabel];
    y += 84;

    self.orgNameField = [[UITextField alloc] initWithFrame:CGRectMake(20, y, w - 40, 48)];
    self.orgNameField.placeholder = @"Organisation name (optional)";
    self.orgNameField.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    self.orgNameField.textColor = [UIColor whiteColor];
    self.orgNameField.font = [UIFont systemFontOfSize:16];
    self.orgNameField.autocapitalizationType = UITextAutocapitalizationTypeWords;
    self.orgNameField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.orgNameField.layer.cornerRadius = 10;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    self.orgNameField.leftView = pad;
    self.orgNameField.leftViewMode = UITextFieldViewModeAlways;
    [self.view addSubview:self.orgNameField];
    y += 60;

    [self makeButton:@"Supervise this device" y:y color:[UIColor systemBlueColor] action:@selector(didTapSupervise)];
    y += 62;

    [self makeButton:@"Remove supervision" y:y color:[UIColor systemOrangeColor] action:@selector(didTapUnsupervise)];
    y += 62;

    UILabel *footer = [[UILabel alloc] initWithFrame:CGRectMake(20, y + 6, w - 40, 80)];
    footer.text = @"A respring is needed for iOS to pick up the change. "
                  @"Both buttons offer it right after they write the file.";
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

#pragma mark - Status

- (void)refreshStatus {
    BOOL isSup = [TBSupervisionManager isSupervised];
    NSString *org = [TBSupervisionManager organizationName];
    BOOL mdm = [TBSupervisionManager isSupervisedByExternalMDM];

    if (mdm) {
        self.statusLabel.text = org.length
            ? [NSString stringWithFormat:@"⚠️ External MDM detected\n(%@)", org]
            : @"⚠️ External MDM detected";
        self.statusLabel.textColor = [UIColor systemOrangeColor];
    } else if (isSup) {
        self.statusLabel.text = org.length
            ? [NSString stringWithFormat:@"✅ Supervised as\n%@", org]
            : @"✅ Supervised (no organisation name)";
        self.statusLabel.textColor = [UIColor systemGreenColor];
        if (org.length) self.orgNameField.text = org;
    } else {
        self.statusLabel.text = @"⚠️ Not supervised.";
        self.statusLabel.textColor = [UIColor lightGrayColor];
    }
}

#pragma mark - Actions

- (void)didTapSupervise {
    NSString *org = [self.orgNameField.text
                     stringByTrimmingCharactersInSet:
                     NSCharacterSet.whitespaceAndNewlineCharacterSet];

    NSError *writeErr = nil;
    if (![TBSupervisionManager supervise:org error:&writeErr]) {
        [self alert:@"Supervise failed"
            message:writeErr.localizedDescription ?: @"unknown"];
        return;
    }

    [self promptRespringWithTitle:@"Done"
                          message:org.length
                                   ? [NSString stringWithFormat:
                                      @"Device will be marked supervised as "
                                      @"\"%@\" after respring.", org]
                                   : @"Device will be marked supervised "
                                     @"after respring."];
    [self refreshStatus];
}

- (void)didTapUnsupervise {
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:@"Remove supervision"
                              message:@"If any configuration profile depends "
                                      @"on supervision, this can break it. "
                                      @"Continue?"
                              preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                           style:UIAlertActionStyleCancel
                                         handler:nil]];
    [ac addAction:[UIAlertAction actionWithTitle:@"Remove"
                                           style:UIAlertActionStyleDestructive
                                         handler:^(UIAlertAction *a) {
        NSError *werr = nil;
        if (![TBSupervisionManager unsupervise:&werr]) {
            [self alert:@"Un-supervise failed"
                message:werr.localizedDescription ?: @"unknown"];
            return;
        }
        [self promptRespringWithTitle:@"Done"
                              message:@"Supervision will be removed after "
                                      @"respring."];
        [self refreshStatus];
    }]];
    [self presentViewController:ac animated:YES completion:nil];
}

#pragma mark - Respring prompt

- (void)promptRespringWithTitle:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController
                              alertControllerWithTitle:title
                              message:msg
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

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
