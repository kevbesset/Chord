#!/usr/bin/env bash
# The latency gate (docs/PERFORMANCE.md): launches Chord on a fresh data folder, lets it
# replay every measured interaction (open the command bar, toggle the sidebar, switch
# tabs and Spaces, Peek, split view, find, little window), then compares each one's
# median with its budget. Fails when one is over: a feature over budget does not ship.
#
# Chromium is far too big for continuous integration: run it on a Mac before each
# release (docs/RELEASING.md), and after any change to an interaction.
#
#   engine/scripts/perf-gate.sh                  # the development build
#   engine/scripts/perf-gate.sh <path>/Chord.app # another build (a release)
#
# It runs beside the Chord you browse with: its own data folder, its own process.
set -euo pipefail

ENGINE_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ENGINE_DIR/vendor/ungoogled-chromium-macos/build/src/out/Chord/Chord.app}"
[ -x "$APP/Contents/MacOS/Chord" ] || { echo "No Chord at $APP (engine/scripts/build.sh)"; exit 1; }

DATA="$(mktemp -d -t chord-perf)"
trap 'rm -rf "$DATA"' EXIT
REPORT="$DATA/perf.json"

echo "Replaying the interactions in $APP…"
# Without --remote-debugging-port, which would keep the process alive after quitting.
CHORD_PERF_REPORT="$REPORT" "$APP/Contents/MacOS/Chord" \
  --user-data-dir="$DATA/profile" --no-first-run --no-default-browser-check \
  >"$DATA/chord.log" 2>&1 &
PID=$!
for _ in $(seq 1 240); do
  kill -0 "$PID" 2>/dev/null || break
  sleep 0.5
done
if kill -0 "$PID" 2>/dev/null; then
  kill "$PID" 2>/dev/null || true
  echo "Chord did not finish its replay in two minutes (log: kept in $DATA/chord.log)"
  trap - EXIT
  exit 1
fi
[ -f "$REPORT" ] || { echo "No report: the replay did not run (is ChordUI up to date in the app?)"; exit 1; }

python3 - "$REPORT" <<'EOF'
import json, statistics, sys

report = json.load(open(sys.argv[1]))
budgets, measured = report["budgets"], report["measurements"]
failed = []
print(f"{'interaction':<20}{'runs':>6}{'median':>10}{'p90':>10}{'max':>10}{'budget':>10}")
for name in sorted(budgets):
    values = sorted(measured.get(name, []))
    if not values:
        print(f"{name:<20}{'—':>6}{'not measured':>40}")
        continue
    median = statistics.median(values)
    p90 = values[min(len(values) - 1, int(len(values) * 0.9))]
    over = median > budgets[name]
    if over:
        failed.append(name)
    print(f"{name:<20}{len(values):>6}{median:>9.1f}ms{p90:>8.1f}ms{values[-1]:>8.1f}ms{budgets[name]:>8.0f}ms"
          + ("   OVER BUDGET" if over else ""))
if failed:
    print(f"\nOver budget: {', '.join(failed)}")
    sys.exit(1)
print("\nEvery measured interaction is within its budget.")
EOF
