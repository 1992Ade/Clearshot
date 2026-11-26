# MYbloXX for iOS — porting notes

Reference material for the Ad Blocking section of TrollBox. Content copied
verbatim from the two HTML pages the user supplied and the GitHub repo:
  https://github.com/pegakmupyem/myxxdev

## Mechanism

MYbloXX works by:

1. Spoofing the device as supervised. It writes `IsSupervised=true` into
   `/var/containers/Shared/SystemGroup/systemgroup.com.apple.configurationprofiles/
    Library/ConfigurationProfiles/CloudConfigurationDetails.plist`.
   This is the same trick as the Supervise section in TrollBox already
   does — we can reuse that code path.
2. Once iOS believes the device is supervised, it allows installing a
   `.mobileconfig` content-filter / managed-configuration profile the
   user couldn't otherwise install.
3. That profile points at a DNS-level or content-filter block list. The
   result: ads, revokes, trackers and miners are blocked system-wide,
   without filesystem modifications or a VPN profile.

## Profiles offered upstream

- **Standard** — blocks everything, including Facebook AdSense. Breaks
  the Facebook share sheet and FB sign-in; user has to temporarily disable
  MYbloXX to use them.
- **noFB** — same as Standard but no Facebook domains, so FB login/
  sharing keeps working. You still get FB ads in apps that fetch them.
- **noOTA** — blocks iOS OTA updates via the standard profile mechanism;
  compatible with the Standard / noFB profiles.

## What our section should do (phase 1)

- [ ] Toggle "Supervised spoof" on/off (reuse SVMainViewController's code)
- [ ] Download the latest Standard / noFB / noOTA profile bundles from
      a configurable URL (default: MYbloXX upstream list)
- [ ] Install the chosen profile via `MCProfileConnection`
- [ ] Show status: current blocker enabled, last update, number of hosts
- [ ] Soft reboot (respring) button
- [ ] Removal path: uninstall the profile and optionally remove the
      supervised spoof

## Credits for the About page and README

- **MYbloXX for iOS** / **myxxdev** — https://github.com/pegakmupyem/myxxdev
  The supervised-spoof → mobileconfig trick, and the curated block-list
  profiles. The TrollBox Ad Blocking section will be a reimplementation
  of this flow with the user-supplied customizations.

## Open questions

- Does the mobileconfig need to be signed? If yes, where does MYbloXX host
  signed copies? (Check landing page or ask dev.)
- Is there a public JSON index of the current profile versions and
  download URLs we can hit so Ad Blocking auto-updates?
- iOS 16+ "Managed by..." lock-screen banner: tolerable or annoying
  enough to need removal?
