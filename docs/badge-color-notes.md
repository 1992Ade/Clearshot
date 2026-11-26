# Badge Color — porting notes

Direct port of Cowabunga's BadgeChanger into TrollBox's own ObjC code.

## Upstream

- **Repo**: [github.com/leminlimez/Cowabunga](https://github.com/leminlimez/Cowabunga)
- **Files**:
  - `Cowabunga/Controllers/Tools/BadgeChanger.swift`
  - `Cowabunga/Views/UniqueToolsViews/SpringboardColorChangerView.swift`
- **Original author**: exerhythm (Oct 2022)

## Mechanism

1. Target file (same on iPhone and iPad): \
   `/var/mobile/Library/Caches/MappedImageCache/Persistent/SBIconBadgeView.BadgeBackground:26:26.cpbitmap`
2. Build a `UIImage` of the chosen color: a filled circle of size
   `max(1, radius)` on iPhone, `radius * 2` on iPad.
3. `FileManager.removeItem(atPath:)` the existing file. Ignore
   "doesn't exist" errors.
4. Call the private UIImage method `-writeToCPBitmapFile:flags:` with
   `flags = 1`. Cowabunga does this through a `Dynamic` runtime wrapper;
   TrollBox declares the selector in a private category and calls it
   directly with `performSelector:` equivalence.
5. Respring (SpringBoard, FrontBoard, BackBoard — same as all our other
   sections, via `CSProcessUtils forceRespring`).

## iOS 16+ status

Upstream's SwiftUI hides the whole Badge Color view behind
`#unavailable(iOS 16)`. In iOS 16+ SpringBoard stops honouring this
cache file for most badge paths, so writes land but the UI doesn't
change. We don't hide the section — the user may still want to try on
edge cases — but we show a yellow warning banner when running on 16+.

## What we ship (phase 1, done)

- [x] UIColor picker (uses UIColorPickerViewController on iOS 14+)
- [x] Radius slider 1…24 (same range Cowabunga clamps to)
- [x] Live preview: a fake icon with a corner badge sized from the slider
- [x] Apply → write the bitmap file
- [x] Reset → delete the override and fall back to Apple's red
- [x] Respring prompt after Apply
- [x] Status label shows whether an override is currently in place

## Not included (yet)

- Custom image badge (upstream has a "Custom image" button that lets the
  user pick a photo and write that instead of a solid circle). Would be
  trivial to add with `PHPickerViewController`.
- Wallpaper preview behind the icon (upstream renders over the device's
  current wallpaper for a more realistic preview).
