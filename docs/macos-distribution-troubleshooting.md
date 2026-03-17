# macOS Distribution Troubleshooting

## Goal
Distribute LedgeriOS as a macOS .dmg for direct distribution (outside Mac App Store).

## Environment
- Certificate: `Developer ID Application: Ben Mackenzie (5VHL56HV63)`
- Bundle ID: `apps.nine4.ledger`
- App-specific password for notarytool: generate at appleid.apple.com
- Notarytool command: `xcrun notarytool submit <dmg> --apple-id team@nine4.co --team-id 5VHL56HV63 --password <app-specific-password> --wait`

## What Works
- Archiving with `CODE_SIGN_STYLE=Automatic SDKROOT=macosx` — Xcode auto-creates a provisioning profile
- Notarization with `xcrun notarytool` — accepts after re-signing with Developer ID + hardened runtime + timestamp
- Stapling with `xcrun stapler staple`
- DMG creation with `create-dmg` or `hdiutil`
- Test target must have `buildForArchiving = NO` in scheme (already fixed)

## The Core Problem: Provisioning Profile + Signing Identity Mismatch

### What happens
1. `xcodebuild archive` with `CODE_SIGN_STYLE=Automatic` signs with **Apple Development** cert and creates an embedded provisioning profile tied to that cert
2. For notarization + distribution, the app must be signed with **Developer ID Application** cert
3. Re-signing with `codesign --force` using Developer ID **invalidates** the provisioning profile because the profile was issued for the Apple Development cert
4. macOS AMFI rejects the app at launch: "No matching profile found" for `keychain-access-groups` and `com.apple.developer.team-identifier`

### Why `xcodebuild -exportArchive` fails
- Requires a **Developer ID provisioning profile** matching bundle ID `apps.nine4.ledger`
- `xcodebuild -exportArchive -exportOptionsPlist` with `method=developer-id` errors: "No profiles for 'apps.nine4.ledger' were found"
- Xcode's automatic archive doesn't create a Developer ID profile — it creates an Apple Development one

### The fix (not yet completed)
Create a **Developer ID provisioning profile** in the Apple Developer portal:
1. Register App ID `apps.nine4.ledger` as an **Identifier** if not already registered (must match platform: Mac Catalyst)
2. Create a **Profile** → Distribution → Developer ID → Mac Catalyst → select `apps.nine4.ledger` → select Developer ID Application cert
3. Download `.provisionprofile` and install: `open <file>.provisionprofile`
4. Then `xcodebuild -exportArchive` should work — it handles re-signing with the correct identity + profile pair

### Alternative: Strip restricted entitlements
If you don't need `keychain-access-groups` (e.g., no Google Sign-In):
- Sign with entitlements containing only `com.apple.security.network.client` (no sandbox, no keychain groups)
- App launches and notarizes fine
- But Google Sign-In fails with "keychain error" because it needs `keychain-access-groups`

## Build Commands Reference

### Archive for macOS
```bash
cd LedgeriOS && xcodebuild archive \
  -scheme "LedgeriOS" \
  -destination 'generic/platform=macOS' \
  -archivePath /tmp/LedgeriOS.xcarchive \
  DEVELOPMENT_TEAM=5VHL56HV63 \
  CODE_SIGN_STYLE=Automatic \
  SDKROOT=macosx \
  -derivedDataPath /tmp/LedgeriOS-DerivedData
```

### Re-sign frameworks + app with Developer ID (for notarization)
```bash
# Extract entitlements from archive first
codesign -d --entitlements /tmp/entitlements.plist --xml /tmp/LedgeriOS.xcarchive/Products/Applications/LedgeriOS.app

# Sign each embedded framework
for fw in Ledger.app/Contents/Frameworks/*.framework; do
  codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: Ben Mackenzie (5VHL56HV63)" "$fw"
done

# Sign the main app (preserving entitlements)
codesign --force --options runtime --timestamp \
  --entitlements /tmp/entitlements.plist \
  --sign "Developer ID Application: Ben Mackenzie (5VHL56HV63)" Ledger.app
```
**WARNING:** This breaks the provisioning profile. The app will notarize but won't launch due to AMFI rejecting the profile/identity mismatch for restricted entitlements.

### Create DMG
```bash
create-dmg \
  --volname "Ledger" \
  --volicon "/tmp/ledger_icon.icns" \
  --window-size 600 400 \
  --icon-size 128 \
  --icon "Ledger.app" 175 200 \
  --app-drop-link 425 200 \
  --hide-extension "Ledger.app" \
  Ledger.dmg \
  /path/to/staging/

# Or simple version if create-dmg has volume conflicts:
hdiutil create -volname "LedgerInstall" -srcfolder /path/to/staging -ov -format UDZO Ledger.dmg
```

### Notarize
```bash
xcrun notarytool submit Ledger.dmg \
  --apple-id team@nine4.co \
  --team-id 5VHL56HV63 \
  --password <app-specific-password> \
  --wait

# Check log if rejected:
xcrun notarytool log <submission-id> \
  --apple-id team@nine4.co \
  --team-id 5VHL56HV63 \
  --password <app-specific-password>

# Staple ticket:
xcrun stapler staple Ledger.dmg
```

## Common Notarization Rejections
| Error | Fix |
|-------|-----|
| "hardened runtime not enabled" | Add `--options runtime` to codesign |
| "no secure timestamp" | Add `--timestamp` to codesign |
| "not signed with Developer ID" | Use `--sign "Developer ID Application: ..."` |
| "No matching profile found" (AMFI) | Provisioning profile doesn't match signing identity — need Developer ID profile from portal |

## App Icon
- Source: `ledger_logo.png` (root of repo)
- Asset catalog: `Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png` + `Contents.json` with mac idiom entries
- The asset catalog only generates 16px and 128px macOS sizes from a single 1024px source
- For full-size Finder icons, manually replace `AppIcon.icns` in the built app's `Contents/Resources/` (but this requires re-signing which breaks the profile)

## Scheme Changes Made
- `LedgeriOS.xcscheme`: Test target `buildForArchiving` and `buildForProfiling` set to `NO` to prevent archive failures on macOS

## What Actually Works (The Correct Flow)

The key flag is `-allowProvisioningUpdates` on the export step. This tells xcodebuild to auto-register App IDs and create provisioning profiles — exactly what Xcode's GUI does.

```bash
# 1. Archive with automatic signing + hardened runtime
cd LedgeriOS && xcodebuild archive \
  -scheme "LedgeriOS" \
  -destination 'generic/platform=macOS' \
  -archivePath /tmp/LedgeriOS.xcarchive \
  DEVELOPMENT_TEAM=5VHL56HV63 \
  CODE_SIGN_STYLE=Automatic \
  SDKROOT=macosx \
  ENABLE_HARDENED_RUNTIME=YES \
  -derivedDataPath /tmp/LedgeriOS-DerivedData

# 2. Export with Developer ID — this handles re-signing, profile creation, everything
xcodebuild -exportArchive \
  -archivePath /tmp/LedgeriOS.xcarchive \
  -exportPath /tmp/LedgeriOS-Export \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -allowProvisioningUpdates

# ExportOptions.plist contents:
# <?xml version="1.0" encoding="UTF-8"?>
# <plist version="1.0">
# <dict>
#   <key>method</key><string>developer-id</string>
#   <key>teamID</key><string>5VHL56HV63</string>
#   <key>signingStyle</key><string>automatic</string>
# </dict>
# </plist>

# 3. Rename and create DMG
mkdir -p /tmp/staging && cp -R /tmp/LedgeriOS-Export/LedgeriOS.app /tmp/staging/Ledger.app
hdiutil create -volname "LedgerInstaller" -srcfolder /tmp/staging -ov -format UDZO /tmp/Ledger.dmg

# 4. Notarize + staple
xcrun notarytool submit /tmp/Ledger.dmg \
  --apple-id team@nine4.co --team-id 5VHL56HV63 \
  --password <app-specific-password> --wait
xcrun stapler staple /tmp/Ledger.dmg

# 5. Copy to Desktop
cp /tmp/Ledger.dmg ~/Desktop/Ledger.dmg
```

## Critical Lessons Learned

1. **Never `codesign --force` after `xcodebuild -exportArchive`** — the export produces a correctly signed app with matching provisioning profile. Re-signing breaks the profile/identity pairing.
2. **`-allowProvisioningUpdates` is essential** — without it, xcodebuild can't auto-register App IDs or create provisioning profiles, which is why export fails with "No profiles found."
3. **`ENABLE_HARDENED_RUNTIME=YES`** must be set at archive time — notarization rejects apps without it.
4. **Renaming `.app` doesn't break codesign** — safe to rename `LedgeriOS.app` to `Ledger.app` after export.
5. **Don't try to set `CODE_SIGN_IDENTITY="Developer ID Application"` at archive time** — it conflicts with automatic signing on SPM packages. Let the export step handle the identity switch.

## Status
**WORKING.** Full pipeline from archive → export → DMG → notarize → staple is functional.
