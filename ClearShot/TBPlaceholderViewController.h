// ============================================================================
// TBPlaceholderViewController — reusable "Coming soon" screen.
//
// The Icons, Ad Blocking and ResSetter tabs don't have working code yet;
// rather than three empty VC files, we use one factory that takes a
// title, blurb, and a list of planned features. Once a tab's feature set
// is implemented it moves to its own view controller.
// ============================================================================

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface TBPlaceholderViewController : UIViewController

+ (instancetype)withTitle:(NSString *)title
                    blurb:(NSString *)blurb
                 planned:(NSArray<NSString *> *)plannedFeatures;

@end

NS_ASSUME_NONNULL_END
