#import "FBAppearance.h"

NSNotificationName const FBAppearanceDidChangeNotification = @"FBAppearanceDidChangeNotification";

static NSString * const kColorKey = @"FBBarColorHex";
static NSString * const kAlphaKey = @"FBBarAlpha";

static UIColor *ColorFromHex(NSString *hex) {
    if (!hex || hex.length < 6) return nil;
    unsigned int rgb = 0;
    NSScanner *s = [NSScanner scannerWithString:hex];
    if ([hex hasPrefix:@"#"]) s.scanLocation = 1;
    if (![s scanHexInt:&rgb]) return nil;
    CGFloat r = ((rgb >> 16) & 0xFF) / 255.0;
    CGFloat g = ((rgb >>  8) & 0xFF) / 255.0;
    CGFloat b = ( rgb        & 0xFF) / 255.0;
    return [UIColor colorWithRed:r green:g blue:b alpha:1.0];
}

static NSString *HexFromColor(UIColor *c) {
    CGFloat r, g, b, a;
    if (![c getRed:&r green:&g blue:&b alpha:&a]) return @"#141820";
    int ri = (int)roundf(r * 255);
    int gi = (int)roundf(g * 255);
    int bi = (int)roundf(b * 255);
    return [NSString stringWithFormat:@"#%02X%02X%02X", ri, gi, bi];
}

@implementation FBAppearance

+ (UIColor *)barColor {
    NSString *hex = [[NSUserDefaults standardUserDefaults] stringForKey:kColorKey];
    UIColor *c = ColorFromHex(hex);
    return c ?: [UIColor colorWithRed:0.08 green:0.09 blue:0.12 alpha:1.0];
}

+ (void)setBarColor:(UIColor *)color {
    [[NSUserDefaults standardUserDefaults] setObject:HexFromColor(color) forKey:kColorKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:FBAppearanceDidChangeNotification object:nil];
}

+ (CGFloat)barOpacity {
    id raw = [[NSUserDefaults standardUserDefaults] objectForKey:kAlphaKey];
    if (!raw) return 0.9;
    CGFloat v = [raw doubleValue];
    return MAX(0.1, MIN(1.0, v));
}

+ (void)setBarOpacity:(CGFloat)value {
    value = MAX(0.1, MIN(1.0, value));
    [[NSUserDefaults standardUserDefaults] setDouble:value forKey:kAlphaKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSNotificationCenter defaultCenter] postNotificationName:FBAppearanceDidChangeNotification object:nil];
}

+ (UIColor *)effectiveBackgroundColor {
    return [[self barColor] colorWithAlphaComponent:[self barOpacity]];
}

@end
