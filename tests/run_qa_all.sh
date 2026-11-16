#!/bin/sh
# QA gate (RAT): run every tests/t_*.gd, scripts/net/selftest.gd, scripts/player/smoke_test.gd, and the --quit-after 120 boot check.
# One log per test in $1 (default /tmp/qa/all). Exit code is captured straight from godot (no pipeline).
cd "$(dirname "$0")/.." || exit 2
OUT=${1:-/tmp/qa/all}
mkdir -p "$OUT"
: > "$OUT/summary.txt"
for f in tests/t_*.gd scripts/net/selftest.gd scripts/player/smoke_test.gd; do
	[ -f "$f" ] || continue
	n=$(basename "$f" .gd)
	timeout 280 /home/kali/tools/godot/godot --headless --path . --script "res://$f" > "$OUT/$n.log" 2>&1
	rc=$?
	echo "$n exit=$rc pass=$(grep -c 'PASS' "$OUT/$n.log") fail=$(grep -cE '(^|[^A-Za-z])FAIL' "$OUT/$n.log") script_err=$(grep -cE 'SCRIPT ERROR|Parse Error|Parser Error' "$OUT/$n.log") err=$(grep -c 'ERROR' "$OUT/$n.log")" >> "$OUT/summary.txt"
done
timeout 120 /home/kali/tools/godot/godot --headless --path . --quit-after 120 > "$OUT/boot120.log" 2>&1
rc=$?
echo "boot120 exit=$rc script_err=$(grep -cE 'SCRIPT ERROR|Parse Error|Parser Error' "$OUT/boot120.log") err=$(grep -c 'ERROR' "$OUT/boot120.log")" >> "$OUT/summary.txt"
echo DONE >> "$OUT/summary.txt"
