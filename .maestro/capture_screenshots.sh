#!/bin/bash
set -e

MAESTRO="$HOME/.maestro/bin/maestro"
DEVICE="booted"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTDIR="$PROJECT_ROOT/reference/screenshots"
FLOW="$PROJECT_ROOT/.maestro/screenshots/capture_all.yaml"

mkdir -p "$OUTDIR/dark" "$OUTDIR/light"

echo "=== Screenshot Capture ==="
echo "Output directory: $OUTDIR"
echo ""

for MODE in dark light; do
  echo "--- Switching to $MODE mode ---"
  xcrun simctl ui $DEVICE appearance $MODE
  sleep 2

  echo "--- Running capture flow in $MODE mode ---"
  # Run from project root so takeScreenshot saves there
  cd "$PROJECT_ROOT"
  "$MAESTRO" test "$FLOW" --no-ansi 2>&1 || {
    echo ""
    echo "WARNING: Some steps may have failed in $MODE mode."
    echo "Screenshots captured before failure are still saved."
    echo ""
  }

  # Move all captured screenshots to the mode-specific folder
  for f in "$PROJECT_ROOT"/*.png; do
    if [ -f "$f" ]; then
      mv "$f" "$OUTDIR/$MODE/"
    fi
  done

  echo "--- $MODE mode complete ---"
  echo ""
done

echo "=== Done ==="
echo ""
echo "Light mode screenshots:"
ls -1 "$OUTDIR/light/" 2>/dev/null || echo "  (none)"
echo ""
echo "Dark mode screenshots:"
ls -1 "$OUTDIR/dark/" 2>/dev/null || echo "  (none)"
echo ""
echo "Total: $(find "$OUTDIR" -name '*.png' | wc -l | tr -d ' ') screenshots"
