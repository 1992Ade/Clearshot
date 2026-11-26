// ============================================================================
// ADMainViewController — "About Device" section.
//
// Port / reimplementation of NiceBattery (com.niceios.Battery). Reads
// system info that normal apps can't surface:
//   • Battery: current %, state, design/current capacity, cycle count,
//     voltage, temperature (via IOPowerSources + IOPSCopyPowerSourcesList,
//     and private IOPMPowerSource keys that are only exposed with the
//     TrollStore IOKit entitlement)
//   • Device: model identifier, iOS version, build, uptime
//   • CPU: physical/active cores, frequency
//   • RAM: total / in use
//   • Storage: total / free
//   • Network: current SSID, local IPs
//
// Pure read-only — no plist writes, no respring. Safe to open any time.
// ============================================================================

#import <UIKit/UIKit.h>

@interface ADMainViewController : UITableViewController
@end
