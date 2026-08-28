#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PREFLIGHT="${LEDGER_SIGNING_PREFLIGHT:-$HOME/.codex/skills/update-testflight/scripts/ledger-signing-preflight.sh}"
WRAPPER="${LEDGER_RELEASE_WRAPPER:-$HOME/.config/ledger-release/with-keychain.sh}"
BUNDLE_BIN="${BUNDLE_BIN:-/opt/homebrew/opt/ruby/bin/bundle}"
RELEASE_PATH="/opt/homebrew/opt/ruby/bin:$PATH"

LANE="external_testflight"
PREFLIGHT_ONLY=false
BUILD_NUMBER=""
VERSION=""
CHANGELOG=""
GROUPS=""

usage() {
  cat <<'USAGE'
Usage:
  scripts/release-testflight.sh [options]

Options:
  --build-number NUMBER  Use an explicit TestFlight build number.
  --version VERSION      Use an explicit marketing version.
  --changelog TEXT       Set TestFlight release notes.
  --groups NAMES         Comma-separated external testing groups.
  --internal             Upload without external distribution.
  --no-upload            Build and export a signed IPA without uploading.
  --preflight-only       Validate signing and exit without building.
  -h, --help             Show this help.

The signing preflight always runs first. Archive and export run through the
dedicated Ledger release keychain with the configured certificate and profile.
USAGE
}

while (($#)); do
  case "$1" in
    --build-number)
      [[ $# -ge 2 ]] || { printf '%s\n' "--build-number requires a value" >&2; exit 2; }
      BUILD_NUMBER="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || { printf '%s\n' "--version requires a value" >&2; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --changelog)
      [[ $# -ge 2 ]] || { printf '%s\n' "--changelog requires a value" >&2; exit 2; }
      CHANGELOG="$2"
      shift 2
      ;;
    --groups)
      [[ $# -ge 2 ]] || { printf '%s\n' "--groups requires a value" >&2; exit 2; }
      GROUPS="$2"
      shift 2
      ;;
    --internal)
      LANE="upload_testflight"
      shift
      ;;
    --no-upload)
      LANE="build_testflight_ipa"
      shift
      ;;
    --preflight-only)
      PREFLIGHT_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -x "$PREFLIGHT" ]] || { printf 'Missing signing preflight: %s\n' "$PREFLIGHT" >&2; exit 1; }
[[ -x "$WRAPPER" ]] || { printf 'Missing release-keychain wrapper: %s\n' "$WRAPPER" >&2; exit 1; }
[[ -x "$BUNDLE_BIN" ]] || { printf 'Missing Bundler executable: %s\n' "$BUNDLE_BIN" >&2; exit 1; }

"$PREFLIGHT"
if [[ "$PREFLIGHT_ONLY" == true ]]; then
  exit 0
fi

cd "$ROOT_DIR"
PATH="$RELEASE_PATH" "$BUNDLE_BIN" check >/dev/null || PATH="$RELEASE_PATH" "$BUNDLE_BIN" install

FASTLANE_ARGS=(ios "$LANE")
[[ -z "$BUILD_NUMBER" ]] || FASTLANE_ARGS+=("build_number:$BUILD_NUMBER")
[[ -z "$VERSION" ]] || FASTLANE_ARGS+=("version:$VERSION")
[[ -z "$CHANGELOG" ]] || FASTLANE_ARGS+=("changelog:$CHANGELOG")
[[ -z "$GROUPS" ]] || FASTLANE_ARGS+=("groups:$GROUPS")

"$WRAPPER" env LEDGER_SIGNING_PREFLIGHT_PASSED=1 PATH="$RELEASE_PATH" "$BUNDLE_BIN" exec fastlane "${FASTLANE_ARGS[@]}"
