#!/bin/bash
set -euo pipefail

# Build a Developer ID signed macOS app update for Sparkle.
# Usage:
#   ./scripts/build-macos-sparkle-update.sh
#
# Optional env:
#   APPCAST_BASE_URL=https://ledger-nine4.web.app/sparkle/
#   SPARKLE_BIN=/path/to/Sparkle/bin
#   SPARKLE_RELEASE_NOTES_FILE=/path/to/release-notes.md
#   DEPLOY=1  # run firebase deploy --only hosting after staging files

TEAM_ID="5VHL56HV63"
SCHEME="LedgeriOS"
KEYCHAIN_PROFILE="ledger-notarize"
APPCAST_BASE_URL="${APPCAST_BASE_URL:-https://ledger-nine4.web.app/sparkle/}"
HOSTING_SPARKLE_DIR="${HOSTING_SPARKLE_DIR:-firebase/hosting/sparkle}"
ARCHIVE_PATH="/tmp/LedgeriOS-Sparkle.xcarchive"
EXPORT_PATH="/tmp/LedgeriOS-Sparkle-Export"
EXPORT_PLIST="/tmp/LedgeriOS-Sparkle-ExportOptions.plist"
DERIVED_DATA="/tmp/LedgeriOS-Sparkle-DerivedData-$(date +%s)"
NOTARY_ZIP="/tmp/Ledger-Sparkle-Notary.zip"

cd "$(dirname "$0")/.."
REPO_ROOT="$(pwd)"

find_sparkle_bin() {
  if [ -n "${SPARKLE_BIN:-}" ] && [ -x "$SPARKLE_BIN/generate_appcast" ]; then
    echo "$SPARKLE_BIN"
    return
  fi

  local found
  found="$(find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path '*/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast' \
    -print 2>/dev/null | sort | tail -n 1 || true)"
  if [ -n "$found" ]; then
    dirname "$found"
    return
  fi

  local tmpdir
  tmpdir="$(mktemp -d /tmp/sparkle-tools.XXXXXX)"
  curl -L --fail \
    -o "$tmpdir/Sparkle-2.9.2.tar.xz" \
    https://github.com/sparkle-project/Sparkle/releases/download/2.9.2/Sparkle-2.9.2.tar.xz
  tar -xf "$tmpdir/Sparkle-2.9.2.tar.xz" -C "$tmpdir"
  echo "$tmpdir/bin"
}

echo "==> Cleaning previous build artifacts..."
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$DERIVED_DATA" "$NOTARY_ZIP"

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
xcodebuild archive \
  -project "$REPO_ROOT/LedgeriOS/LedgeriOS.xcodeproj" \
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

APP_PATH="$EXPORT_PATH/LedgeriOS.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP_PATH/Contents/Info.plist")"
ARCHIVE_NAME="Ledger-${VERSION}-${BUILD}.zip"
ARCHIVE_PATH_FINAL="$REPO_ROOT/$HOSTING_SPARKLE_DIR/$ARCHIVE_NAME"
RELEASE_NOTES_PATH="${ARCHIVE_PATH_FINAL%.zip}.md"

echo "==> Notarizing exported app..."
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"
xcrun notarytool submit "$NOTARY_ZIP" \
  --keychain-profile "$KEYCHAIN_PROFILE" \
  --wait

echo "==> Stapling notarization ticket to app..."
xcrun stapler staple "$APP_PATH"

echo "==> Creating Sparkle update archive..."
mkdir -p "$REPO_ROOT/$HOSTING_SPARKLE_DIR"
rm -f "$ARCHIVE_PATH_FINAL"
ditto -c -k --keepParent "$APP_PATH" "$ARCHIVE_PATH_FINAL"

if [ -n "${SPARKLE_RELEASE_NOTES_FILE:-}" ]; then
  cp "$SPARKLE_RELEASE_NOTES_FILE" "$RELEASE_NOTES_PATH"
elif [ ! -f "$RELEASE_NOTES_PATH" ]; then
  cat > "$RELEASE_NOTES_PATH" <<EOF
# Ledger ${VERSION} (${BUILD})

- Maintenance update.
EOF
fi

SPARKLE_BIN_RESOLVED="$(find_sparkle_bin)"

echo "==> Generating Sparkle appcast..."
"$SPARKLE_BIN_RESOLVED/generate_appcast" \
  --download-url-prefix "$APPCAST_BASE_URL" \
  --release-notes-url-prefix "$APPCAST_BASE_URL" \
  -o "$REPO_ROOT/$HOSTING_SPARKLE_DIR/appcast.xml" \
  "$REPO_ROOT/$HOSTING_SPARKLE_DIR"

echo ""
echo "Sparkle update staged:"
echo "  $ARCHIVE_PATH_FINAL"
echo "  $REPO_ROOT/$HOSTING_SPARKLE_DIR/appcast.xml"

if [ "${DEPLOY:-0}" = "1" ]; then
  echo "==> Deploying Firebase Hosting..."
  firebase deploy --only hosting
fi
