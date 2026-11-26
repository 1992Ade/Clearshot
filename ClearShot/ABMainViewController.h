// ============================================================================
// ABMainViewController — Ad Blocking.
//
// Port of MYbloXX for iOS (pegakmupyem/myxxdev) with the blocklists
// embedded locally (nothing fetched over HTTP at install time). 3 user
// toggles (allow FB login, block adult, block iOS updates) plus a
// supervision toggle sharing TBSupervisionManager with the Supervise tab.
// Generates the .mobileconfig on-device, installs silently via
// MCProfileConnection (com.apple.managedconfiguration.profiled-access).
// ============================================================================

#import <UIKit/UIKit.h>

@interface ABMainViewController : UITableViewController
@end
