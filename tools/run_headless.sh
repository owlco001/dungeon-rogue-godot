#!/usr/bin/env bash
# v0.8 无头门禁（Linux 版，对应 07 方案的 run_headless.bat）
# 用法：tools/run_headless.sh [v1|v2|v3|all]
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-$HOME/workspace/.tools/godot/Godot_v4.7.2-stable_linux.x86_64}"
MODE="${1:-all}"
rc=0

run_v1() {
  echo "== V1 parse gate =="
  "$GODOT" --headless --path . --script res://tools/check_parse.gd > /tmp/dr_v1.log 2>&1
  local e=$?
  grep -E "V1 (checked|RESULT|LOAD FAIL|AUTOLOAD)" /tmp/dr_v1.log || cat /tmp/dr_v1.log
  if [ $e -ne 0 ]; then rc=1; fi
}

run_driver() {
  local m="$1"
  echo "== driver mode $m =="
  rm -f test/result.txt
  "$GODOT" --headless --audio-driver Dummy --path . --script res://test/auto_v08.gd -- "$m" > "/tmp/dr_$m.log" 2>&1
  local e=$?
  cat test/result.txt 2>/dev/null || echo "(no result.txt)"
  if grep -q "SCRIPT ERROR" "/tmp/dr_$m.log"; then
    echo "SCRIPT ERROR found in $m log:"; grep "SCRIPT ERROR" "/tmp/dr_$m.log" | head -5; rc=1
  fi
  if [ $e -ne 0 ]; then rc=1; fi
}

case "$MODE" in
  v1) run_v1 ;;
  v2|v3|v5h|v8|v9|v7|v5) run_driver "$MODE" ;;
  v3x) run_driver v3; run_driver v3setup; run_driver v3check ;;
  all) run_v1; run_driver v2; run_driver v3; run_driver v3setup; run_driver v3check; run_driver v5h; run_driver v5; run_driver v7; run_driver v8; run_driver v9 ;;
  *) echo "unknown mode $MODE"; exit 2 ;;
esac
echo "GATES RESULT: $([ $rc -eq 0 ] && echo PASS || echo FAIL)"
exit $rc
