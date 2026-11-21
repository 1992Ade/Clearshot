#import "FBMainViewController.h"
#import "FBPiPController.h"
#import "FBConfigViewController.h"
#import "FBButtonConfig.h"
#import <Photos/Photos.h>

@interface FBMainViewController () <FBConfigViewControllerDelegate>
@property (strong, nonatomic) FBPiPController *pip;
@property (strong, nonatomic) UIView *pipHost;
@property (strong, nonatomic) UIButton *startBtn;
@property (strong, nonatomic) UIButton *stopBtn;
@property (strong, nonatomic) UIButton *configBtn;
@property (strong, nonatomic) UILabel *statusLabel;
@property (strong, nonatomic) UILabel *buttonSummary;
@end

@implementation FBMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    [self buildUI];
    [self requestPhotosPermission];
    self.pip = [[FBPiPController alloc] initWithHostView:self.pipHost];
    [self refreshSummary];
}

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
    title.text = @"FloatBar";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:34 weight:UIFontWeightBold];
    [self.view addSubview:title];
    y += 44;

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 60)];
    sub.text = @"Barre flottante : retour, home, app switcher, capture d'écran. Ordre et activation configurables.";
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:14];
    sub.numberOfLines = 0;
    [self.view addSubview:sub];
    y += 70;

    self.pipHost = [[UIView alloc] initWithFrame:CGRectMake(20, y, w - 40, 140)];
    self.pipHost.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.pipHost.layer.cornerRadius = 14;
    self.pipHost.clipsToBounds = YES;
    [self.view addSubview:self.pipHost];
    UILabel *hostHint = [[UILabel alloc] initWithFrame:self.pipHost.bounds];
    hostHint.text = @"Source PiP\n(la barre apparaît ici et au-dessus de toutes les apps après activation)";
    hostHint.textAlignment = NSTextAlignmentCenter;
    hostHint.numberOfLines = 0;
    hostHint.font = [UIFont systemFontOfSize:12];
    hostHint.textColor = [UIColor grayColor];
    [self.pipHost addSubview:hostHint];
    y += 150;

    self.configBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.configBtn.frame = CGRectMake(20, y, w - 40, 48);
    [self.configBtn setTitle:@"⚙ Configurer les boutons…" forState:UIControlStateNormal];
    [self.configBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.configBtn.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightMedium];
    self.configBtn.backgroundColor = [UIColor colorWithWhite:0.22 alpha:1.0];
    self.configBtn.layer.cornerRadius = 12;
    [self.configBtn addTarget:self action:@selector(didTapConfig) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.configBtn];
    y += 58;

    self.buttonSummary = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 24)];
    self.buttonSummary.font = [UIFont systemFontOfSize:13];
    self.buttonSummary.textColor = [UIColor systemBlueColor];
    self.buttonSummary.textAlignment = NSTextAlignmentCenter;
    [self.view addSubview:self.buttonSummary];
    y += 34;

    self.startBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.startBtn.frame = CGRectMake(20, y, w - 40, 54);
    [self.startBtn setTitle:@"Activer la barre flottante" forState:UIControlStateNormal];
    [self.startBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.startBtn.backgroundColor = [UIColor systemBlueColor];
    self.startBtn.layer.cornerRadius = 14;
    [self.startBtn addTarget:self action:@selector(didTapStart) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startBtn];
    y += 62;

    self.stopBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.stopBtn.frame = CGRectMake(20, y, w - 40, 54);
    [self.stopBtn setTitle:@"Désactiver la barre" forState:UIControlStateNormal];
    [self.stopBtn setTitleColor:[UIColor systemRedColor] forState:UIControlStateNormal];
    self.stopBtn.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    self.stopBtn.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    self.stopBtn.layer.cornerRadius = 14;
    [self.stopBtn addTarget:self action:@selector(didTapStop) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.stopBtn];
    y += 70;

    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textColor = [UIColor lightGrayColor];
    self.statusLabel.numberOfLines = 0;
    [self.view addSubview:self.statusLabel];
}

- (void)refreshSummary {
    NSArray *enabled = [FBButtonConfig enabledOrderedButtons];
    NSMutableString *s = [NSMutableString stringWithString:@"Barre : "];
    for (NSInteger i = 0; i < (NSInteger)enabled.count; i++) {
        FBButtonType t = (FBButtonType)[enabled[i] integerValue];
        if (i > 0) [s appendString:@"  "];
        [s appendString:[FBButtonConfig iconForType:t]];
    }
    if (enabled.count == 0) [s appendString:@"(aucun bouton)"];
    self.buttonSummary.text = s;
}

- (void)requestPhotosPermission {
    [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelAddOnly handler:^(PHAuthorizationStatus status) {}];
}

#pragma mark - Actions

- (void)didTapConfig {
    FBConfigViewController *cfg = [FBConfigViewController new];
    cfg.delegate = self;
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:cfg];
    cfg.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemDone target:self action:@selector(dismissConfig)];
    [self presentViewController:nav animated:YES completion:nil];
}

- (void)dismissConfig {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)didTapStart {
    if (![FBPiPController isAvailable]) {
        self.statusLabel.text = @"⚠️ PiP indisponible sur cet appareil.";
        self.statusLabel.textColor = [UIColor systemOrangeColor];
        return;
    }
    if ([FBButtonConfig enabledOrderedButtons].count == 0) {
        self.statusLabel.text = @"⚠️ Active au moins un bouton dans les réglages.";
        self.statusLabel.textColor = [UIColor systemOrangeColor];
        return;
    }
    [self.pip start];
    self.statusLabel.text = @"✓ Barre active. Home-swipe vers n'importe quelle app.";
    self.statusLabel.textColor = [UIColor systemGreenColor];
}

- (void)didTapStop {
    [self.pip stop];
    self.statusLabel.text = @"Barre désactivée.";
    self.statusLabel.textColor = [UIColor lightGrayColor];
}

#pragma mark - FBConfigViewControllerDelegate

- (void)configViewControllerDidChange:(FBConfigViewController *)vc {
    [self.pip reloadConfig];
    [self refreshSummary];
}

@end
