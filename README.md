# TrollBox

> *A single-icon re-bundle of iOS 14-16 TrollStore utilities I use daily.*

**TrollBox** is a re-bundle of various existing TrollStore utilities that I
find useful and functional on iOS 14-16 (device of reference: iPhone SE
1st-gen on iOS 15.8.8). Other similar tools exist, but these are the ones I
actually use; rather than switching between ten apps I put mine under one
icon. Install once, pick what you need from the home grid.

**No jailbreak. No MobileSubstrate / ElleKit.** TrollStore's
`platform-application` entitlement is enough.

**Compatibility**: iOS 14.0 - 16.6.1, any device TrollStore runs on - the
A9 iPhone 6s / SE 1st-gen, iPad Pro 2018 (A12X), everything in between. The
Ad Blocking profile the app generates also installs on **non-TrollStore**
iPhones once they're supervised via Apple Configurator 2 (see the "For
non-TrollStore users" section below).

**Latest release**: [github.com/1992Ade/TrollBox/releases/latest](https://github.com/1992Ade/TrollBox/releases/latest)

## Sections

### LocSim — simulated CLLocation
Feeds a fake GPS fix to every app via the private `CLSimulationManager`.
Enter coordinates or pick a preset; iOS re-evaluates time zone automatically.

### Ad Blocking — MYbloXX-style blocker, PACs embedded locally
Port of [MYbloXX for iOS](https://github.com/pegakmupyem/myxxdev) with the
blocklists shipped **inside the app**: no PAC is fetched over HTTP at
install time, no third-party server sees your traffic. Four PAC variants
(Standard / noFB / noXXX / noFBnoXXX), each ~83,521 domains merged from
MYbloXX + StevenBlack at build time. Three user toggles:

- **Allow Facebook/Instagram login** — unblocks the FB/IG SDK login
  endpoints only, keeps all tracker domains blocked. Switch this on if FB
  or Instagram log-in screens fail to load.
- **Block adult content** — adds ~45 wildcard filters for adult keywords on
  top of the baseline.
- **Block iOS updates** — installs a fake tvOS Beta Software Profile that
  silences iOS Software Update. Reversible.

Also an in-app "Refresh blocklist from StevenBlack" button so you can pull
a fresher list between releases.

### ResSetter — display resolution tweaks, with persist-at-boot
Writes `canvas_width` / `canvas_height` to
`com.apple.iokit.IOMobileGraphicsFamily.plist` so iOS reports your chosen
logical resolution. Save as many presets as you want. **Persistence toggle**
installs a LaunchDaemon that re-applies your last preset before backboardd
at every boot, so the custom resolution survives reboots (safe boot
disables it so you can recover from a bad choice).

### Badge Color — recolor SpringBoard notification badges
Port of Cowabunga's BadgeChanger. Draws a filled circle of your chosen
`UIColor` at a chosen radius, writes it to the SpringBoard badge bitmap
cache. Persist-on-apply: reopening the section restores your last applied
color/radius instead of the stock red.

### ClearShot — Control Center screenshot that bypasses FLAG_SECURE
Installs a `ClearShotModule.bundle` in `/Library/ControlCenter/Bundles/`.
From any app, swipe into Control Center → tap the tile → the screenshot
lands in Photos even when the foreground app has FLAG_SECURE set (banking,
auth, secure messaging). Uses `CARenderServerRenderDisplay` from inside
SpringBoard.

### Supervise — IsSupervised spoof
Toggles the `IsSupervised` flag (and an optional `OrganizationName`) in
`CloudConfigurationDetails.plist`. Unlocks a handful of supervised-only
iOS settings; same mechanism Ad Blocking uses under the hood.

### Tweaks — dylib / bundle injection (WIP)
Lists installed user apps. Preamble points to the three well-maintained
tweak repos to grab dylibs from — YTLite (dayanch96) for YouTube,
BHInstagram and BHTwitter (BandarHL) for Instagram and Twitter — since
TrollBox ships no tweaks itself. MachO injection UI is being ported from
TrollFools.

### Reclaim Space — free real disk space
Targeted replacement for the generic iOS "cleanup" tools that free
basically nothing. Scans the five paths iOS actually leaves lying around:
analytics panics, crash reports, Feedback Assistant logs, rotated system
logs, and leftover containers from uninstalled apps. Shows real sizes
before + after, so you know how much was actually freed.

### AppRepack — install older compatible app versions (Muffinstore port)
Port of [Muffinstore](https://github.com/mineek/muffinstore). Pick an
installed app or paste an AppStore URL; TrollBox fetches the version
history from `apis.bilin.eu.org` and triggers the native iOS Store
download for the version you pick (via private `SKUIItemStateCenter`). Your
Apple ID session already active on this device handles authentication —
TrollBox never sees your password. "Latest compatible" option lets Apple's
Store server pick the newest version that will install on your iOS.

### Jaility — small iOS system tweaks (scaffolded)
Scaffold for a future port of Jaility by haxi0.

### About Device — battery health, device, CPU, RAM, storage, network
Reads the private `IOPowerSources` keys that normal apps can't surface
(design capacity, cycle count, voltage, temperature), plus system info via
`sysctl`.

## Install on device

### With TrollStore (primary path)

1. Download **TrollBox.tipa** from the
   [latest release](https://github.com/1992Ade/TrollBox/releases/latest/download/TrollBox.tipa).
   In TrollStore, open **Install from URL** and paste:
   ```
   https://github.com/1992Ade/TrollBox/releases/latest/download/TrollBox.tipa
   ```
2. Open **TrollBox** from the Home Screen.
3. For ClearShot: tap the tile → **1 · Install Control Center module** →
   **2 · Respring now** → **3 · Open Control Center settings**, scroll to
   *More Controls* and tap **+** next to **ClearShot**.
4. For Ad Blocking: tap the tile → toggle filters → **Generate & install
   profile**. Enable supervision in the same screen if prompted.
5. Other sections work out of the box — no install step.

### For non-TrollStore users

TrollBox itself needs TrollStore (it uses the `platform-application`
entitlement that only TrollStore grants). But **the Ad Blocking profile it
generates installs on any supervised iPhone**, no TrollStore required.
Two paths:

**Option (a) — Download pre-generated mobileconfigs (easier)**

Each GitHub Release attaches 8 ready-made `.mobileconfig` files, one per
toggle combo:
```
TrollBoxAdBlock-Standard.mobileconfig
TrollBoxAdBlock-noFB.mobileconfig
TrollBoxAdBlock-noXXX.mobileconfig
TrollBoxAdBlock-noFBnoXXX.mobileconfig
TrollBoxAdBlock-Standard-noOTA.mobileconfig
TrollBoxAdBlock-noFB-noOTA.mobileconfig
TrollBoxAdBlock-noXXX-noOTA.mobileconfig
TrollBoxAdBlock-noFBnoXXX-noOTA.mobileconfig
```

Pick the one you want, open it on your iPhone in Safari, install via
Settings → Profile Downloaded. For the install to be accepted the iPhone
must already be supervised, which you do from a Mac:

1. Back up your iPhone — supervising wipes it.
2. Install [Apple Configurator 2](https://apps.apple.com/app/apple-configurator-2/id1037126344)
   (free, Mac App Store).
3. Plug the iPhone into the Mac via USB.
4. Prepare → Manual Configuration → check **Supervise devices**, uncheck
   "Enroll in MDM".
5. Follow the wizard; the iPhone will erase and come back supervised.
6. Download the chosen `.mobileconfig` from the latest release, install
   via Settings.

Free alternatives for supervision: **iMazing Profile Editor** (Mac/Windows),
**cfgutil** (CLI shipped with Apple Configurator 2).

**Option (b) — Side-load TrollBox via SideStore, use the app to generate**

If you want to customise filters beyond the 8 pre-generated combos
without re-downloading each time:

1. Install [SideStore](https://sidestore.io) on the iPhone (no Mac
   required; re-sign runs every 7 days via a free Apple developer account).
2. Install the TrollBox `.ipa` from the latest release via SideStore.
3. Caveat: SideStore strips several entitlements
   (`platform-application`, `managedconfiguration.profiled-access`). What
   this means per section:
   - ✅ About Device, LocSim, BadgeColor work
   - ❌ ClearShot, ResSetter persistence, AppRepack won't work
   - ⚠️ Ad Blocking can **generate** the mobileconfig but not install it
     silently — the app shares it via the share sheet, you install via
     Settings → Profile Downloaded
4. You still need to supervise via Apple Configurator 2 (same procedure
   as option (a)).

Options (a) and (b) are not exclusive. **Option (a) is enough for 95% of
users.**

## Prerequisites

- An iPhone running **iOS 14.0 - 16.6.1**
- [TrollStore](https://github.com/opa334/TrollStore) installed on the
  device via the installer that matches the iOS version:

  | iOS version | Installer |
  |---|---|
  | 14.0 - 15.4.1 | [TrollHelper](https://github.com/opa334/TrollStore) |
  | 15.5 - 15.7.x | [TrollMisaka](https://github.com/straight-tamago/TrollMisaka) |
  | 15.8.x - 16.6.1 | [TrollInstallerDark](https://github.com/rockylabs-dev/TrollInstallerDark) |

## Build

### Via GitHub Actions

Every push rebuilds the `.tipa`, re-fetches StevenBlack, re-merges the
PACs, pre-generates the 8 release `.mobileconfig` files and overwrites the
rolling `latest` release. See `.github/workflows/build.yml`.

### Local build (optional)

macOS with [Theos](https://theos.dev) + iOS SDK 15.5+ in `$THEOS/sdks`:

```bash
make clean
make package FINALPACKAGE=1
```

## Credits

Short list; the in-app **About** screen has the per-project detail.

| Project | Used for |
|---|---|
| [TrollStore](https://github.com/opa334/TrollStore) by opa334 | Platform-application ecosystem |
| [TrollInstallerDark](https://github.com/rockylabs-dev/TrollInstallerDark) by rockylabs-dev | TrollStore installer for iOS 15.8.x |
| [Andromeda / Geranium](https://github.com/Son3ra1n/Andromeda) by Son3ra1n | LocSim, Supervise, respring, entitlements template |
| [TrollFools](https://github.com/Lessica/TrollFools) by Lessica | Tweaks section (dylib/bundle injection path) |
| [ResolutionSetterSwift](https://github.com/haoict/ResolutionSetterSwift) by haoict | ResSetter mechanism |
| NiceBattery | About Device battery metrics via `IOPowerSources` |
| [MYbloXX for iOS](https://github.com/pegakmupyem/myxxdev) by pegakmupyem | Ad Blocking mechanism + base PACs |
| [StevenBlack/hosts](https://github.com/StevenBlack/hosts) | Fresh blocklists merged into the PACs at build time |
| [Muffinstore](https://github.com/mineek/muffinstore) by mineek | AppRepack mechanism (`SKUIItemStateCenter`) |
| [Cowabunga](https://github.com/leminlimez/Cowabunga) by leminlimez (BadgeChanger by exerhythm) | Badge Color |
| Jaility (haxi0) | Jaility section toggles (scaffolded) |
| [YTLite](https://github.com/dayanch96/YTLite), [BHInstagram](https://github.com/BandarHL/BHInstagram), [BHTwitter](https://github.com/BandarHL/BHTwitter) | Example tweak sources referenced in the Tweaks section preamble |
| [Apple Configurator 2](https://apps.apple.com/app/apple-configurator-2/id1037126344) | Documented path for non-TrollStore supervision (free, Mac App Store) |

## License

**GNU General Public License v3.0** — see [`LICENSE`](./LICENSE).

## Disclaimer

Provided for personal use, research and accessibility. Some features
(screen capture of other apps' protected content, simulated locations,
supervision toggles, binary modification, downloading older app versions)
can violate third-party terms of service and, depending on content and
jurisdiction, local law. Use responsibly on devices you own.
