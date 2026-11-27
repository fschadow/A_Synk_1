extends Node
## LAN-Integrationstest mit zwei echten Godot-Prozessen (Host + Client) auf
## demselben Rechner. Beide zusammen starten:
##   godot --headless --path asynk-rpg res://tests/test_lan.tscn -- --role=host
##   godot --headless --path asynk-rpg res://tests/test_lan.tscn -- --role=client
## (tests/run_lan_test.sh macht das und vergleicht am Ende die Spielstaende.)
##
## Ablauf: Client findet den Host per Suche, tritt bei und legt einen zweiten
## Spieler an (Hotseat) -> Host startet mit 3 Spielern und 5 s Zugzeit ->
## Host zieht, Client zieht, Zeit laeuft fuer Spieler 3 ab -> Client trennt die
## Verbindung -> Spiel pausiert, Host laesst die KI uebernehmen -> Client kommt
## zurueck, bekommt seine Spieler wieder und beendet den Zug.

const TURN_TIME := 5

var _failures := 0
var _role := ""


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		printerr("[%s] FEHLER: %s" % [_role, what])
	else:
		print("[%s] ok: %s" % [_role, what])


func _ready() -> void:
	# Den Testknoten beim Szenenwechsel ins Spiel nicht mitloeschen.
	get_tree().current_scene = null
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr(7)
	if _role == "host":
		await _host()
	elif _role == "client":
		await _client()
	else:
		check(false, "--role=host oder --role=client fehlt")
	print("[%s] LAN-Test: %s" % [_role, "OK" if _failures == 0 else "%d Fehler" % _failures])
	Net.leave()
	get_tree().quit(1 if _failures > 0 else 0)


## Wartet, bis cond() true liefert (oder die Zeit um ist).
func wait_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func state() -> GameState:
	return Net.session.state if Net.session else null


func summary(s: GameState) -> String:
	var parts := ["r%d c%d" % [s.round_number, s.current_player]]
	for p in s.players:
		parts.append("%s@%s %s s%d" % [p["name"], p["pos"], JSON.stringify(p["inv"]), p["steps_left"]])
	return " | ".join(parts)


func free_neighbor(s: GameState) -> Vector2i:
	var me := s.current()
	for c in Net.session.map.neighbors(me["pos"]):
		if not s.occupied_cells(s.current_player).has(c):
			return c
	return me["pos"]


# ---------------------------------------------------------------- Host

func _host() -> void:
	Net.device_id = "test-host"
	check(Net.host_game("Hosti") == "", "Host eroeffnet das Spiel")
	check(await wait_until(func(): return Net.players().size() == 3, 30.0), "Client + Hotseat-Spieler in der Lobby (3)")
	Net.set_turn_time(TURN_TIME)
	Net.start_game()
	check(await wait_until(func(): return state() != null, 10.0), "Host ist im Spiel")
	if state() == null:
		return
	await get_tree().process_frame
	var s := state()
	check(s.players.size() == 3, "3 Spieler im Spielstand")
	var shown := 0
	for agent in get_tree().get_nodes_in_group("hex_agents"):
		if agent.get_parent().visible and agent.player_index < 3:
			shown += 1
	check(shown == 3, "3 Figuren auf der Karte (%d)" % shown)
	check(Net.controls(0) and not Net.controls(1), "Host steuert nur Spieler 1")

	# Zug des Hosts
	await get_tree().create_timer(1.0).timeout  # Client die Szene laden lassen
	var target := free_neighbor(s)
	check(Net.session.request_move_to(target), "Host zieht")
	check(Net.session.request_end_turn(), "Host beendet den Zug")
	check(not Net.session.request_end_turn(), "Host darf fuer den Client nicht beenden")

	# Client zieht und beendet, dann laeuft die Zeit fuer Spieler 3 ab
	check(await wait_until(func(): return s.current_player == 2, 15.0), "Client hat seinen Zug beendet")
	check(s.players[1]["steps_left"] == 0, "Schritte von Spieler 2 sind verbraucht")
	check(await wait_until(func(): return s.round_number == 2 and s.current_player == 0, TURN_TIME + 5.0),
		"Zugzeit von Spieler 3 abgelaufen -> Runde 2")

	# Runde 2: Host beendet sofort, Client trennt die Verbindung
	await get_tree().create_timer(0.5).timeout
	check(Net.session.request_end_turn(), "Host beendet Runde 2")
	check(await wait_until(func(): return Net.is_paused(s), 15.0), "Spiel pausiert, Spieler 2 ist weg")
	await get_tree().create_timer(1.0).timeout
	check(not Net.clock_running(), "Zuguhr steht in der Pause")
	check(s.current_player == 1, "Pause bei Spieler 2")
	Net.set_ai(1, true)
	check(await wait_until(func(): return s.current_player == 2, 20.0), "KI hat den Zug von Spieler 2 gespielt")
	var ai_moves := 0
	for m in s.history:
		if int(m["player"]) == 1 and int(m["round"]) == 2:
			ai_moves += 1
	check(ai_moves >= 1, "KI hat Zuege gemacht (%d)" % ai_moves)
	check(Net.is_paused(s), "Pause bei Spieler 3 (gleiches Geraet, auch weg)")

	# Client kommt zurueck und beendet den Zug von Spieler 3
	check(await wait_until(func(): return s.round_number == 3 and s.current_player == 0, 40.0),
		"Client ist zurueck und hat weitergespielt -> Runde 3")
	var p2 := Net.player_entry(1)
	check(p2["connected"] and not p2["ai"], "Spieler 2 gehoert wieder dem Client (KI aus)")
	print("SUMMARY:", summary(s))
	Net.save_setting("turn_time", 0)  # Testwert nicht als Voreinstellung stehen lassen
	await get_tree().create_timer(2.0).timeout


# -------------------------------------------------------------- Client

func _client() -> void:
	Net.device_id = "test-client"
	Net.discovery.start_search()
	check(await wait_until(func(): return not Net.discovery.host_list().is_empty(), 20.0), "Host per Suche gefunden")
	if Net.discovery.host_list().is_empty():
		return
	var ip: String = Net.discovery.host_list()[0]["ip"]
	Net.discovery.stop_search()
	check(Net.join(ip, "Cli") == "", "Beitreten zu %s" % ip)
	var joined := [false]
	Net.joined.connect(func(): joined[0] = true)
	check(await wait_until(func(): return joined[0], 10.0), "In der Lobby aufgenommen")
	Net.add_local_player("Cli2")
	check(await wait_until(func(): return state() != null, 30.0), "Spiel gestartet")
	if state() == null:
		return
	check(Net.controls(1) and Net.controls(2) and not Net.controls(0), "Client steuert Spieler 2 und 3")

	# Eigener Zug
	check(await wait_until(func(): return state().current_player == 1, 15.0), "Spieler 2 ist dran")
	var s := state()
	var before: Vector2i = s.players[1]["pos"]
	var target := free_neighbor(s)
	check(Net.session.request_move_to(target), "Client schickt Zug")
	check(await wait_until(func(): return s.players[1]["pos"] != before, 5.0), "Host hat den Zug ausgefuehrt")
	# Restliche Schritte verbrauchen, dann beenden
	while s.players[1]["steps_left"] > 0:
		var t := free_neighbor(s)
		var steps: int = s.players[1]["steps_left"]
		Net.session.request_move_to(t)
		if not await wait_until(func(): return s.players[1]["steps_left"] < steps, 5.0):
			break
	check(Net.session.request_end_turn(), "Client beendet den Zug")
	check(await wait_until(func(): return s.current_player == 2, 5.0), "Spieler 3 ist dran (Hotseat am Client)")
	check(Net.time_left() > 0.0, "Client sieht die Zuguhr (%.1f s)" % Net.time_left())

	# Spieler 3 wartet, bis die Zeit abgelaufen ist
	check(await wait_until(func(): return s.round_number == 2, TURN_TIME + 5.0), "Zeit abgelaufen -> Runde 2")
	check(not Net.session.request_end_turn(), "Client darf den Zug des Hosts nicht beenden")

	# Runde 2: Verbindung trennen, sobald Spieler 2 dran ist
	check(await wait_until(func(): return s.current_player == 1, 15.0), "Runde 2, Spieler 2 ist dran")
	Net.leave()
	# Host pausiert, laesst die KI spielen, pausiert dann bei Spieler 3.
	await get_tree().create_timer(14.0).timeout
	check(Net.join(ip, "Cli") == "", "Wieder beitreten")
	check(await wait_until(func(): return state() != null and Net.controls(2), 15.0), "Spielstand zurueck, Spieler 3 gehoert wieder mir")
	if state() == null:
		return
	s = state()
	check(s.round_number == 2 and s.current_player == 2, "Stand nach Wiederbeitritt: Runde 2, Spieler 3")
	check(Net.session.request_end_turn(), "Spieler 3 beendet den Zug")
	check(await wait_until(func(): return s.round_number == 3, 5.0), "Runde 3")
	print("SUMMARY:", summary(s))
