#import <UIKit/UIKit.h>

@interface FBAppearance : NSObject

/// Background color of the floating bar, without the alpha component.
+ (UIColor *)barColor;
+ (void)setBarColor:(UIColor *)color;

/// Bar background opacity, 0.1 ... 1.0.
+ (CGFloat)barOpacity;
+ (void)setBarOpacity:(CGFloat)value;

/// Convenience: barColor combined with barOpacity.
+ (UIColor *)effectiveBackgroundColor;

/// Notification posted after barColor or barOpacity changes.
extern NSNotificationName const FBAppearanceDidChangeNotification;

@end
