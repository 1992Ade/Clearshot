// ============================================================================
// SVMainViewController — "Supervise" tab.
//
// Toggles whether iOS considers this device "supervised" by writing to
//
//   /var/containers/Shared/SystemGroup/
//        systemgroup.com.apple.configurationprofiles/
//        Library/ConfigurationProfiles/CloudConfigurationDetails.plist
//
// A supervised iPhone exposes several things a normal iPhone doesn't —
// an organisation name on the lock screen, extra MDM-like settings, and
// a few private frameworks' feature flags. The trick was documented by
// Son3ra1n / Geranium and this file is a straight ObjC port of Andromeda's
// SuperviseView.swift, with a respring hook that goes through our own
// CSProcessUtils instead of UIApplication.respringDeprecated.
// ============================================================================

#import <UIKit/UIKit.h>

@interface SVMainViewController : UIViewController
@end
