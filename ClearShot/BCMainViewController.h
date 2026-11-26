// ============================================================================
// BCMainViewController — "Badge Color" section.
//
// Port of Cowabunga's BadgeChanger + SpringboardColorChangerView
// (leminlimez/Cowabunga, originally by exerhythm). Rewrites the SpringBoard
// badge bitmap cache so notification badges render in a chosen colour
// instead of Apple's red.
//
// Mechanism (direct port, same path and keys as upstream):
//   1. Draw a filled circle of the chosen UIColor at the chosen radius
//      into a UIImage (26×26 on iPhone, 52×52 on iPad).
//   2. Delete the existing badge bitmap at
//        /var/mobile/Library/Caches/MappedImageCache/Persistent/
//          SBIconBadgeView.BadgeBackground:26:26.cpbitmap
//   3. Call the private UIImage method `-writeToCPBitmapFile:flags:` with
//      flags=1 to save the new badge at that path.
//   4. Respring.
//
// Upstream's `#unavailable(iOS 16)` guard applies here too: iOS 16+
// SpringBoard no longer honours this cache for notification badges. We
// show a warning in the UI on those versions but let the user try anyway.
// ============================================================================

#import <UIKit/UIKit.h>

@interface BCMainViewController : UIViewController
@end
