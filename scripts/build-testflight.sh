#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARGS=(--internal)

for arg in "$@"; do
  case "$arg" in
    --no-upload)
      ARGS=(--no-upload)
      ;;
    -h|--help)
      exec "$ROOT_DIR/scripts/release-testflight.sh" --help
      ;;
    *)
      if [[ "$arg" =~ ^[0-9]+$ ]]; then
        ARGS+=(--build-number "$arg")
      else
        printf 'Unknown argument: %s\n' "$arg" >&2
        exit 2
      fi
      ;;
  esac
done

printf '%s\n' "scripts/build-testflight.sh now uses the preflighted manual-signing release path."
exec "$ROOT_DIR/scripts/release-testflight.sh" "${ARGS[@]}"
