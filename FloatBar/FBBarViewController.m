#import "FBBarViewController.h"
#import "FBButtonConfig.h"
#import "FBActions.h"
#import "FBAppearance.h"

static const CGFloat kButtonWidth = 56.0;
static const CGFloat kBarHeight = 56.0;

@interface FBBarViewController () <FBActionHost>
@property (strong, nonatomic) NSMutableArray<UIButton *> *buttons;
@property (strong, nonatomic) NSArray<NSNumber *> *orderedTypes;
@end

@implementation FBBarViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.buttons = [NSMutableArray new];
    [self applyAppearance];
    [self reloadFromConfig];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applyAppearance)
                                                 name:FBAppearanceDidChangeNotification
                                               object:nil];
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)applyAppearance {
    self.view.backgroundColor = [FBAppearance effectiveBackgroundColor];
}

- (CGFloat)preferredBarWidth {
    return MAX(kButtonWidth, kButtonWidth * (CGFloat)self.orderedTypes.count);
}

- (void)reloadFromConfig {
    for (UIButton *b in self.buttons) [b removeFromSuperview];
    [self.buttons removeAllObjects];

    self.orderedTypes = [FBButtonConfig enabledOrderedButtons];

    [self.orderedTypes enumerateObjectsUsingBlock:^(NSNumber *typeNum, NSUInteger idx, BOOL *stop) {
        FBButtonType type = (FBButtonType)typeNum.integerValue;
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        [btn setTitle:[FBButtonConfig iconForType:type] forState:UIControlStateNormal];
        [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        btn.titleLabel.font = [UIFont systemFontOfSize:20 weight:UIFontWeightSemibold];
        btn.tag = (NSInteger)type;
        [btn addTarget:self action:@selector(didTapButton:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:btn];
        [self.buttons addObject:btn];
    }];

    [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat w = self.view.bounds.size.width;
    CGFloat h = self.view.bounds.size.height;
    CGFloat slot = self.buttons.count > 0 ? (w / self.buttons.count) : w;
    for (NSInteger i = 0; i < (NSInteger)self.buttons.count; i++) {
        self.buttons[i].frame = CGRectMake(i * slot, 0, slot, h);
    }
}

- (void)didTapButton:(UIButton *)sender {
    FBButtonType type = (FBButtonType)sender.tag;
    [self flashButton:sender];
    [FBActions performAction:type host:self];
}

- (void)flashButton:(UIButton *)btn {
    btn.alpha = 0.3;
    [UIView animateWithDuration:0.25 animations:^{ btn.alpha = 1.0; }];
}

#pragma mark - FBActionHost (self-hide during capture)

- (void)actionsWillCapture {
    self.view.alpha = 0;
}

- (void)actionsDidCaptureWithSuccess:(BOOL)success {
    dispatch_async(dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.25 animations:^{
            self.view.alpha = 1.0;
        }];
    });
}

@end
