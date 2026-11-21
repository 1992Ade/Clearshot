#import <UIKit/UIKit.h>

@class FBConfigViewController;

@protocol FBConfigViewControllerDelegate <NSObject>
/// Invoked when the user leaves the config screen and the button set changed.
- (void)configViewControllerDidChange:(FBConfigViewController *)vc;
@end

@interface FBConfigViewController : UIViewController
@property (nonatomic, weak) id<FBConfigViewControllerDelegate> delegate;
@end
