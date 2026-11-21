# FloatBar

> *iOS is boring, so I made it more Android. This navigation bar brings Android vibes to iOS, with a bonus: a button that takes forbidden screenshots!*

A single iOS TrollStore app that puts a **configurable, Android-style floating navigation bar** above every other app, and **can capture the screen** bypassing software-level FLAG_SECURE / protected-content filters.

**Four actions available on the bar**:

| Button | Effect |
|---|---|
| ◉ Capture | Screen capture via `CARenderServerRenderDisplay`. Bypasses software secure-screen flags (banking apps, Signal, 1Password). Hardware DRM (Netflix/Disney+ secure video on A11+) stays blocked by the GPU. |
| ⏺ Home | Simulates a Home-button press (HID Consumer-Menu). Useful as a substitute if the physical Home button is broken. |
| ☰ App Switcher | Opens the app switcher (synthesized swipe-up-with-pause from the bottom edge). |
| ◀ Back | Edge-swipe from the left — triggers `UINavigationController` back in every stock UIKit nav stack. |

Each button can be **enabled/disabled** and **reordered** from the app's settings screen. The bar auto-hides during a capture so it does not appear on the resulting screenshot.

**No jailbreak. No tweak injection. No MobileSubstrate / ElleKit required.**

**Repository**: [github.com/1992Ade/FloatBar](https://github.com/1992Ade/FloatBar)
**Latest release**: [github.com/1992Ade/FloatBar/releases/latest](https://github.com/1992Ade/FloatBar/releases/latest)

**Compatibility**: iOS 15.0 → 16.x, on any device where **TrollStore** is installed — regardless of which installer was used (TrollHelper, TrollInstallerDark/darksword, TrollMisaka, etc.). iOS 15+ is required because the overlay is drawn by `AVPictureInPictureVideoCallViewController`, which only accepts an arbitrary `UIView` from iOS 15 onwards.

## How it works

The usual way to put a view on top of every other iOS app is to inject a dylib into SpringBoard — which requires a jailbreak. FloatBar takes a different route: it piggybacks on `AVPictureInPictureVideoCallViewController` (iOS 15+), the API Apple designed for video-calling apps to keep a mini-window of the call visible while the user is in another app.

- The PiP window is drawn by the system compositor, so it floats above every foreground app natively.
- Our custom `FBBarViewController` fills the PiP window with the user-selected buttons, in the user-selected order.
- Taps on the PiP window are delivered to the view hierarchy normally — so our buttons receive touches.
- Button taps dispatch to `FBActions`, which either synthesizes HID events (Home/Back/App Switcher) via `BKSHIDEventPostFast`, or triggers the capture pipeline.
- The capture pipeline hides the bar (`alpha = 0` + `CATransaction flush`), waits one display frame (~50 ms) so the bar is *absent* from the captured image, then calls `CARenderServerRenderDisplay` into an `IOSurface`.
- TrollStore grants the entitlements needed to reach `IOHIDEventSystemUserClient` and `CARenderServer`, which makes HID synthesis and raw-screen capture possible from a standalone process without a tweak.

## Prerequisites

- An iPhone running iOS 15.0 – 16.x
- [TrollStore](https://github.com/opa334/TrollStore) installed on the device, by any available installer

Depending on your iOS version, use whichever TrollStore installer applies:

| iOS version | Installer |
|---|---|
| 14.0 – 15.4.1 | [TrollHelper](https://github.com/opa334/TrollStore) (bundled with early TrollStore) |
| 15.5 – 15.7.x (some) | [TrollMisaka](https://github.com/straight-tamago/TrollMisaka) and related |
| 15.8.x – 16.x | [TrollInstallerDark](https://github.com/rockylabs-dev/TrollInstallerDark) — leverages [darksword-kexploit](https://github.com/opa334/darksword-kexploit) |

Once TrollStore is installed — regardless of path — this `.tipa` works. The app itself does not depend on any particular installer.

## Build

### Via GitHub Actions (recommended, no local setup)

Clone, then push:

```bash
git clone https://github.com/1992Ade/FloatBar.git
cd FloatBar
# make your changes, then:
git push
```

The workflow in `.github/workflows/build.yml` compiles the project on a macOS runner (Intel or Apple Silicon — Theos cross-compiles to arm64 iOS, the runner CPU doesn't affect the output) and uploads `FloatBar.tipa` as an artifact.

To cut a tagged release (`.tipa` attached automatically):

```bash
git tag v1.0.0
git push --tags
```

### Local (optional)

Requires macOS with [Theos](https://theos.dev) installed and an iOS SDK (15.5+) in `$THEOS/sdks`.

```bash
make clean
make package FINALPACKAGE=1
```

## Install on device

Easiest path — **Install from URL** in TrollStore:

```
https://github.com/1992Ade/FloatBar/releases/latest/download/FloatBar.tipa
```

Paste that URL into TrollStore → **Install from URL**. TrollStore downloads the latest release and installs it.

Alternative:

1. Grab `FloatBar.tipa` from the [Releases page](https://github.com/1992Ade/FloatBar/releases) or the latest [Actions run](https://github.com/1992Ade/FloatBar/actions) artifact.
2. AirDrop / share-sheet the file to the device.
3. Open it with TrollStore.

## Using FloatBar

1. Launch FloatBar.
2. Tap **Configurer les boutons** and choose which buttons you want on the bar and in which order. Drag the handles on the right to reorder; tap the minus to disable; tap the plus on a disabled row to re-enable.
3. Tap **Activer la barre flottante**. A small pill appears above the FloatBar UI.
4. Home-swipe to any other app — the pill stays visible, floating over it.
5. Tap any button on the bar to trigger its action. When you tap **Capture**, the bar momentarily hides, the screen is captured without the bar in frame, and the image is saved to Photos.
6. Return to FloatBar and tap **Désactiver la barre** when you're done.

## Project layout

```
floatbar/
├── Makefile                           # Theos build (standalone app)
├── control, LICENSE, README.md
├── Info.plist                         # Must live at root — Theos convention
├── entitlements.plist                 # TrollStore entitlements
├── .github/workflows/build.yml        # CI → .tipa artifact
├── Resources/
│   ├── icon.svg                       # source
│   └── icon-*.png                     # 11 rendered sizes
└── FloatBar/
    ├── main.m
    ├── FBAppDelegate.{h,m}            # bootstraps AVAudioSession in playback mode
    ├── FBMainViewController.{h,m}     # start/stop + config entry point
    ├── FBConfigViewController.{h,m}   # table view: enable/disable + reorder
    ├── FBButtonConfig.{h,m}           # persisted button list in NSUserDefaults
    ├── FBPiPController.{h,m}          # wires AVPictureInPictureController
    ├── FBBarViewController.{h,m}      # the dynamic bar inside the PiP window
    ├── FBActions.{h,m}                # action dispatcher + capture flow
    ├── FBEventSynthesizer.{h,m}       # HID event injection (Home / Back / Switcher)
    └── FBScreenCapture.{h,m}          # CARenderServer-based capture (ClearShot engine)
```

## Entitlements of note

See `entitlements.plist`:

| Entitlement | Purpose |
|---|---|
| `platform-application` | Granted by TrollStore — baseline |
| `com.apple.frontboard.launchapplications` | Launch other apps |
| `com.apple.security.exception.iokit-user-client-class → IOHIDEventSystemUserClient` | Open the HID event service for touch and key synthesis |
| `com.apple.security.exception.mach-lookup.global-name → com.apple.CARenderServer` | Reach the render server for secure-mode screen capture |
| `com.apple.QuartzCore.secure-mode` | Read `CALayer`s marked as secure |
| `com.apple.security.exception.iokit-user-client-class → IOSurfaceRootUserClient` | Create the `IOSurface` that `CARenderServer` writes into |

## Known limitations

- **Hardware DRM** (Netflix/Disney+ secure video pipeline on A11+ devices, routed through the Secure Enclave and the hardware compositor) remains out of reach — the GPU excludes that layer *before* `CARenderServer` can see it.
- Some apps that filter synthetic HID events (certain payment apps, a few games) may ignore the simulated back-swipe.
- On iOS 16+, the app switcher gesture sometimes needs extra entitlements (`UIAutomation`); TrollStore grants them by default when declared.

## History

Early iterations of FloatBar were floating-bar-only, and ClearShot was a separate screen-capture-only app. They have now been **merged into this single configurable TrollStore app**, with each button toggleable and reorderable, and the bar auto-hiding during captures. The former ClearShot repo is deprecated — all its functionality now lives here as the `Capture` button.

## Credits & acknowledgements

- **[@opa334](https://github.com/opa334)** — creator of [TrollStore](https://github.com/opa334/TrollStore) and the [darksword-kexploit](https://github.com/opa334/darksword-kexploit) kernel exploit, the combo that makes everything here possible on stock iOS.
- **[@rockylabs-dev](https://github.com/rockylabs-dev)** — [TrollInstallerDark](https://github.com/rockylabs-dev/TrollInstallerDark), the installer for the iOS 15.8.x window.
- **[@theos](https://github.com/theos)** — the [Theos](https://theos.dev) build system.
- **[@theos/sdks](https://github.com/theos/sdks)** — redistributed iOS SDKs used by CI.
- The PiP-as-overlay technique is inspired by prior community explorations of `AVPictureInPictureVideoCallViewController` as a general-purpose overlay surface.
- The HID-event synthesis technique via `BKSHIDEventPostFast` has been documented for years in the jailbreak community.
- The `CARenderServerRenderDisplay` screen-capture approach is a long-known iOS technique documented in jailbreak tweaks such as **Shoot!** and **ScreenshotEnabler**.

## License

**GNU General Public License v3.0** — see [`LICENSE`](./LICENSE).

This is a copyleft license: you can use, modify and redistribute this software freely, but any derivative work must also be licensed under GPL-3.0 and ship with its complete source code. See <https://www.gnu.org/licenses/gpl-3.0.html> for the full terms.

## Disclaimer

Provided for personal use, research, and accessibility. Synthesizing touch events and capturing screens in third-party apps may violate those apps' terms of service and, depending on the content, local law (copyright, privacy, DRM circumvention). Use responsibly on devices you own and content you have the right to capture.
