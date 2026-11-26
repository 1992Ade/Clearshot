// ============================================================================
// ARMainViewController — AppRepack.
//
// Port of Muffinstore (github.com/mineek/muffinstore). Uses iOS's private
// SKUIItemStateCenter (via com.apple.itunesstored.private entitlement) to
// trigger the native Store download flow for a specific older version of
// an app, reusing the user's existing Apple ID session (no credentials
// handled by TrollBox). Version catalog queried from apis.bilin.eu.org,
// with a manual-ID fallback.
// ============================================================================

#import <UIKit/UIKit.h>

@interface ARMainViewController : UITableViewController
@end
