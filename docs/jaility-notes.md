# Jaility — porting notes

Reference material for the Jaility section of TrollBox.

## Upstream

- **App**: Jaility
- **Bundle ID**: `org.haxi0.Jaility`
- **Version analyzed**: 3.1.1
- **Author**: haxi0 (Yurii Anokhin)
- **IPA source**: user-supplied `Jaility-3.1.1.ipa`

The project doesn't appear to have a public source repository in the IPA
metadata (no `git` string, no GitHub URL). The binary is a SwiftUI Xcode
app signed ad-hoc with `ldid`, same pattern as Andromeda.

## Mechanism

Reverse-engineered from binary strings (`strings` on the Mach-O):

- A sandbox-check file is written to `/var/mobile/org.haxi0.Jaility`
  during install / first launch. Presence of this file is Jaility's
  own "we're installed and have root" proof. Failure to write it prints
  `Failed to remove sandbox check file`.
- Each tweak is a write / edit of a system plist or preference file,
  followed by a respring.
- `Remove Modifications` walks back everything Jaility has applied so
  far. Presumably uses the marker file to know what to undo.

## Known tweaks (from v3.1.1 UI strings)

- **Hide / Show the Mute Switch in Control Center**
- **Disable / Enable Locking After Respring**
- **Placeholder text that was edited by Jaility** — demo tweak that
  just rewrites a string in a system plist, showing the mechanism

## Entitlements (also from the Mach-O)

Same core set as Andromeda / TrollBox already uses:

- `platform-application`
- `com.apple.private.security.no-container`
- `com.apple.private.security.no-sandbox`
- `com.apple.private.security.container-manager`
- `com.apple.private.security.system-application`
- `com.apple.private.security.storage.MobileDocuments`
- `com.apple.security.exception.files.absolute-path.read-write`

Nothing we don't already carry, so our existing `entitlements.plist` is
enough to run the ported logic.

## What our section should do (phase 1)

- [ ] Replicate "Hide / Show Mute Switch" by writing the right key to
      the Control Center / SpringBoard preferences plist (identify the
      key by diffing the system state before and after Jaility applies
      it on-device)
- [ ] Replicate "Disable / Enable Locking After Respring" similarly
- [ ] Marker file at `/var/mobile/org.haxi0.TrollBoxJaility` (our own
      namespace so we don't collide with an installed Jaility) listing
      what we've applied
- [ ] Remove Modifications button — walks the marker and undoes each
- [ ] Respring button shared with the rest of TrollBox (CSProcessUtils)

## Open questions

- Exact plist path + key for the Mute Switch hide. (Diff needed.)
- Exact plist path + key for Locking After Respring. (Diff needed.)
- Does haxi0 maintain a changelog / list of tweaks somewhere we can
  mirror automatically?
- Can we find the original source? (Not in the IPA; try searching haxi0
  on GitHub when work resumes.)
