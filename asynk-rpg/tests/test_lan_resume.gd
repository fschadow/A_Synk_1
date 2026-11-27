extends Node
## LAN-Test "Spielstand hosten" mit drei Prozessen (tests/run_lan_resume_test.sh):
## - host: legt ein Spiel mit "Hosti" und "Cli" an (Cli gehoert Geraet test-orig),
##   speichert es und hostet den Spielstand.
## - sub:  tritt zuerst bei und uebernimmt den freien Platz von Cli.
## - orig: tritt danach bei und bekommt Cli zurueck (Vorrang!). sub steigt
##   dann als neuer Spieler "Neu" ein.
## Danach startet der Host: 3 Spieler, jeder steuert den richtigen.

var _failures := 0
var _role := ""


func check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		printerr("[%s] FEHLER: %s" % [_role, what])
	else:
		print("[%s] ok: %s" % [_role, what])


func _ready() -> void:
	get_tree().current_scene = null
	SaveStore.dir = "user://test_saves_resume"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--role="):
			_role = arg.substr(7)
	match _role:
		"host": await _host()
		"sub": await _sub()
		"orig": await _orig()
		_: check(false, "--role fehlt")
	print("[%s] Resume-Test: %s" % [_role, "OK" if _failures == 0 else "%d Fehler" % _failures])
	Net.leave()
	get_tree().quit(1 if _failures > 0 else 0)


func wait_until(cond: Callable, timeout: float) -> bool:
	var end := Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func state() -> GameState:
	return Net.session.state if Net.session else null


func _host() -> void:
	SaveStore.clear_all()
	Net.device_id = "test-host"
	# Spielstand vorbereiten: lokales Spiel mit 2 Spielern, Cli gehoert test-orig.
	Net.start_local("Hosti")
	Net.add_local_player("Cli")
	Net.start_game()
	check(await wait_until(func(): return state() != null, 10.0), "Lokales Spiel gestartet")
	var id: String = Net.lobby["id"]
	Net.players()[1]["orig"] = "test-orig"
	Net.session.request_end_turn()  # etwas Spielverlauf
	Net.leave()
	await get_tree().process_frame
	check(SaveStore.read(id).size() > 0, "Spielstand gespeichert")

	check(Net.host_saved(id) == "", "Spielstand im LAN hosten")
	check(Net.is_resume() and Net.controls(0) and Net.is_free(1), "Hosti belegt, Cli frei")
	check(await wait_until(func(): return Net.player_entry(1)["connected"], 20.0), "sub hat Cli uebernommen")
	var sub_peer := int(Net.player_entry(1)["peer"])
	check(await wait_until(func(): return int(Net.player_entry(1)["peer"]) != sub_peer, 20.0), "orig hat Cli zurueck (Vorrang)")
	check(await wait_until(func(): return Net.players().size() == 3, 15.0), "sub ist als neuer Spieler dazugekommen")
	check(Net.player_entry(2).get("new", false) and Net.player_entry(2)["name"] == "Neu", "Neuer Spieler 'Neu' in der Lobby")
	Net.start_game()
	check(await wait_until(func(): return state() != null, 10.0), "Spiel gestartet")
	if state() == null:
		return
	var s := state()
	check(s.players.size() == 3 and s.players[2]["name"] == "Neu", "Spielstand hat jetzt 3 Spieler")
	check(s.round_number == 1 and s.current_player == 1, "Fortgesetzt beim gespeicherten Stand (Cli ist dran)")
	check(await wait_until(func(): return s.current_player == 2, 15.0), "orig (Cli) hat seinen Zug beendet")
	check(await wait_until(func(): return s.round_number == 2, 15.0), "sub (Neu) hat seinen Zug beendet")
	await get_tree().create_timer(2.0).timeout
	SaveStore.clear_all()


func _join_host(player_name: String) -> bool:
	Net.discovery.start_search()
	if not await wait_until(func(): return not Net.discovery.host_list().is_empty(), 20.0):
		check(false, "Host nicht gefunden")
		return false
	var ip: String = Net.discovery.host_list()[0]["ip"]
	Net.discovery.stop_search()
	var joined := [false]
	Net.joined.connect(func(): joined[0] = true)
	Net.join(ip, player_name)
	return await wait_until(func(): return joined[0], 10.0)


func _sub() -> void:
	Net.device_id = "test-sub"
	check(await _join_host("Ersatz"), "sub: in der Lobby des Spielstands")
	check(Net.is_resume() and Net.is_free(1), "sub sieht Cli als frei")
	Net.take_slot(1)
	check(await wait_until(func(): return Net.controls(1), 5.0), "sub steuert Cli")
	# orig kommt und hat Vorrang
	check(await wait_until(func(): return not Net.controls(1), 25.0), "sub wurde von orig verdraengt")
	Net.add_local_player("Neu")
	check(await wait_until(func(): return Net.players().size() == 3 and Net.controls(2), 5.0), "sub ist jetzt 'Neu'")
	check(await wait_until(func(): return state() != null, 20.0), "sub ist im Spiel")
	if state() == null:
		return
	var s := state()
	check(s.players.size() == 3 and Net.controls(2) and not Net.controls(1), "sub steuert nur 'Neu'")
	check(await wait_until(func(): return s.current_player == 2, 15.0), "'Neu' ist dran")
	check(Net.session.request_end_turn(), "'Neu' beendet den Zug")
	check(await wait_until(func(): return s.round_number == 2, 5.0), "Runde 2")


func _orig() -> void:
	Net.device_id = "test-orig"
	check(await _join_host("Cli"), "orig: in der Lobby")
	check(await wait_until(func(): return Net.controls(1), 5.0), "orig hat Cli automatisch zurueck")
	check(await wait_until(func(): return state() != null, 25.0), "orig ist im Spiel")
	if state() == null:
		return
	var s := state()
	check(Net.controls(1) and not Net.controls(2), "orig steuert Cli")
	check(await wait_until(func(): return s.current_player == 1, 10.0), "Cli ist dran")
	check(Net.session.request_end_turn(), "Cli beendet den Zug")
	check(await wait_until(func(): return s.round_number == 2, 20.0), "Runde 2")
