#!/usr/bin/env bash
# Startet den LAN-Test: Host und Client als zwei Godot-Prozesse, vergleicht
# am Ende die Spielstaende. Aufruf aus dem Repo-Ordner:
#   GODOT=/pfad/zu/godot_console tests/run_lan_test.sh
set -u
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
OUT="$(mktemp -d)"
"$GODOT" --headless --path . res://tests/test_lan.tscn -- --role=host > "$OUT/host.txt" 2>&1 &
HOST=$!
sleep 2
"$GODOT" --headless --path . res://tests/test_lan.tscn -- --role=client > "$OUT/client.txt" 2>&1
CLIENT_RC=$?
wait $HOST
HOST_RC=$?
cat "$OUT/host.txt" "$OUT/client.txt" | grep -E "FEHLER|LAN-Test|SCRIPT ERROR|ERROR"
H=$(grep "^SUMMARY:" "$OUT/host.txt")
C=$(grep "^SUMMARY:" "$OUT/client.txt")
if [ -n "$H" ] && [ "$H" = "$C" ]; then echo "Spielstaende gleich"; else echo "Spielstaende VERSCHIEDEN:"; echo "H $H"; echo "C $C"; HOST_RC=1; fi
echo "Logs: $OUT"
[ $HOST_RC -eq 0 ] && [ $CLIENT_RC -eq 0 ]
