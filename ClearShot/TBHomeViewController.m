#import "TBHomeViewController.h"
#import "CSMainViewController.h"
#import "LSMainViewController.h"
#import "SVMainViewController.h"
#import "TWMainViewController.h"
#import "RSMainViewController.h"
#import "ADMainViewController.h"
#import "BCMainViewController.h"
#import "ABMainViewController.h"
#import "RMMainViewController.h"
#import "ARMainViewController.h"
#import "TBPlaceholderViewController.h"
#import "TBAboutViewController.h"

typedef UIViewController *(^TBSectionFactory)(void);

@interface TBSection : NSObject
@property (copy) NSString *title;
@property (copy) NSString *subtitle;
@property (copy) NSString *symbol;
@property (strong) UIColor *tint;
@property (copy) TBSectionFactory factory;
@end
@implementation TBSection
@end

@interface TBHomeViewController () <UICollectionViewDataSource, UICollectionViewDelegate>
@property (strong, nonatomic) UICollectionView *grid;
@property (strong, nonatomic) NSArray<TBSection *> *sections;
@end

@implementation TBHomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.06 green:0.06 blue:0.10 alpha:1.0];
    self.title = @"TrollBox";
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *a = [[UINavigationBarAppearance alloc] init];
        [a configureWithOpaqueBackground];
        a.backgroundColor = self.view.backgroundColor;
        a.titleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        a.largeTitleTextAttributes = @{ NSForegroundColorAttributeName: UIColor.whiteColor };
        self.navigationController.navigationBar.standardAppearance = a;
        self.navigationController.navigationBar.scrollEdgeAppearance = a;
        self.navigationController.navigationBar.prefersLargeTitles = YES;
    }

    [self buildSections];
    [self buildGrid];
}

- (void)buildSections {
    NSMutableArray *s = [NSMutableArray array];

    // ----- Top (user-requested ordering) :
    //   LocSim / Ad Blocking / ResSetter / Badge Color -----
    [s addObject:[self section:@"LocSim"
                      subtitle:@"Simulated GPS location"
                        symbol:@"location.fill"
                          tint:[UIColor systemGreenColor]
                       factory:^UIViewController *{ return [[LSMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Ad Blocking"
                      subtitle:@"MYbloXX-style global HTTP proxy blocker"
                        symbol:@"shield.lefthalf.filled"
                          tint:[UIColor systemRedColor]
                       factory:^UIViewController *{ return [[ABMainViewController alloc] init]; }]];

    [s addObject:[self section:@"ResSetter"
                      subtitle:@"Display resolution tweaks"
                        symbol:@"rectangle.expand.vertical"
                          tint:[UIColor systemYellowColor]
                       factory:^UIViewController *{ return [[RSMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Badge Color"
                      subtitle:@"Recolor SpringBoard notification badges"
                        symbol:@"paintbrush.fill"
                          tint:[UIColor systemPinkColor]
                       factory:^UIViewController *{ return [[BCMainViewController alloc] init]; }]];

    // ----- Then the rest -----
    [s addObject:[self section:@"ClearShot"
                      subtitle:@"CC screenshot, bypass FLAG_SECURE"
                        symbol:@"camera.viewfinder"
                          tint:[UIColor systemBlueColor]
                       factory:^UIViewController *{ return [[CSMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Supervise"
                      subtitle:@"Fake org name, supervised flag"
                        symbol:@"eye.fill"
                          tint:[UIColor systemPurpleColor]
                       factory:^UIViewController *{ return [[SVMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Tweaks"
                      subtitle:@"Inject dylibs / bundles into apps"
                        symbol:@"wrench.and.screwdriver.fill"
                          tint:[UIColor systemOrangeColor]
                       factory:^UIViewController *{ return [[TWMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Reclaim Space"
                      subtitle:@"Delete analytics/crash/support logs iOS forgot"
                        symbol:@"trash.fill"
                          tint:[UIColor systemBrownColor]
                       factory:^UIViewController *{ return [[RMMainViewController alloc] init]; }]];

    [s addObject:[self section:@"AppRepack"
                      subtitle:@"Install older compatible app versions"
                        symbol:@"shippingbox.fill"
                          tint:[UIColor systemMintColor]
                       factory:^UIViewController *{ return [[ARMainViewController alloc] init]; }]];

    [s addObject:[self section:@"Jaility"
                      subtitle:@"System tweaks (haxi0)"
                        symbol:@"slider.horizontal.3"
                          tint:[UIColor systemIndigoColor]
                       factory:^UIViewController *{
        return [TBPlaceholderViewController
                 withTitle:@"Jaility"
                     blurb:@"Port of Jaility by haxi0 (org.haxi0.Jaility v3.1.1). "
                           @"A pile of small iOS system tweaks you flip on / off. "
                           @"Scaffold in place; toggles pending."
                   planned:@[ @"Hide / Show the Mute Switch in Control Center",
                              @"Disable / Enable Locking After Respring",
                              @"Edit the \"Placeholder text\" demo string",
                              @"One-tap Remove Modifications" ]];
    }]];

    [s addObject:[self section:@"About Device"
                      subtitle:@"Battery, CPU, RAM, network"
                        symbol:@"iphone"
                          tint:[UIColor systemTealColor]
                       factory:^UIViewController *{ return [[ADMainViewController alloc] init]; }]];

    [s addObject:[self section:@"About"
                      subtitle:@"Version, credits, license"
                        symbol:@"info.circle.fill"
                          tint:[UIColor systemGrayColor]
                       factory:^UIViewController *{ return [[TBAboutViewController alloc] init]; }]];

    self.sections = s;
}

- (TBSection *)section:(NSString *)title
              subtitle:(NSString *)subtitle
                symbol:(NSString *)symbol
                  tint:(UIColor *)tint
               factory:(TBSectionFactory)factory {
    TBSection *s = [[TBSection alloc] init];
    s.title = title; s.subtitle = subtitle;
    s.symbol = symbol; s.tint = tint;
    s.factory = factory;
    return s;
}

- (void)buildGrid {
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.minimumInteritemSpacing = 14;
    layout.minimumLineSpacing = 14;
    layout.sectionInset = UIEdgeInsetsMake(16, 16, 16, 16);

    self.grid = [[UICollectionView alloc] initWithFrame:self.view.bounds
                                   collectionViewLayout:layout];
    self.grid.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.grid.backgroundColor = self.view.backgroundColor;
    self.grid.dataSource = self;
    self.grid.delegate = self;
    [self.grid registerClass:UICollectionViewCell.class
     forCellWithReuseIdentifier:@"card"];
    [self.view addSubview:self.grid];
}

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    UICollectionViewFlowLayout *l = (UICollectionViewFlowLayout *)self.grid.collectionViewLayout;
    CGFloat side = self.view.bounds.size.width;
    CGFloat cellW = floor((side - 16 * 2 - 14) / 2.0);
    l.itemSize = CGSizeMake(cellW, 110);
}

#pragma mark - Collection

- (NSInteger)collectionView:(UICollectionView *)cv numberOfItemsInSection:(NSInteger)s {
    return self.sections.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)cv
                   cellForItemAtIndexPath:(NSIndexPath *)ip {
    UICollectionViewCell *cell = [cv dequeueReusableCellWithReuseIdentifier:@"card"
                                                               forIndexPath:ip];
    for (UIView *v in cell.contentView.subviews) [v removeFromSuperview];

    TBSection *s = self.sections[ip.item];
    cell.contentView.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    cell.contentView.layer.cornerRadius = 16;
    cell.contentView.layer.masksToBounds = YES;

    CGFloat w = cell.contentView.bounds.size.width;

    UIImageView *icon = [[UIImageView alloc] initWithFrame:CGRectMake(14, 12, 28, 28)];
    icon.contentMode = UIViewContentModeScaleAspectFit;
    icon.tintColor = s.tint;
    if (@available(iOS 13.0, *)) {
        icon.image = [UIImage systemImageNamed:s.symbol];
    }
    [cell.contentView addSubview:icon];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 48, w - 28, 22)];
    title.text = s.title;
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    [cell.contentView addSubview:title];

    UILabel *sub = [[UILabel alloc] initWithFrame:CGRectMake(14, 70, w - 28, 34)];
    sub.text = s.subtitle;
    sub.textColor = [UIColor lightGrayColor];
    sub.font = [UIFont systemFontOfSize:12];
    sub.numberOfLines = 2;
    [cell.contentView addSubview:sub];

    return cell;
}

- (void)collectionView:(UICollectionView *)cv didSelectItemAtIndexPath:(NSIndexPath *)ip {
    [cv deselectItemAtIndexPath:ip animated:YES];
    TBSection *s = self.sections[ip.item];
    UIViewController *vc = s.factory();
    [self.navigationController pushViewController:vc animated:YES];
}

@end
