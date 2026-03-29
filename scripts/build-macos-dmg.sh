#!/bin/bash
set -euo pipefail

# Build Ledger macOS DMG installer and save to Desktop
# Usage: ./scripts/build-macos-dmg.sh
#
# Requires:
#   - Developer ID Application certificate in Keychain
#   - App-specific password stored in Keychain (see below)
#
# To store your app-specific password in Keychain (one-time):
#   xcrun notarytool store-credentials "ledger-notarize" \
#     --apple-id team@nine4.co \
#     --team-id 5VHL56HV63 \
#     --password <your-app-specific-password>

TEAM_ID="5VHL56HV63"
SCHEME="LedgeriOS"
ARCHIVE_PATH="/tmp/LedgeriOS.xcarchive"
EXPORT_PATH="/tmp/LedgeriOS-Export"
EXPORT_PLIST="/tmp/ExportOptions.plist"
DERIVED_DATA="/tmp/LedgeriOS-DerivedData-$(date +%s)"
SPARSE_PATH="/tmp/Ledger.sparseimage"
MOUNT_POINT="/tmp/ledger_dmg_mount"
DMG_PATH="/tmp/Ledger.dmg"
DESKTOP_PATH="$HOME/Desktop/Ledger.dmg"
KEYCHAIN_PROFILE="ledger-notarize"

echo "==> Cleaning previous build artifacts..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$SPARSE_PATH" "$DMG_PATH"

echo "==> Writing ExportOptions.plist..."
cat > "$EXPORT_PLIST" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>5VHL56HV63</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF

echo "==> Archiving for macOS..."
cd "$(dirname "$0")/../LedgeriOS"
xcodebuild archive \
  -scheme "$SCHEME" \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE_PATH" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  CODE_SIGN_STYLE=Automatic \
  SDKROOT=macosx \
  ENABLE_HARDENED_RUNTIME=YES \
  -derivedDataPath "$DERIVED_DATA"

echo "==> Exporting with Developer ID signing..."
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_PLIST" \
  -allowProvisioningUpdates

echo "==> Creating DMG..."
# Use sparse image + rsync to avoid com.apple.provenance xattr blocking hdiutil -srcfolder
hdiutil create -size 200m -fs HFS+ -volname "LedgerInstaller" -type SPARSE "$SPARSE_PATH"
hdiutil attach "$SPARSE_PATH" -mountpoint "$MOUNT_POINT"
rsync -a "$EXPORT_PATH/LedgeriOS.app/" "$MOUNT_POINT/Ledger.app/"
hdiutil detach "$MOUNT_POINT"
hdiutil convert "$SPARSE_PATH" -format UDZO -o "$DMG_PATH"
rm -f "$SPARSE_PATH"

echo "==> Notarizing..."
xcrun notarytool submit "$DMG_PATH" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo "==> Copying to Desktop..."
cp -f "$DMG_PATH" "$DESKTOP_PATH"

echo ""
echo "Done! Ledger.dmg is on your Desktop."
