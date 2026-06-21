#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<'USAGE'
Usage:
  scripts/distribute-testflight-external.sh <build-number> [--groups "Group A,Group B"] [--version "1.0"] [--changelog "Text"]

Examples:
  scripts/distribute-testflight-external.sh 15
  scripts/distribute-testflight-external.sh 15 --groups "External Testing"

Environment:
  APP_STORE_CONNECT_ISSUER_ID defaults to 4827880b-e626-4e8e-a16b-c66db4355e12.
  APP_STORE_CONNECT_KEY_ID defaults to X5SX4S7NW5.
  APP_STORE_CONNECT_KEY_FILEPATH defaults to ~/.appstoreconnect/private_keys/AuthKey_${APP_STORE_CONNECT_KEY_ID}.p8.
  TESTFLIGHT_GROUPS defaults to External Testing.
USAGE
}

args=()
if [[ $# -gt 0 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 1
fi

if [[ "$1" =~ ^[0-9]+$ ]]; then
  args+=("build_number:$1")
  shift
else
  echo "First argument must be the numeric build number." >&2
  usage >&2
  exit 1
fi

while [[ $# -gt 0 ]]; do
  case "$1" in
    --groups)
      args+=("groups:$2")
      shift 2
      ;;
    --version)
      args+=("version:$2")
      shift 2
      ;;
    --changelog)
      args+=("changelog:$2")
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

cd "$ROOT_DIR"
BUNDLE_BIN="${BUNDLE_BIN:-}"
if [[ -z "$BUNDLE_BIN" ]]; then
  if [[ -x /opt/homebrew/opt/ruby/bin/bundle ]]; then
    BUNDLE_BIN=/opt/homebrew/opt/ruby/bin/bundle
  else
    BUNDLE_BIN=bundle
  fi
fi

"$BUNDLE_BIN" check >/dev/null || "$BUNDLE_BIN" install
"$BUNDLE_BIN" exec fastlane ios distribute_existing_external "${args[@]}"
