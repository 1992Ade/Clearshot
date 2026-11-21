#import <UIKit/UIKit.h>

@interface FBPiPController : NSObject

+ (BOOL)isAvailable;

- (instancetype)initWithHostView:(UIView *)hostView;
- (void)start;
- (void)stop;

/// Call after the button config changes to resize + re-render the pill.
- (void)reloadConfig;

@property (nonatomic, readonly, getter=isActive) BOOL active;

@end
