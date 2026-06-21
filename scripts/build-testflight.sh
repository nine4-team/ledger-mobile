#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/LedgeriOS/LedgeriOS.xcodeproj"
PROJECT_FILE="$PROJECT_PATH/project.pbxproj"
SCHEME="LedgeriOS"
CONFIGURATION="Release"
INFO_PLIST="$ROOT_DIR/LedgeriOS/LedgeriOS/Info.plist"
TEAM_ID="5VHL56HV63"
BUILD_DIR="$ROOT_DIR/build/TestFlight"

UPLOAD=true
BUILD_NUMBER=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/build-testflight.sh [build-number] [--no-upload]

Examples:
  scripts/build-testflight.sh
  scripts/build-testflight.sh 14
  scripts/build-testflight.sh --no-upload

By default, the script increments CFBundleVersion and uploads to App Store
Connect using the Apple account signed into Xcode.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --no-upload)
      UPLOAD=false
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      if [[ "$arg" =~ ^[0-9]+$ ]]; then
        BUILD_NUMBER="$arg"
      else
        echo "Unknown argument: $arg" >&2
        usage >&2
        exit 1
      fi
      ;;
  esac
done

CURRENT_BUILD_RAW="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$INFO_PLIST")"
CURRENT_BUILD="$CURRENT_BUILD_RAW"
if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  CURRENT_BUILD="$(awk -F '=|;' '/CURRENT_PROJECT_VERSION = [0-9]+;/ { gsub(/[[:space:]]/, "", $2); print $2; exit }' "$PROJECT_FILE")"
fi
if [[ ! "$CURRENT_BUILD" =~ ^[0-9]+$ ]]; then
  echo "Could not determine numeric build number from CFBundleVersion or CURRENT_PROJECT_VERSION." >&2
  exit 1
fi
if [[ -z "$BUILD_NUMBER" ]]; then
  BUILD_NUMBER="$((CURRENT_BUILD + 1))"
fi

ARCHIVE_PATH="$BUILD_DIR/LedgeriOS-$BUILD_NUMBER.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"

echo "Setting LedgeriOS build number to $BUILD_NUMBER"
if [[ "$CURRENT_BUILD_RAW" =~ ^[0-9]+$ && "$CURRENT_BUILD_RAW" != "$BUILD_NUMBER" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$INFO_PLIST"
fi
perl -0pi -e "s/CURRENT_PROJECT_VERSION = [0-9]+;/CURRENT_PROJECT_VERSION = $BUILD_NUMBER;/g" "$PROJECT_FILE"

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$OPTIONS_PLIST"
mkdir -p "$BUILD_DIR"

DESTINATION="export"
if [[ "$UPLOAD" == true ]]; then
  DESTINATION="upload"
fi

/usr/libexec/PlistBuddy -c 'Clear dict' "$OPTIONS_PLIST" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :destination string $DESTINATION" "$OPTIONS_PLIST"
/usr/libexec/PlistBuddy -c 'Add :manageAppVersionAndBuildNumber bool false' "$OPTIONS_PLIST"
/usr/libexec/PlistBuddy -c 'Add :method string app-store-connect' "$OPTIONS_PLIST"
/usr/libexec/PlistBuddy -c 'Add :signingStyle string automatic' "$OPTIONS_PLIST"
/usr/libexec/PlistBuddy -c "Add :teamID string $TEAM_ID" "$OPTIONS_PLIST"
if [[ "$UPLOAD" == true ]]; then
  /usr/libexec/PlistBuddy -c 'Add :uploadSymbols bool true' "$OPTIONS_PLIST"
fi

echo "Archiving $SCHEME $BUILD_NUMBER"
xcodebuild archive \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE_PATH" \
  -allowProvisioningUpdates

if [[ "$UPLOAD" == true ]]; then
  echo "Uploading $SCHEME $BUILD_NUMBER to App Store Connect"
else
  echo "Exporting $SCHEME $BUILD_NUMBER IPA"
fi

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$OPTIONS_PLIST" \
  -allowProvisioningUpdates

if [[ "$UPLOAD" == true ]]; then
  echo "Uploaded $SCHEME build $BUILD_NUMBER to App Store Connect."
else
  echo "Exported IPA: $EXPORT_PATH/$SCHEME.ipa"
fi
