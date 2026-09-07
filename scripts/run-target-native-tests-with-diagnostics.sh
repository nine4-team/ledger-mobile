#!/bin/bash
# Preserve the command and exit status; capture native runner stacks if it stalls.
set -uo pipefail

if [ "$#" -eq 0 ]; then
  echo "A test command is required" >&2
  exit 2
fi

diagnostic_directory="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/ledger-native-diagnostics"
mkdir -p "$diagnostic_directory"
"$@" &
test_pid=$!

(
  sleep 120 &
  delay_pid=$!
  trap 'kill "$delay_pid" 2>/dev/null || true' EXIT
  trap 'exit 0' TERM
  wait "$delay_pid"
  trap - EXIT
  if kill -0 "$test_pid" 2>/dev/null; then
    echo "Native test command still active after 120 seconds; collecting process evidence."
    ps -axo pid,ppid,etime,pcpu,command > "$diagnostic_directory/processes-$test_pid.txt"
    # Walk only descendants of this command, including the Swift Testing helper.
    sample_tree() {
      local candidate="$1"
      local child
      for child in $(pgrep -P "$candidate" || true); do
        sample_tree "$child"
      done
      if kill -0 "$candidate" 2>/dev/null; then
        sample "$candidate" 3 1 -file "$diagnostic_directory/sample-$candidate.txt" || true
        # Keep evidence in the job log even if job cancellation skips artifact upload.
        if [ -f "$diagnostic_directory/sample-$candidate.txt" ]; then
          cat "$diagnostic_directory/sample-$candidate.txt"
        fi
      fi
    }
    sample_tree "$test_pid"
  fi
) &
diagnostic_pid=$!

wait "$test_pid"
test_status=$?
kill "$diagnostic_pid" 2>/dev/null || true
wait "$diagnostic_pid" 2>/dev/null || true
exit "$test_status"
