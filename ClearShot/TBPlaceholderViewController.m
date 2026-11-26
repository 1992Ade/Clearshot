#import "TBPlaceholderViewController.h"

@interface TBPlaceholderViewController ()
@property (copy, nonatomic)   NSString *sectionTitle;
@property (copy, nonatomic)   NSString *blurb;
@property (strong, nonatomic) NSArray<NSString *> *planned;
@end

@implementation TBPlaceholderViewController

+ (instancetype)withTitle:(NSString *)title
                    blurb:(NSString *)blurb
                  planned:(NSArray<NSString *> *)plannedFeatures {
    TBPlaceholderViewController *vc = [[self alloc] init];
    vc.sectionTitle = title;
    vc.blurb = blurb;
    vc.planned = plannedFeatures;
    vc.title = title;
    return vc;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.12 alpha:1.0];

    CGFloat w = self.view.bounds.size.width;
    CGFloat y = 80;

    UILabel *t = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 40)];
    t.text = self.sectionTitle;
    t.textColor = [UIColor whiteColor];
    t.font = [UIFont systemFontOfSize:30 weight:UIFontWeightBold];
    [self.view addSubview:t];
    y += 50;

    UILabel *b = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 100)];
    b.text = self.blurb;
    b.textColor = [UIColor lightGrayColor];
    b.font = [UIFont systemFontOfSize:14];
    b.numberOfLines = 0;
    [b sizeToFit];
    CGRect bf = b.frame; bf.size.width = w - 40; b.frame = bf;
    [self.view addSubview:b];
    y += b.frame.size.height + 20;

    UILabel *soon = [[UILabel alloc] initWithFrame:CGRectMake(20, y, w - 40, 30)];
    soon.text = @"🚧 Coming soon";
    soon.textColor = [UIColor systemYellowColor];
    soon.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
    [self.view addSubview:soon];
    y += 36;

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(20, y, w - 40, 44 + 28 * self.planned.count)];
    card.backgroundColor = [UIColor colorWithWhite:0.14 alpha:1.0];
    card.layer.cornerRadius = 12;
    [self.view addSubview:card];

    UILabel *hdr = [[UILabel alloc] initWithFrame:CGRectMake(14, 10, card.bounds.size.width - 28, 20)];
    hdr.text = @"Planned";
    hdr.textColor = [UIColor whiteColor];
    hdr.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    [card addSubview:hdr];

    CGFloat ly = 36;
    for (NSString *item in self.planned) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, ly, card.bounds.size.width - 28, 22)];
        l.text = [NSString stringWithFormat:@"• %@", item];
        l.textColor = [UIColor lightGrayColor];
        l.font = [UIFont systemFontOfSize:14];
        [card addSubview:l];
        ly += 24;
    }
}

@end
