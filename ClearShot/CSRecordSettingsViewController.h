// ============================================================================
// CSRecordSettingsViewController — "Record settings" sub-screen pushed from
// ClearShot. Lets the user pick FPS, resolution, audio sources and codec
// for the Record CC module. Values persist in NSUserDefaults so the CC
// module (running in SpringBoard) reads the same keys before each record.
// ============================================================================

#import <UIKit/UIKit.h>

@interface CSRecordSettingsViewController : UITableViewController
@end
