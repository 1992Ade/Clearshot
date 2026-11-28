// ============================================================================
// STMainViewController — "SpringBoard Tweaks" section.
//
// Home for SpringBoard-side hooks that don't belong in a more specific
// section (ClearShot's native gesture bypass lives there because it's
// about screenshots; ResSetter's Don't-lock-after-respring stays there
// because it's about the respring workflow). Everything else SB-hook
// lands here:
//
//   • Clear All in app switcher — adds a "Clear all" button to the
//     native app-switcher that kills every app except SpringBoard
//     (via libClearAllHook.dylib injected into SpringBoard)
//   • (future) Hide mic / cam active indicators
//   • (future) Unlock hidden Control Center controls
//
// Each toggle = inject / eject the corresponding dylib via the shared
// TFInjector engine (same code path as Tweaks and ClearShot's native-
// gesture bypass). The section's bottom row is an "Uninject all SB
// hooks" nuke button — handy right before an iOS update since you want
// SpringBoard clean before you let it launch a different iOS version.
// ============================================================================

#import <UIKit/UIKit.h>

@interface STMainViewController : UIViewController
@end
