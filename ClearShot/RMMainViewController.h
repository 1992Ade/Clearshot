// ============================================================================
// RMMainViewController — Reclaim Space.
//
// Targeted replacement for Andromeda's generic "Cleanup" section (which was
// mostly placebo on iOS 15+). Scans and clears the handful of paths that
// genuinely accumulate junk iOS never reclaims on its own: analytics panics,
// crash dumps, support logs, rotated system logs, and leftover containers
// for apps that have been uninstalled.
// ============================================================================

#import <UIKit/UIKit.h>

@interface RMMainViewController : UITableViewController
@end
