#!/bin/sh
# Round 5 (RAT): run t_r5_late.gd and fail if the combined host/client log contains any RPC/replication error (D2).
cd "$(dirname "$0")/.." || exit 2
LOG=${1:-/tmp/r5/late.log}
mkdir -p "$(dirname "$LOG")"
timeout 280 /home/kali/tools/godot/godot --headless --path . --script res://tests/t_r5_late.gd > "$LOG" 2>&1
RC=$?
ERRS=$(grep -cE 'cannot see this node|Node not found|not found in cache|"spawner" is null|Attempt to call an RPC' "$LOG")
echo "t_r5_late exit=$RC pass=$(grep -c 'PASS' "$LOG") fail=$(grep -c 'FAIL' "$LOG") rpc_errors=$ERRS"
grep -E 'cannot see this node|Node not found|not found in cache|"spawner" is null|Attempt to call an RPC' "$LOG" | sort | uniq -c | head
[ "$RC" -eq 0 ] && [ "$ERRS" -eq 0 ]
