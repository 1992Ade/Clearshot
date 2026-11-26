#import "LSMainViewController.h"
#import "LSManager.h"
#import <CoreLocation/CoreLocation.h>
#import <objc/runtime.h>

@interface LSMainViewController ()
@property (strong, nonatomic) UITextField *latField;
@property (strong, nonatomic) UITextField *lngField;
@property (strong, nonatomic) UILabel *statusLabel;
@end

@implementation LSMainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];
    self.title = @"LocSim";
    [self buildUI];
    [self refreshStatus];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self refreshStatus];
}

- (void)buildUI {
    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
    title.text = @"LocSim";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    [self.view addSubview:title];
    y += 48;

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 60)];
    sub.text = @"Feed a fake GPS location to every app on this device via "
               @"CLSimulationManager.";
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:14];
    sub.numberOfLines = 0;
    [self.view addSubview:sub];
    y += 70;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, w - 40, 60)];
    card.backgroundColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    card.layer.cornerRadius = 12;
    [self.view addSubview:card];
    self.statusLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, 0, card.bounds.size.width - 28, 60)];
    self.statusLabel.textColor = [UIColor whiteColor];
    self.statusLabel.font = [UIFont systemFontOfSize:14];
    self.statusLabel.textAlignment = NSTextAlignmentCenter;
    self.statusLabel.numberOfLines = 0;
    [card addSubview:self.statusLabel];
    y += 72;

    CGFloat halfW = (w - 40 - 10) / 2.0;
    self.latField = [self makeField:@"Latitude"  x:20                y:y width:halfW];
    self.lngField = [self makeField:@"Longitude" x:(20 + halfW + 10) y:y width:halfW];
    y += 60;

    [self makeButton:@"Start simulation"
                   y:y
               color:[UIColor systemBlueColor]
              action:@selector(didTapStart)];
    y += 62;

    [self makeButton:@"Stop simulation"
                   y:y
               color:[UIColor systemOrangeColor]
              action:@selector(didTapStop)];
    y += 72;

    UILabel *presetsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 20)];
    presetsLabel.text = @"Quick presets";
    presetsLabel.textColor = [UIColor lightGrayColor];
    presetsLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [self.view addSubview:presetsLabel];
    y += 26;

    NSArray *presets = @[
        @{ @"name": @"Paris",      @"lat": @48.8566,  @"lng": @2.3522  },
        @{ @"name": @"New York",   @"lat": @40.7128,  @"lng": @-74.0060},
        @{ @"name": @"Tokyo",      @"lat": @35.6895,  @"lng": @139.6917},
        @{ @"name": @"Null Island",@"lat": @0.0,      @"lng": @0.0     },
    ];
    for (NSDictionary *p in presets) {
        UIButton *b = [self makeButton:p[@"name"] y:y
                                 color:[UIColor colorWithWhite:0.22 alpha:1.0]
                                action:@selector(didTapPreset:)];
        b.tag = [presets indexOfObject:p];
        objc_setAssociatedObject(b, "preset", p, OBJC_ASSOCIATION_RETAIN);
        y += 58;
    }
}

- (UITextField *)makeField:(NSString *)placeholder x:(CGFloat)x y:(CGFloat)y width:(CGFloat)w {
    UITextField *f = [[UITextField alloc] initWithFrame:CGRectMake(x, y, w, 48)];
    f.placeholder = placeholder;
    f.backgroundColor = [UIColor colorWithWhite:0.18 alpha:1.0];
    f.textColor = [UIColor whiteColor];
    f.font = [UIFont systemFontOfSize:16];
    f.keyboardType = UIKeyboardTypeNumbersAndPunctuation;
    f.autocorrectionType = UITextAutocorrectionTypeNo;
    f.layer.cornerRadius = 10;
    UIView *pad = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 12, 1)];
    f.leftView = pad;
    f.leftViewMode = UITextFieldViewModeAlways;
    [self.view addSubview:f];
    return f;
}

- (UIButton *)makeButton:(NSString *)title y:(CGFloat)y color:(UIColor *)color action:(SEL)sel {
    CGFloat w = self.view.bounds.size.width;
    UIButton *b = [UIButton buttonWithType:UIButtonTypeSystem];
    b.frame = CGRectMake(20, y, w - 40, 48);
    [b setTitle:title forState:UIControlStateNormal];
    [b setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    b.backgroundColor = color;
    b.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightSemibold];
    b.layer.cornerRadius = 10;
    [b addTarget:self action:sel forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:b];
    return b;
}

#pragma mark - Status

- (void)refreshStatus {
    if ([LSManager isActive]) {
        self.statusLabel.text = @"✅ Currently simulating.";
        self.statusLabel.textColor = [UIColor systemGreenColor];
    } else {
        self.statusLabel.text = @"⚪️ Idle — enter coordinates then Start.";
        self.statusLabel.textColor = [UIColor lightGrayColor];
    }
}

#pragma mark - Actions

- (void)didTapStart {
    [self.view endEditing:YES];
    double lat = [self.latField.text doubleValue];
    double lng = [self.lngField.text doubleValue];
    if (lat == 0 && lng == 0 &&
        self.latField.text.length == 0 && self.lngField.text.length == 0) {
        [self alert:@"Missing coordinates"
            message:@"Enter a latitude and a longitude first, or tap one "
                    @"of the preset buttons below."];
        return;
    }
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:lat longitude:lng];
    [LSManager startWithLocation:loc];
    [self refreshStatus];
}

- (void)didTapStop {
    [LSManager stop];
    [self refreshStatus];
}

- (void)didTapPreset:(UIButton *)sender {
    NSDictionary *p = objc_getAssociatedObject(sender, "preset");
    if (!p) return;
    double lat = [p[@"lat"] doubleValue];
    double lng = [p[@"lng"] doubleValue];
    self.latField.text = [NSString stringWithFormat:@"%.4f", lat];
    self.lngField.text = [NSString stringWithFormat:@"%.4f", lng];
    CLLocation *loc = [[CLLocation alloc] initWithLatitude:lat longitude:lng];
    [LSManager startWithLocation:loc];
    [self refreshStatus];
}

- (void)alert:(NSString *)title message:(NSString *)msg {
    UIAlertController *ac = [UIAlertController alertControllerWithTitle:title
                                                                message:msg
                                                         preferredStyle:UIAlertControllerStyleAlert];
    [ac addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:ac animated:YES completion:nil];
}

@end
