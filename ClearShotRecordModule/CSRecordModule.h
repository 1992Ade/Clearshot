#import <UIKit/UIKit.h>

// CCUIToggleModule forward decl (ControlCenterUIKit private). Same shape as
// CSModule in the Capture bundle — latching is YES for the Record toggle so
// the tile stays "selected" while recording, and untapping stops.
@interface CCUIToggleModule : UIViewController
@property (nonatomic) BOOL selected;
- (void)setSelected:(BOOL)selected;
- (BOOL)isSelected;
@end

@interface CSRecordModule : CCUIToggleModule
@end
