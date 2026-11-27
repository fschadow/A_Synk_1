#!/usr/bin/env bash
# Startet den Test "Spielstand im LAN hosten" mit drei Godot-Prozessen.
#   GODOT=/pfad/zu/godot_console tests/run_lan_resume_test.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
run() { "$GODOT" --headless --path . res://tests/test_lan_resume.tscn -- --role=$1 > "$OUT/$1.txt" 2>&1; }
run host & H=$!
sleep 4
run sub & S=$!
sleep 6
run orig & O=$!
wait $H; HR=$?; wait $S; SR=$?; wait $O; OR=$?
cat "$OUT"/host.txt "$OUT"/sub.txt "$OUT"/orig.txt | grep -E "FEHLER|Resume-Test|SCRIPT ERROR"
echo "Logs: $OUT"
[ $HR -eq 0 ] && [ $SR -eq 0 ] && [ $OR -eq 0 ]
