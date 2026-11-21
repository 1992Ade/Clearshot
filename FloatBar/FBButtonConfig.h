#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, FBButtonType) {
    FBButtonTypeHome = 0,
    FBButtonTypeBack,
    FBButtonTypeAppSwitcher,
    FBButtonTypeCapture
};

@interface FBButtonConfig : NSObject

+ (NSString *)labelForType:(FBButtonType)type;
+ (NSString *)iconForType:(FBButtonType)type;

/// Persisted ordered list of button types that are currently enabled.
+ (NSArray<NSNumber *> *)enabledOrderedButtons;

/// Replace the stored enabled-ordered list.
+ (void)setEnabledOrderedButtons:(NSArray<NSNumber *> *)buttons;

/// All known buttons in their natural order.
+ (NSArray<NSNumber *> *)allButtons;

@end
