#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT/LedgeriOS/DerivedData-Codex}"

if [[ -z "${IOS_DESTINATION:-}" ]]; then
  IOS_DESTINATION="$(
    xcrun simctl list devices available --json | node -e '
const fs = require("fs");
const input = fs.readFileSync(0, "utf8");
const parsed = JSON.parse(input);
const devices = [];

for (const [runtime, runtimeDevices] of Object.entries(parsed.devices || {})) {
  for (const device of runtimeDevices || []) {
    if (device.isAvailable && /^iPhone /.test(device.name)) {
      const os = (runtime.match(/iOS-(.*)$/)?.[1] || "").replace(/-/g, ".");
      if (os) devices.push({ name: device.name, os });
    }
  }
}

devices.sort((a, b) => {
  const osCompare = a.os.localeCompare(b.os, undefined, { numeric: true });
  return osCompare || a.name.localeCompare(b.name, undefined, { numeric: true });
});

const selected = devices.at(-1);
if (!selected) {
  console.error("No available iPhone simulator found. Set IOS_DESTINATION explicitly.");
  process.exit(1);
}

console.log(`platform=iOS Simulator,name=${selected.name},OS=${selected.os}`);
'
  )"
fi

echo "Verification profile: taxonomy-model"
echo "No Firebase emulators. No full iOS suite."
echo "Using iOS destination: $IOS_DESTINATION"

echo
echo "== Functions build =="
(cd "$ROOT/firebase/functions" && npm run build)

echo
echo "== MCP build =="
(cd "$ROOT/mcp-server" && npm run build)

echo
echo "== iOS build =="
xcodebuild build \
  -project "$ROOT/LedgeriOS/LedgeriOS.xcodeproj" \
  -scheme LedgeriOS \
  -destination "$IOS_DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH"

echo
echo "== Focused Swift model tests =="
xcodebuild test \
  -project "$ROOT/LedgeriOS/LedgeriOS.xcodeproj" \
  -scheme LedgeriOS \
  -destination "$IOS_DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -only-testing:LedgeriOSTests/ModelCodableTests

echo
echo "taxonomy-model verification passed"
