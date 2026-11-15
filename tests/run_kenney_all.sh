#!/bin/sh
# Kenney asset test (RAT): run every tests/t_*.gd plus selftest and smoke_test, one log each in $1 (default /tmp/kt/all).
cd "$(dirname "$0")/.." || exit 2
OUT=${1:-/tmp/kt/all}
mkdir -p "$OUT"
: > "$OUT/summary.txt"
for f in tests/t_*.gd scripts/net/selftest.gd scripts/player/smoke_test.gd; do
	n=$(basename "$f" .gd)
	timeout 280 /home/kali/tools/godot/godot --headless --path . --script "res://$f" > "$OUT/$n.log" 2>&1
	rc=$?
	echo "$n exit=$rc pass=$(grep -c 'PASS' "$OUT/$n.log") fail=$(grep -c 'FAIL' "$OUT/$n.log") diag=$(grep -cE 'ERROR|WARNING|SCRIPT ERROR|Parse Error' "$OUT/$n.log")" >> "$OUT/summary.txt"
done
echo DONE >> "$OUT/summary.txt"
