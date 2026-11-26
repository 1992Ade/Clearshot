#import <UIKit/UIKit.h>

// ControlCenterUIKit private — forward-declared here so we don't need the
// headers. CCUIToggleModule is the common parent for momentary / toggle CC
// buttons and has been stable across iOS 11–16. The runtime resolves
// everything by selector dispatch.
@interface CCUIToggleModule : UIViewController
@property (nonatomic) BOOL selected;
- (void)setSelected:(BOOL)selected;
- (BOOL)isSelected;
@end

@interface CSModule : CCUIToggleModule
@end
